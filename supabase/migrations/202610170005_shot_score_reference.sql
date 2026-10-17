-- Separate independently confirmed score reference; no statistics overwrite/export.
begin;
create table team_private.shot_score_references (
 id uuid primary key,team_id uuid not null,game_id uuid not null,revision bigint not null,
 actor_user_id uuid not null references auth.users(id),expected_revision bigint not null,
 our_points integer check(our_points>=0),opponent_points integer check(opponent_points>=0),
 source_note text not null check(length(btrim(source_note)) between 1 and 200),created_at timestamptz not null default now(),
 unique(game_id,revision),foreign key(team_id,game_id) references public.games(team_id,id)
);
alter table team_private.shot_score_references enable row level security;
revoke all on team_private.shot_score_references from public,anon,authenticated,service_role;
create trigger shot_score_reference_immutable before update or delete on team_private.shot_score_references for each row execute function team_private.append_only();
create function public.shots_score_read(p_team_id uuid,p_game_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);v team_private.shot_score_references;
begin
 if not exists(select 1 from public.games where team_id=p_team_id and id=p_game_id) then raise exception 'Game access denied' using errcode='42501';end if;
 select * into v from team_private.shot_score_references where team_id=p_team_id and game_id=p_game_id order by revision desc limit 1;
 return jsonb_build_object('team_id',p_team_id,'game_id',p_game_id,'revision',coalesce(v.revision,0),'reference_id',v.id,'our_points',v.our_points,'opponent_points',v.opponent_points,'source_note',v.source_note,'can_confirm',team_private.has_capability(p_team_id,a,'stats.review'));
end $$;
create function public.shots_score_confirm(p_team_id uuid,p_game_id uuid,p_expected_revision bigint,p_batch_id uuid,p_our_points integer,p_opponent_points integer,p_source_note text) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);v team_private.shot_score_references;current_revision bigint;
begin
 if not team_private.has_capability(p_team_id,a,'stats.review') then raise exception 'Official statistics review authority required' using errcode='42501';end if;
 perform 1 from public.games where team_id=p_team_id and id=p_game_id for update;
 if not found then raise exception 'Game access denied' using errcode='42501';end if;
 if p_batch_id is null or p_batch_id='00000000-0000-0000-0000-000000000000' or p_expected_revision is null or p_expected_revision<0
  or (p_our_points is null and p_opponent_points is null) or p_our_points<0 or p_opponent_points<0 or p_source_note is null or length(btrim(p_source_note)) not between 1 and 200 then raise exception 'Independent confirmed score and source required' using errcode='22023';end if;
 select * into v from team_private.shot_score_references where id=p_batch_id;
 if found then
  if (v.team_id,v.game_id,v.actor_user_id,v.expected_revision,v.our_points,v.opponent_points,v.source_note) is distinct from
   (p_team_id,p_game_id,a,p_expected_revision,p_our_points,p_opponent_points,p_source_note) then raise exception 'Score command identity conflict' using errcode='PT409';end if;
 else
  select coalesce(max(revision),0) into current_revision from team_private.shot_score_references where game_id=p_game_id;
  if current_revision<>p_expected_revision then raise exception 'Score reference changed' using errcode='PT409';end if;
  if team_private.shot_actor(p_team_id) is distinct from a or not team_private.has_capability(p_team_id,a,'stats.review') then raise exception 'Current statistics review authority required' using errcode='42501';end if;
  insert into team_private.shot_score_references(id,team_id,game_id,revision,actor_user_id,expected_revision,our_points,opponent_points,source_note)
  values(p_batch_id,p_team_id,p_game_id,current_revision+1,a,p_expected_revision,p_our_points,p_opponent_points,p_source_note) returning * into v;
  perform team_private.audit(p_team_id,a,'shots.score_confirm',p_batch_id);
 end if;
 return jsonb_build_object('batch_id',p_batch_id,'operation','score_confirm','team_id',p_team_id,'game_id',p_game_id,'actor_user_id',a,'score_revision',v.revision);
end $$;
create function public.shots_score_receipt(p_team_id uuid,p_game_id uuid,p_batch_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.shot_actor(p_team_id);v team_private.shot_score_references;
begin
 if not team_private.has_capability(p_team_id,a,'stats.review') then raise exception 'Current statistics review authority required' using errcode='42501';end if;
 select * into v from team_private.shot_score_references where id=p_batch_id and team_id=p_team_id and game_id=p_game_id and actor_user_id=a;
 if not found then return null;end if;
 return jsonb_build_object('batch_id',p_batch_id,'operation','score_confirm','team_id',p_team_id,'game_id',p_game_id,'actor_user_id',a,'score_revision',v.revision);
end $$;
revoke all on function public.shots_score_read(uuid,uuid),public.shots_score_confirm(uuid,uuid,bigint,uuid,integer,integer,text),public.shots_score_receipt(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.shots_score_read(uuid,uuid),public.shots_score_confirm(uuid,uuid,bigint,uuid,integer,integer,text),public.shots_score_receipt(uuid,uuid,uuid) to authenticated;
commit;
