-- Practice-plan PDFs extend the existing private file contract; delivery stays fail-closed.
begin;
alter table public.file_resources add column practice_id uuid;
alter table public.file_resources add foreign key(team_id,practice_id) references public.web_sessions(team_id,id);
alter table public.file_resources drop constraint file_resources_kind_check,drop constraint file_resources_check;
alter table public.file_resources add check(kind in ('practice','scouting','practice_plan'));
alter table public.file_resources add check((kind='practice' and play_id is not null and game_id is null and practice_id is null) or (kind='scouting' and game_id is not null and play_id is null and practice_id is null) or (kind='practice_plan' and practice_id is not null and play_id is null and game_id is null));
create unique index one_practice_plan_resource on public.file_resources(team_id,practice_id) where kind='practice_plan';
create table public.web_practice_plan_versions(
 id uuid primary key default gen_random_uuid(),team_id uuid not null,practice_id uuid not null,revision bigint not null,
 kind text not null check(kind in ('builder','pdf')),builder jsonb,pdf_version_id uuid references public.file_resource_versions(id),source_snapshot_id uuid,
 author_user_id uuid not null references auth.users(id),shared_by uuid not null references auth.users(id),shared_at timestamptz not null default clock_timestamp(),operation_id uuid not null unique,
 foreign key(team_id,practice_id) references public.web_sessions(team_id,id),unique(team_id,practice_id,id),unique(practice_id,revision),
 check((kind='builder' and builder is not null and pdf_version_id is null and source_snapshot_id is not null) or (kind='pdf' and builder is null and pdf_version_id is not null and source_snapshot_id is null))
);
create trigger plan_version_append_only before update or delete on public.web_practice_plan_versions for each row execute function team_private.append_only();
alter table public.web_sessions add column shared_plan_id uuid;
alter table public.web_sessions add foreign key(team_id,id,shared_plan_id) references public.web_practice_plan_versions(team_id,practice_id,id);
alter table public.web_practice_plan_versions enable row level security;
create policy shared_plan_read on public.web_practice_plan_versions for select to authenticated using(team_private.can_read(team_id));
-- Ordinary viewers need plan contents, not staff Auth identifiers.
grant select(id,team_id,practice_id,revision,kind,builder,pdf_version_id,shared_at) on public.web_practice_plan_versions to authenticated;
create or replace function team_private.file_resource_guard() returns trigger language plpgsql set search_path=pg_catalog as $$begin
 if tg_op='DELETE' or new.id<>old.id or new.team_id<>old.team_id or new.kind<>old.kind or new.play_id is distinct from old.play_id or new.game_id is distinct from old.game_id or new.practice_id is distinct from old.practice_id then raise exception 'Private file linkage is immutable' using errcode='42501';end if;return new;end$$;
create or replace function team_private.file_eligible(t uuid,a uuid,k text) returns boolean language sql stable security definer set search_path=pg_catalog as $$ select team_private.is_active(t,a) and (k='practice' or (k='scouting' and team_private.has_capability(t,a,'scouting.upload')) or (k='practice_plan' and team_private.has_capability(t,a,'plans.manage'))) $$;
create or replace function team_private.file_can_fetch(t uuid,v uuid,a uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.is_active(t,a) and exists(select 1 from public.file_resource_versions x join public.file_resources r on r.id=x.resource_id
 where x.id=v and x.team_id=t and x.byte_count is not null and (team_private.is_owner(t,a) or
 (r.archived_at is null and ((x.author_user_id=a and team_private.file_eligible(t,a,r.kind) and (x.status in ('ready','submitted') or (r.kind='practice' and x.status='rejected'))) or
 ((r.published_version_id=x.id or (r.kind='practice_plan' and exists(select 1 from public.web_practice_plan_versions pv where pv.team_id=t and pv.practice_id=r.practice_id and pv.pdf_version_id=x.id))) and x.status='published' and (r.kind in ('practice','practice_plan') or team_private.has_capability(t,a,'scouting.read')))))))
$$;
create or replace function team_private.file_visible(t uuid,v uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.can_read(t) and exists(select 1 from public.file_resource_versions x join public.file_resources r on r.id=x.resource_id where x.id=v and x.team_id=t
 and (team_private.is_owner(t,team_private.actor()) or (r.kind='practice_plan' and team_private.has_capability(t,team_private.actor(),'plans.manage')) or (r.archived_at is null and
 ((x.author_user_id=team_private.actor() and team_private.file_eligible(t,team_private.actor(),r.kind) and ((r.kind='practice' and x.status<>'published') or (r.kind in ('scouting','practice_plan') and x.status in ('uploading','ready','submitted','failed')))) or ((r.published_version_id=x.id or (r.kind='practice_plan' and exists(select 1 from public.web_practice_plan_versions pv where pv.team_id=t and pv.practice_id=r.practice_id and pv.pdf_version_id=x.id))) and x.status='published' and (r.kind in ('practice','practice_plan') or team_private.has_capability(t,team_private.actor(),'scouting.read')))))))
$$;
create or replace function public.file_reserve(p_team_id uuid,p_resource_id uuid,p_kind text,p_target_id uuid,p_operation_id uuid,p_declared_bytes bigint,p_title text,p_notes text default '',p_base_published_version_id uuid default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare a uuid; r public.file_resources;v public.file_resource_versions;begin
 -- Across teams, the same account cannot race the one-active-upload limit.
 a:=team_private.actor();if a is null then raise exception 'Verified session required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(a::text,370));a:=team_private.member_actor(p_team_id);
 if not team_private.file_eligible(p_team_id,a,p_kind) then raise exception 'Private file contribution denied' using errcode='42501';end if;
 if p_resource_id is null or p_target_id is null or p_operation_id is null or p_kind is null or p_kind not in ('practice','scouting','practice_plan') or p_declared_bytes is null or p_declared_bytes<1 or p_declared_bytes>(case when p_kind in ('scouting','practice_plan') then 5242880 else 10485760 end) or p_title is null or length(p_title)>120 or p_notes is null or length(p_notes)>1000 or p_title~'[[:cntrl:]]' or p_notes~'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' then raise exception 'Valid bounded private file fields required' using errcode='22023';end if;
 select * into v from public.file_resource_versions where operation_id=p_operation_id;
 if found then
  select * into r from public.file_resources where id=v.resource_id;
  if v.author_user_id<>a or v.team_id<>p_team_id or r.id<>p_resource_id or r.kind<>p_kind or coalesce(r.play_id,r.game_id,r.practice_id)<>p_target_id or v.declared_bytes<>p_declared_bytes or v.base_published_version_id is distinct from p_base_published_version_id then raise exception 'Upload operation already has different content or identity' using errcode='PT409';end if;return to_jsonb(v);
 end if;
 if (p_kind='practice' and not exists(select 1 from public.plays where id=p_target_id and team_id=p_team_id and published_version_id is not null)) or (p_kind='scouting' and not exists(select 1 from public.games where id=p_target_id and team_id=p_team_id)) or (p_kind='practice_plan' and not exists(select 1 from public.web_sessions where id=p_target_id and team_id=p_team_id and kind='practice')) then raise exception 'Existing authorized play, game or practice required' using errcode='22023';end if;
 select * into r from public.file_resources where id=p_resource_id for update;
 if found then
  if r.team_id<>p_team_id or r.kind<>p_kind or coalesce(r.play_id,r.game_id,r.practice_id)<>p_target_id or r.archived_at is not null then raise exception 'Private resource linkage unavailable' using errcode='42501';end if;
  if r.published_version_id is distinct from p_base_published_version_id then raise exception 'Published private file changed; reload' using errcode='PT409';end if;
 else
  if p_base_published_version_id is not null then raise exception 'New resource cannot have a source' using errcode='22023';end if;
  insert into public.file_resources(id,team_id,kind,play_id,game_id,practice_id) values(p_resource_id,p_team_id,p_kind,case when p_kind='practice' then p_target_id end,case when p_kind='scouting' then p_target_id end,case when p_kind='practice_plan' then p_target_id end) returning * into r;
 end if;
 -- Expiry permits another attempt, but never releases the old reservation/occupied bytes.
 update team_private.file_uploads set state='interrupted' where actor_id=a and state in ('reserved','uncertain') and expires_at<=clock_timestamp();
 if exists(select 1 from team_private.file_uploads where actor_id=a and state in ('reserved','uncertain')) then raise exception 'Another upload is active; reconcile it before starting another' using errcode='PT409';end if;
 perform team_private.file_budget_lock(p_declared_bytes,false);
 insert into public.file_resource_versions(team_id,resource_id,author_user_id,operation_id,title,notes,declared_bytes,base_published_version_id) values(p_team_id,r.id,a,p_operation_id,p_title,p_notes,p_declared_bytes,r.published_version_id) returning * into v;
 insert into team_private.file_uploads(operation_id,version_id,actor_id,session_id,jwt_expires_at,reserved_bytes,object_path) values(p_operation_id,v.id,a,(auth.jwt()->>'session_id')::uuid,to_timestamp((auth.jwt()->>'exp')::double precision),p_declared_bytes,p_team_id::text||'/'||r.id::text||'/'||v.id::text);
 perform team_private.audit(p_team_id,a,'file.reserved',v.id);return to_jsonb(v);
end$$;
create or replace function public.file_transition(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_action text,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare a uuid:=team_private.member_actor(p_team_id);v public.file_resource_versions;r public.file_resources;ns text;begin
 select * into v from public.file_resource_versions where id=p_version_id and team_id=p_team_id for update;select * into r from public.file_resources where id=v.resource_id for update;
 if v.id is null or r.archived_at is not null then raise exception 'Private file unavailable' using errcode='42501';end if;
 if p_expected_revision is distinct from v.revision then raise exception 'Private file revision changed; reload' using errcode='PT409';end if;
 if p_action in ('submit','publish') then
  if v.author_user_id<>a or v.status<>'ready' or not team_private.file_eligible(p_team_id,a,r.kind) then raise exception 'Validated own eligible file required' using errcode='42501';end if;
  if p_action='publish' and not ((r.kind='practice' and (team_private.has_capability(p_team_id,a,'practice.upload') or team_private.has_capability(p_team_id,a,'practice.publish'))) or (r.kind='practice_plan' and team_private.has_capability(p_team_id,a,'plans.manage'))) then raise exception 'Unrestricted practice upload required' using errcode='42501';end if;
 elsif p_action in ('approve','reject') then
  if not team_private.is_owner(p_team_id,a) or v.status<>'submitted' then raise exception 'Owner pending review required' using errcode='42501';end if;
 else raise exception 'Unknown private file action' using errcode='22023';end if;
 if p_reason is null or length(p_reason)>500 or v.byte_count is null or v.sha256 is null or length(btrim(v.title))=0 then raise exception 'Validated bytes and title required' using errcode='22023';end if;
 ns:=case when p_action='submit' then 'submitted' when p_action='reject' then 'rejected' else 'published' end;
 if ns='published' then
  if r.published_version_id is distinct from v.base_published_version_id then raise exception 'Published private file changed; open a successor' using errcode='PT409';end if;
  -- A grant removed while pending is not bypassed by later owner approval.
  if not team_private.file_eligible(p_team_id,v.author_user_id,r.kind) then raise exception 'Contributor authority changed' using errcode='42501';end if;
  if r.kind='practice' and not exists(select 1 from public.plays where id=r.play_id and team_id=p_team_id and published_version_id is not null) then raise exception 'Published play required' using errcode='42501';end if;
 end if;
 update public.file_resource_versions set status=ns,revision=revision+1,updated_at=now(),review_reason=case when p_action in ('approve','reject') then p_reason else '' end,review_actor_user_id=case when p_action in ('approve','reject') then a else null end where id=v.id returning * into v;
 if ns='published' then update public.file_resources set published_version_id=v.id where id=r.id;end if;
 perform team_private.audit(p_team_id,a,'file.'||p_action,v.id);return to_jsonb(v);
end$$;
create or replace function public.file_worker_finish(p_operation_id uuid,p_byte_count bigint,p_sha256 text,p_content_type text,p_validation_details jsonb,p_failure_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare v public.file_resource_versions;u team_private.file_uploads;r public.file_resources;begin
 select * into v from public.file_resource_versions where operation_id=p_operation_id;select * into u from team_private.file_uploads where operation_id=p_operation_id;
 if u.version_id is null then raise exception 'Upload unavailable' using errcode='42501';end if;
 perform team_private.file_worker_actor(v.team_id,u.actor_id,u.session_id,u.jwt_expires_at);
 select * into v from public.file_resource_versions where id=v.id for update;select * into u from team_private.file_uploads where operation_id=p_operation_id for update;select * into r from public.file_resources where id=v.resource_id;
 if not team_private.file_eligible(v.team_id,u.actor_id,r.kind) or r.archived_at is not null then raise exception 'Current contributor authority required' using errcode='42501';end if;
 if u.state='stored' then
  if p_failure_reason is not null or p_byte_count is distinct from v.byte_count or p_sha256 is distinct from v.sha256 then raise exception 'Stored receipt differs' using errcode='PT409';end if;return to_jsonb(v);
 end if;
 if v.status<>'uploading' or u.state not in ('uncertain','interrupted') then raise exception 'Uncertain upload required' using errcode='PT409';end if;
 if p_failure_reason is not null then
  if length(p_failure_reason)>120 then raise exception 'Bounded failure code required' using errcode='22023';end if;
  update public.file_resource_versions set status='failed',revision=revision+1,review_reason=p_failure_reason,updated_at=now() where id=v.id returning * into v;
  update team_private.file_uploads set state='failed' where operation_id=p_operation_id;
 else
  if p_byte_count is null or p_byte_count<>u.reserved_bytes or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' or p_content_type is distinct from (case when r.kind in ('scouting','practice_plan') then 'application/pdf' else 'video/mp4' end) or p_validation_details is null or jsonb_typeof(p_validation_details)<>'object' or length(p_validation_details::text)>4000 then raise exception 'Exact trusted immutable byte receipt required' using errcode='22023';end if;
  update public.file_resource_versions set status='ready',byte_count=p_byte_count,sha256=p_sha256,content_type=p_content_type,validation_details=p_validation_details,revision=revision+1,updated_at=now() where id=v.id returning * into v;
  update team_private.file_uploads set state='stored' where operation_id=p_operation_id;
 end if;
 perform team_private.audit(v.team_id,u.actor_id,case when p_failure_reason is null then 'file.bytes_validated' else 'file.validation_failed' end,v.id);return to_jsonb(v);
end$$;
create function public.web_plan_share(p_team_id uuid,p_practice_id uuid,p_operation_id uuid,p_expected_revision bigint,p_pdf_version_id uuid default null) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id);s public.web_sessions;v public.web_practice_plan_versions;source public.web_session_snapshots;pdf public.file_resource_versions;doc jsonb;next_revision bigint;
begin
 if not team_private.has_capability(p_team_id,a,'plans.manage') then raise exception 'Plan management access required' using errcode='42501';end if;
 select * into s from public.web_sessions where team_id=p_team_id and id=p_practice_id and kind='practice' for update;
 if not found then raise exception 'Practice unavailable' using errcode='42501';end if;
 select * into v from public.web_practice_plan_versions where operation_id=p_operation_id;
 if found then
  if v.team_id<>p_team_id or v.practice_id<>p_practice_id or v.shared_by<>a or v.pdf_version_id is distinct from p_pdf_version_id or (v.kind='builder' and not exists(select 1 from public.web_session_snapshots x where x.id=v.source_snapshot_id and x.revision=p_expected_revision)) then raise exception 'Plan operation already bound to another version' using errcode='PT409';end if;
  return jsonb_build_object('id',v.id,'revision',v.revision,'kind',v.kind);
 end if;
 if p_operation_id is null or p_expected_revision is distinct from s.revision then raise exception 'Plan source changed; reload saved entries' using errcode='PT409';end if;
 select coalesce(max(revision),0)+1 into next_revision from public.web_practice_plan_versions where practice_id=s.id;
 if p_pdf_version_id is null then
  select * into source from public.web_session_snapshots where id=s.current_snapshot_id and team_id=p_team_id and session_id=s.id;
  doc:=source.document->'session';
  if jsonb_array_length(doc->'plan')=0 then raise exception 'Add and save a drill before sharing the builder plan' using errcode='22023';end if;
  -- Explicit allowlist prevents an early shared plan from exposing draft player statistics.
  insert into public.web_practice_plan_versions(team_id,practice_id,revision,kind,builder,source_snapshot_id,author_user_id,shared_by,operation_id)
   values(p_team_id,s.id,next_revision,'builder',jsonb_build_object('title',doc->'title','date',doc->'date','plan',doc->'plan','protocol',doc->'protocol','spots',doc->'spots'),source.id,source.author_user_id,a,p_operation_id) returning * into v;
 else
  select x.* into pdf from public.file_resource_versions x join public.file_resources r on r.id=x.resource_id where x.id=p_pdf_version_id and x.team_id=p_team_id and r.kind='practice_plan' and r.practice_id=s.id;
  if not found or pdf.content_type<>'application/pdf' or pdf.byte_count is null or pdf.sha256 is null then raise exception 'Validated practice PDF required' using errcode='42501';end if;
  if pdf.status='ready' then perform public.file_transition(p_team_id,pdf.id,pdf.revision,'publish');
  elsif pdf.status<>'published' or not exists(select 1 from public.file_resources where id=pdf.resource_id and published_version_id=pdf.id and archived_at is null) then raise exception 'Current published PDF required' using errcode='PT409';end if;
  insert into public.web_practice_plan_versions(team_id,practice_id,revision,kind,pdf_version_id,author_user_id,shared_by,operation_id) values(p_team_id,s.id,next_revision,'pdf',pdf.id,pdf.author_user_id,a,p_operation_id) returning * into v;
 end if;
 update public.web_sessions set shared_plan_id=v.id where id=s.id;
 perform team_private.audit(p_team_id,a,'practice_plan.shared',v.id);
 return jsonb_build_object('id',v.id,'revision',v.revision,'kind',v.kind);
end $$;
create function public.web_plan_list(p_team_id uuid,p_practice_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id);result jsonb;
begin
 if not exists(select 1 from public.web_sessions where team_id=p_team_id and id=p_practice_id and kind='practice') then raise exception 'Practice unavailable' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'revision',v.revision,'kind',v.kind,'builder',v.builder,'pdf_version_id',v.pdf_version_id,'shared_at',v.shared_at,'is_current',s.shared_plan_id=v.id,'operation_id',case when team_private.has_capability(p_team_id,a,'plans.manage') then v.operation_id else null end) order by v.revision desc),'[]') into result from public.web_practice_plan_versions v join public.web_sessions s on s.id=v.practice_id and s.team_id=v.team_id where v.team_id=p_team_id and v.practice_id=p_practice_id;
 if octet_length(result::text)>4194304 then raise exception 'Plan history exceeds display limit' using errcode='22023';end if;
 return result;
end $$;
revoke all on function public.web_plan_share(uuid,uuid,uuid,bigint,uuid),public.web_plan_list(uuid,uuid) from public,anon;
grant execute on function public.web_plan_share(uuid,uuid,uuid,bigint,uuid),public.web_plan_list(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
