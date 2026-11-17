-- Explicit owner-selected seasons. No game is assigned automatically.
begin;
create table public.web_seasons(
 id uuid primary key,team_id uuid not null references public.teams(id),name text not null check(length(btrim(name)) between 1 and 100),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),unique(team_id,id)
);
create table public.web_season_games(
 team_id uuid not null,game_id uuid not null,season_id uuid not null,assigned_by uuid not null references auth.users(id),assigned_at timestamptz not null default now(),
 primary key(team_id,game_id),foreign key(team_id,game_id) references public.games(team_id,id),foreign key(team_id,season_id) references public.web_seasons(team_id,id)
);
alter table public.web_seasons enable row level security;
alter table public.web_season_games enable row level security;
create policy seasons_read on public.web_seasons for select to authenticated using(team_private.can_read(team_id));
create policy season_games_read on public.web_season_games for select to authenticated using(team_private.can_read(team_id));
grant select on public.web_seasons,public.web_season_games to authenticated;
create function public.team_save_season(p_team_id uuid,p_season_id uuid,p_name text,p_expected_access_revision bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.command_actor(p_team_id,p_expected_access_revision);s public.web_seasons;
begin
 if not team_private.is_owner(p_team_id,a) then raise exception 'Owner season setup required' using errcode='42501';end if;
 if p_season_id is null or p_name is null or length(btrim(p_name)) not between 1 and 100 then raise exception 'Season identity and name required' using errcode='22023';end if;
 select * into s from public.web_seasons where id=p_season_id for update;
 if found and s.team_id<>p_team_id then raise exception 'Wrong team season' using errcode='42501';end if;
 insert into public.web_seasons(id,team_id,name,created_by) values(p_season_id,p_team_id,btrim(p_name),a) on conflict(id) do update set name=excluded.name where public.web_seasons.team_id=excluded.team_id returning * into s;
 if not found then raise exception 'Wrong team season' using errcode='42501';end if;
 perform team_private.audit(p_team_id,a,'season.saved',s.id);perform team_private.advance_access_revision(p_team_id);return to_jsonb(s);
end $$;
create function public.team_assign_season_game(p_team_id uuid,p_season_id uuid,p_game_id uuid,p_expected_season_id uuid,p_expected_access_revision bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.command_actor(p_team_id,p_expected_access_revision);old_season uuid;r public.web_season_games;
begin
 if not team_private.is_owner(p_team_id,a) then raise exception 'Owner season assignment required' using errcode='42501';end if;
 if not exists(select 1 from public.web_seasons where team_id=p_team_id and id=p_season_id) or not exists(select 1 from public.games where team_id=p_team_id and id=p_game_id) then raise exception 'Same-team season and game required' using errcode='42501';end if;
 select season_id into old_season from public.web_season_games where team_id=p_team_id and game_id=p_game_id for update;
 if old_season is distinct from p_expected_season_id then raise exception 'Season assignment changed; reload' using errcode='PT409';end if;
 insert into public.web_season_games(team_id,game_id,season_id,assigned_by) values(p_team_id,p_game_id,p_season_id,a) on conflict(team_id,game_id) do update set season_id=excluded.season_id,assigned_by=a,assigned_at=clock_timestamp() returning * into r;
 perform team_private.audit(p_team_id,a,'season.game_assigned',p_game_id,p_season_id::text);perform team_private.advance_access_revision(p_team_id);return to_jsonb(r);
end $$;
-- One statement reads a coherent set of accepted pointers; no author/session credentials are projected.
create function public.web_results(p_team_id uuid,p_season_id uuid default null,p_game_id uuid default null) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id);result jsonb;
begin
 if (p_season_id is null)=(p_game_id is null) then raise exception 'Choose one season or game' using errcode='22023';end if;
 if p_season_id is not null and not exists(select 1 from public.web_seasons where team_id=p_team_id and id=p_season_id) or p_game_id is not null and not exists(select 1 from public.games where team_id=p_team_id and id=p_game_id) then raise exception 'Results scope unavailable' using errcode='42501';end if;
 with games as (
  select g.id,g.team_id,g.date,g.opponent,g.home_away,g.game_type from public.games g where g.team_id=p_team_id and
  (g.id=p_game_id or exists(select 1 from public.web_season_games sg where sg.team_id=p_team_id and sg.game_id=g.id and sg.season_id=p_season_id))
 ), versions as (
  select v.id,v.game_id,v.dataset_type,v.records,v.covered_roster from public.stat_datasets d join public.stat_versions v on v.id=d.published_version_id and v.dataset_id=d.id and v.game_id=d.game_id and v.team_id=d.team_id join games g on g.id=d.game_id where d.team_id=p_team_id and v.status='published'
 ), charts as (
  select s.id,s.game_id,s.title,s.accepted_snapshot_id as snapshot_id,x.document->'session'->'players' as players,
   (select coalesce(jsonb_agg(last_change->'after' order by event_id),'[]') from (
    select distinct on (change->>'eventID') change as last_change,change->>'eventID' as event_id from jsonb_array_elements(x.document->'session'->'changes') with ordinality as entry(change,n) order by change->>'eventID',n desc
   ) latest where last_change->'after'<>'null'::jsonb) as events
  from public.web_sessions s join public.web_session_snapshots x on x.id=s.accepted_snapshot_id and x.team_id=s.team_id and x.session_id=s.id join games g on g.id=s.game_id where s.team_id=p_team_id and s.kind='game'
 )
 select jsonb_build_object('games',coalesce((select jsonb_agg(to_jsonb(g) order by g.date,g.id) from games g),'[]'),
 'versions',coalesce((select jsonb_agg(to_jsonb(v) order by v.game_id,v.dataset_type) from versions v),'[]'),
 'charts',coalesce((select jsonb_agg(to_jsonb(c) order by c.game_id,c.id) from charts c),'[]')) into result;
 if octet_length(result::text)>4194304 then raise exception 'Results exceed the display limit; choose an individual game' using errcode='22023';end if;
 return result;
end $$;
revoke all on function public.team_save_season(uuid,uuid,text,bigint),public.team_assign_season_game(uuid,uuid,uuid,uuid,bigint),public.web_results(uuid,uuid,uuid) from public,anon;
grant execute on function public.team_save_season(uuid,uuid,text,bigint),public.team_assign_season_game(uuid,uuid,uuid,uuid,bigint),public.web_results(uuid,uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
