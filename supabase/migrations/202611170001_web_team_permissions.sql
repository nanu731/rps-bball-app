-- Prospective web permissions. No existing memberships, grants or accepted history change.
begin;
create or replace function team_private.capabilities() returns text[] language sql immutable
set search_path=pg_catalog as $$ select array['stats.record','stats.review','stats.publish','datasets.reopen','roster.manage','members.manage','plays.author','plays.review','plays.publish','practice.upload','practice.review','practice.publish','film.upload','film.review','film.publish','scouting.upload','scouting.read','shots.record','shots.review','shots.publish','sessions.manage','sessions.record','sessions.review','sessions.publish','sessions.reopen','sessions.clock','plans.manage']::text[] $$;
create function team_private.staff_preset() returns text[] language sql immutable set search_path=pg_catalog as $$
 select array['stats.record','stats.review','stats.publish','datasets.reopen','sessions.manage','sessions.record','sessions.review','sessions.publish','sessions.reopen','sessions.clock','plans.manage']::text[]
$$;
create function team_private.statistics_actor(p_team uuid) returns uuid language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team);
begin
 if not team_private.has_capability(p_team,a,'stats.record') then raise exception 'Statistics entry access required' using errcode='42501'; end if;
 return a;
end $$;
-- Replace only the common actor guard on the explicit manual-entry command list.
-- Fail on drift instead of modifying an unexpected function body.
do $$
declare name text; signature regprocedure; definition text;
begin
 foreach name in array array['stats_create_game','stats_open_draft','stats_save_draft','stats_save_drafts','stats_complete','stats_submit','stats_request_edit'] loop
  select p.oid::regprocedure into strict signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=name;
  definition:=pg_get_functiondef(signature);
  if position('team_private.member_actor(p_team_id)' in definition)=0 then raise exception 'Unexpected statistics actor guard: %',name; end if;
  execute replace(definition,'team_private.member_actor(p_team_id)','team_private.statistics_actor(p_team_id)');
 end loop;
end $$;
create or replace function team_private.stat_visible(p_team uuid,p_author uuid,p_status text) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.can_read(p_team) and (p_status='published' or
 (p_author=team_private.actor() and team_private.has_capability(p_team,team_private.actor(),'stats.record')) or
 (p_status in ('submitted','rejected') and team_private.has_capability(p_team,team_private.actor(),'stats.review')))
$$;
-- Authorized staff may verify their own statistics; historical review actors remain untouched.
create or replace function public.stats_publish(p_team_id uuid,p_version_id uuid,p_expected_revision bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id);v public.stat_versions;
begin
 v:=team_private.lock_stat(p_team_id,p_version_id,p_expected_revision);
 if v.author_user_id<>a or v.status not in ('completed','submitted') or not team_private.has_capability(p_team_id,a,'stats.publish') then raise exception 'Author publication access required' using errcode='42501';end if;
 v:=team_private.accept_stat(v,a,'');return to_jsonb(v);
end $$;
create or replace function public.stats_review(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_approve boolean,p_reason text default '') returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id);v public.stat_versions;
begin
 v:=team_private.lock_stat(p_team_id,p_version_id,p_expected_revision);
 if v.status<>'submitted' or not team_private.has_capability(p_team_id,a,'stats.review') then raise exception 'Statistic verification access required' using errcode='42501';end if;
 if p_approve is null or p_reason is null or length(p_reason)>500 then raise exception 'Invalid review decision' using errcode='22023';end if;
 if p_approve then v:=team_private.accept_stat(v,a,p_reason);
 else update public.stat_versions set status='rejected',revision=revision+1,updated_at=now(),review_actor_user_id=a,review_reason=p_reason where id=v.id returning * into v;perform team_private.audit(p_team_id,a,'stats.rejected',v.id);end if;
 return to_jsonb(v);
end $$;
do $$
declare definition text; old_guard text:='if p_action=''review'' and actor=any(s.contributors) and not team_private.is_owner(p_team_id,actor) then raise exception ''Independent reviewer required'' using errcode=''42501'';end if;';
begin
 definition:=pg_get_functiondef('public.web_session_command(uuid,uuid,text,uuid,bigint,bigint,jsonb,jsonb)'::regprocedure);
 if position(old_guard in definition)=0 then raise exception 'Unexpected session review guard';end if;
 execute replace(definition,old_guard,'-- Authorized statistics self-verification; the publication retains accepted_by.');
end $$;
create or replace function team_private.web_read_snapshot(p_team uuid,p_session uuid,p_snapshot uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.can_read(p_team) and (exists(select 1 from public.web_session_publications where team_id=p_team and session_id=p_session and snapshot_id=p_snapshot) or
 (team_private.has_capability(p_team,team_private.actor(),'sessions.record') and exists(select 1 from public.web_sessions s where s.team_id=p_team and s.id=p_session and (team_private.actor()=s.author_user_id or team_private.actor()=s.recorder_user_id or team_private.actor()=any(s.contributors)))) or
 team_private.has_capability(p_team,team_private.actor(),'sessions.manage') or team_private.has_capability(p_team,team_private.actor(),'sessions.review') or team_private.has_capability(p_team,team_private.actor(),'sessions.reopen'))
$$;
create or replace function public.team_access(p_team_id uuid) returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.actor();caps jsonb;envelopes jsonb;
begin
 if a is null or not team_private.is_active(p_team_id,a) then raise exception 'Active membership required' using errcode='42501';end if;
 select coalesce(jsonb_agg(c),'[]'::jsonb) into caps from unnest(team_private.capabilities()) c where team_private.has_capability(p_team_id,a,c);
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'allowed_capabilities',allowed_capabilities,'expires_at',expires_at)),'[]'::jsonb) into envelopes from public.delegation_envelopes where team_id=p_team_id and delegate_user_id=a and revoked_at is null and expires_at>clock_timestamp();
 return jsonb_build_object('team_id',p_team_id,'user_id',a,'is_owner',team_private.is_owner(p_team_id,a),'can_propose_stats',team_private.has_capability(p_team_id,a,'stats.record'),'capabilities',caps,'grant_envelopes',envelopes,'access_revision',(select access_revision from public.teams where id=p_team_id));
end $$;
create function public.team_apply_staff_preset(p_team_id uuid,p_user_id uuid,p_role text,p_expected_access_revision bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.command_actor(p_team_id,p_expected_access_revision);cap text;
begin
 if not team_private.is_owner(p_team_id,a) or p_user_id=a or not team_private.is_active(p_team_id,p_user_id) or p_role is null or p_role not in ('player','coach','manager') then raise exception 'Owner and existing active nonowner required' using errcode='42501';end if;
 if p_role='player' and (exists(select 1 from public.capability_grants g where g.team_id=p_team_id and g.user_id=p_user_id and g.revoked_at is null and (g.expires_at is null or g.expires_at>clock_timestamp()) and not(g.capability=any(team_private.staff_preset()))) or exists(select 1 from public.delegation_envelopes e where e.team_id=p_team_id and e.delegate_user_id=p_user_id and e.revoked_at is null and e.expires_at>clock_timestamp())) then raise exception 'Remove separate administration or content authority before applying player preset' using errcode='42501';end if;
 -- Presets affect only these web capabilities, retaining unrelated grants and audit history.
 update public.capability_grants set revoked_at=clock_timestamp() where team_id=p_team_id and user_id=p_user_id and revoked_at is null and capability=any(team_private.staff_preset());
 if p_role in ('coach','manager') then
  foreach cap in array team_private.staff_preset() loop insert into public.capability_grants(team_id,user_id,capability,issued_by) values(p_team_id,p_user_id,cap,a);end loop;
 end if;
 perform team_private.audit(p_team_id,a,'team.preset.'||p_role,p_user_id);
 perform team_private.advance_access_revision(p_team_id);
 return public.team_access(p_team_id);
end $$;
create table public.team_player_accounts(
 team_id uuid not null references public.teams(id),player_id uuid not null,user_id uuid not null,
 linked_by uuid not null references auth.users(id),linked_at timestamptz not null default now(),
 primary key(team_id,user_id),unique(team_id,player_id),
 foreign key(team_id,player_id) references public.roster_entries(team_id,id),
 foreign key(team_id,user_id) references public.team_memberships(team_id,user_id)
);
alter table public.team_player_accounts enable row level security;
create function team_private.player_account_visible(t uuid,u uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$ select team_private.can_read(t) and (u=team_private.actor() or team_private.is_owner(t,team_private.actor())) $$;
revoke all on function team_private.player_account_visible(uuid,uuid) from public,anon;
grant execute on function team_private.player_account_visible(uuid,uuid) to authenticated;
create policy player_account_read on public.team_player_accounts for select to authenticated using(team_private.player_account_visible(team_id,user_id));
revoke all on public.team_player_accounts from public,anon,authenticated;
grant select(team_id,player_id,user_id) on public.team_player_accounts to authenticated;
create function public.team_link_player_account(p_team_id uuid,p_user_id uuid,p_player_id uuid,p_expected_access_revision bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.command_actor(p_team_id,p_expected_access_revision);result public.team_player_accounts;
begin
 if not team_private.is_owner(p_team_id,a) or not team_private.is_active(p_team_id,p_user_id) or not exists(select 1 from public.roster_entries where id=p_player_id and team_id=p_team_id and archived_at is null) then raise exception 'Owner and active same-team identities required' using errcode='42501';end if;
 if exists(select 1 from public.team_player_accounts where team_id=p_team_id and user_id=p_user_id and player_id<>p_player_id) then raise exception 'Existing player link requires explicit reviewed correction' using errcode='PT409';end if;
 insert into public.team_player_accounts(team_id,player_id,user_id,linked_by) values(p_team_id,p_player_id,p_user_id,a) on conflict(team_id,user_id) do nothing;
 select * into result from public.team_player_accounts where team_id=p_team_id and user_id=p_user_id;
 perform team_private.audit(p_team_id,a,'roster.account_linked',p_player_id);perform team_private.advance_access_revision(p_team_id);
 return to_jsonb(result);
end $$;
revoke all on function team_private.staff_preset(),team_private.statistics_actor(uuid) from public,anon,authenticated;
revoke all on function public.team_apply_staff_preset(uuid,uuid,text,bigint),public.team_link_player_account(uuid,uuid,uuid,bigint) from public,anon;
grant execute on function public.team_apply_staff_preset(uuid,uuid,text,bigint),public.team_link_player_account(uuid,uuid,uuid,bigint) to authenticated;
notify pgrst,'reload schema';
commit;
