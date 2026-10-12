-- Private immutable PDF/clip bytes. Hosted budgets intentionally start unknown.
begin;
create or replace function team_private.capabilities() returns text[] language sql immutable
set search_path=pg_catalog as $$select array['stats.review','stats.publish','datasets.reopen','roster.manage','members.manage','plays.author','plays.review','plays.publish','practice.upload','practice.review','practice.publish','film.upload','film.review','film.publish','scouting.upload','scouting.read']::text[]$$;
create table public.file_resources(
 id uuid primary key, team_id uuid not null references public.teams(id), kind text not null check(kind in ('practice','scouting')),
 play_id uuid, game_id uuid, published_version_id uuid, archived_at timestamptz, created_at timestamptz not null default now(),
 unique(team_id,id), check((kind='practice' and play_id is not null and game_id is null) or (kind='scouting' and game_id is not null and play_id is null)),
 foreign key(team_id,play_id) references public.plays(team_id,id),foreign key(team_id,game_id) references public.games(team_id,id)
);
create table public.file_resource_versions(
 id uuid primary key default gen_random_uuid(),team_id uuid not null,resource_id uuid not null,author_user_id uuid not null references auth.users(id),
 operation_id uuid not null unique, revision bigint not null default 1 check(revision>0),status text not null default 'uploading' check(status in ('uploading','ready','submitted','rejected','published','failed')),
 title text not null default '' check(length(title)<=120),notes text not null default '' check(length(notes)<=1000),declared_bytes bigint not null check(declared_bytes>0),
 byte_count bigint,sha256 text check(sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),content_type text,validation_details jsonb,
 base_published_version_id uuid,review_reason text not null default '' check(length(review_reason)<=500),review_actor_user_id uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(team_id,resource_id) references public.file_resources(team_id,id),unique(resource_id,id)
);
alter table public.file_resources add constraint file_current_version foreign key(id,published_version_id) references public.file_resource_versions(resource_id,id);
alter table public.file_resource_versions add constraint file_base_version foreign key(resource_id,base_published_version_id) references public.file_resource_versions(resource_id,id);
create index file_versions_target on public.file_resource_versions(team_id,resource_id,created_at,id);
-- These tables are not exposed through the Data API and have no client grants.
create table team_private.file_budget(
 id boolean primary key default true check(id),known_until timestamptz check(known_until is null or isfinite(known_until)),storage_limit bigint check(storage_limit>=0),transfer_limit bigint check(transfer_limit>=0),transfer_charged bigint not null default 0 check(transfer_charged>=0)
);
insert into team_private.file_budget(id) values(true);
create table team_private.file_uploads(
 operation_id uuid primary key references public.file_resource_versions(operation_id),version_id uuid not null unique references public.file_resource_versions(id),
 actor_id uuid not null references auth.users(id),session_id uuid not null,jwt_expires_at timestamptz not null,
 reserved_bytes bigint not null check(reserved_bytes>0),expires_at timestamptz not null default now()+interval '30 minutes',
 state text not null default 'reserved' check(state in ('reserved','uncertain','stored','failed','interrupted')),
 object_path text not null unique,created_at timestamptz not null default now()
);
create unique index file_one_active_upload on team_private.file_uploads(actor_id) where state in ('reserved','uncertain');
create table team_private.file_deliveries(
 operation_id uuid primary key,version_id uuid not null references public.file_resource_versions(id),actor_id uuid not null references auth.users(id),
 session_id uuid not null,jwt_expires_at timestamptz not null,byte_count bigint not null,state text not null default 'reserved' check(state in ('reserved','started')),
 created_at timestamptz not null default now()
);
revoke all on team_private.file_budget,team_private.file_uploads,team_private.file_deliveries from public,anon,authenticated;
create function team_private.file_eligible(t uuid,a uuid,k text) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.is_active(t,a) and (k='practice' or (k='scouting' and team_private.has_capability(t,a,'scouting.upload')))
$$;
create function team_private.file_can_fetch(t uuid,v uuid,a uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.is_active(t,a) and exists(select 1 from public.file_resource_versions x join public.file_resources r on r.id=x.resource_id
 where x.id=v and x.team_id=t and x.byte_count is not null and (team_private.is_owner(t,a) or
 (r.archived_at is null and ((x.author_user_id=a and team_private.file_eligible(t,a,r.kind) and (x.status in ('ready','submitted') or (r.kind='practice' and x.status='rejected'))) or
 (r.published_version_id=x.id and x.status='published' and (r.kind='practice' or team_private.has_capability(t,a,'scouting.read')))))))
$$;
create function team_private.file_visible(t uuid,v uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select team_private.can_read(t) and exists(select 1 from public.file_resource_versions x join public.file_resources r on r.id=x.resource_id where x.id=v and x.team_id=t
 and (team_private.is_owner(t,team_private.actor()) or (r.archived_at is null and
 ((x.author_user_id=team_private.actor() and team_private.file_eligible(t,team_private.actor(),r.kind) and ((r.kind='practice' and x.status<>'published') or (r.kind='scouting' and x.status in ('uploading','ready','submitted','failed')))) or (r.published_version_id=x.id and x.status='published' and (r.kind='practice' or team_private.has_capability(t,team_private.actor(),'scouting.read')))))))
$$;
create function team_private.file_parent_visible(t uuid,r uuid) returns boolean language sql stable security definer set search_path=pg_catalog as $$select exists(select 1 from public.file_resource_versions x where x.team_id=t and x.resource_id=r and team_private.file_visible(t,x.id))$$;
alter table public.file_resources enable row level security;
alter table public.file_resource_versions enable row level security;
create policy file_resources_read on public.file_resources for select to authenticated using(team_private.file_parent_visible(team_id,id));
create policy file_versions_read on public.file_resource_versions for select to authenticated using(team_private.file_visible(team_id,id));
revoke all on public.file_resources,public.file_resource_versions from public,anon,authenticated;
grant select on public.file_resources,public.file_resource_versions to authenticated;
create function team_private.file_guard() returns trigger language plpgsql set search_path=pg_catalog as $$begin
 if tg_op='DELETE' or old.status in ('published','rejected','failed') or new.id<>old.id or new.team_id<>old.team_id or new.resource_id<>old.resource_id or new.author_user_id<>old.author_user_id or new.operation_id<>old.operation_id or new.declared_bytes<>old.declared_bytes or new.base_published_version_id is distinct from old.base_published_version_id
 or (old.byte_count is not null and (new.byte_count is distinct from old.byte_count or new.sha256 is distinct from old.sha256 or new.content_type is distinct from old.content_type or new.validation_details is distinct from old.validation_details))
 or (old.status='submitted' and (new.title<>old.title or new.notes<>old.notes)) then raise exception 'Private file history is immutable' using errcode='42501';end if;return new;end$$;
create trigger file_history_guard before update or delete on public.file_resource_versions for each row execute function team_private.file_guard();
create function team_private.file_resource_guard() returns trigger language plpgsql set search_path=pg_catalog as $$begin
 if tg_op='DELETE' or new.id<>old.id or new.team_id<>old.team_id or new.kind<>old.kind or new.play_id is distinct from old.play_id or new.game_id is distinct from old.game_id then raise exception 'Private file linkage is immutable' using errcode='42501';end if;return new;end$$;
create trigger file_resource_guard before update or delete on public.file_resources for each row execute function team_private.file_resource_guard();
create function team_private.file_budget_lock(p_bytes bigint,p_transfer boolean) returns void language plpgsql security definer set search_path=pg_catalog as $$declare b team_private.file_budget;used numeric;begin
 select * into b from team_private.file_budget where id for update;
 if b.known_until is null or b.known_until<=clock_timestamp() or b.storage_limit is null or b.transfer_limit is null then raise exception 'Private file capacity is not verified; preserve input and retry after trusted setup' using errcode='P0001';end if;
 if p_bytes is null or p_bytes<1 then raise exception 'Positive byte count required' using errcode='22023';end if;
 if p_transfer then
  if b.transfer_charged::numeric+p_bytes>b.transfer_limit then raise exception 'Private file transfer allowance exhausted' using errcode='P0001';end if;
  update team_private.file_budget set transfer_charged=transfer_charged+p_bytes where id;
 else
  select coalesce(sum(reserved_bytes::numeric),0) into used from team_private.file_uploads;
  if used+p_bytes>b.storage_limit then raise exception 'Private file storage allowance exhausted' using errcode='P0001';end if;
 end if;
end$$;
create function public.file_reserve(p_team_id uuid,p_resource_id uuid,p_kind text,p_target_id uuid,p_operation_id uuid,p_declared_bytes bigint,p_title text,p_notes text default '',p_base_published_version_id uuid default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare a uuid; r public.file_resources;v public.file_resource_versions;begin
 -- Across teams, the same account cannot race the one-active-upload limit.
 a:=team_private.actor();if a is null then raise exception 'Verified session required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(a::text,370));a:=team_private.member_actor(p_team_id);
 if not team_private.file_eligible(p_team_id,a,p_kind) then raise exception 'Private file contribution denied' using errcode='42501';end if;
 if p_resource_id is null or p_target_id is null or p_operation_id is null or p_kind is null or p_kind not in ('practice','scouting') or p_declared_bytes is null or p_declared_bytes<1 or p_declared_bytes>(case when p_kind='scouting' then 5242880 else 10485760 end) or p_title is null or length(p_title)>120 or p_notes is null or length(p_notes)>1000 or p_title~'[[:cntrl:]]' or p_notes~'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' then raise exception 'Valid bounded private file fields required' using errcode='22023';end if;
 select * into v from public.file_resource_versions where operation_id=p_operation_id;
 if found then
  select * into r from public.file_resources where id=v.resource_id;
  if v.author_user_id<>a or v.team_id<>p_team_id or r.id<>p_resource_id or r.kind<>p_kind or coalesce(r.play_id,r.game_id)<>p_target_id or v.declared_bytes<>p_declared_bytes or v.base_published_version_id is distinct from p_base_published_version_id then raise exception 'Upload operation already has different content or identity' using errcode='40001';end if;return to_jsonb(v);
 end if;
 if (p_kind='practice' and not exists(select 1 from public.plays where id=p_target_id and team_id=p_team_id and published_version_id is not null)) or (p_kind='scouting' and not exists(select 1 from public.games where id=p_target_id and team_id=p_team_id)) then raise exception 'Existing published play or shared game required' using errcode='22023';end if;
 select * into r from public.file_resources where id=p_resource_id for update;
 if found then
  if r.team_id<>p_team_id or r.kind<>p_kind or coalesce(r.play_id,r.game_id)<>p_target_id or r.archived_at is not null then raise exception 'Private resource linkage unavailable' using errcode='42501';end if;
  if r.published_version_id is distinct from p_base_published_version_id then raise exception 'Published private file changed; reload' using errcode='40001';end if;
 else
  if p_base_published_version_id is not null then raise exception 'New resource cannot have a source' using errcode='22023';end if;
  insert into public.file_resources(id,team_id,kind,play_id,game_id) values(p_resource_id,p_team_id,p_kind,case when p_kind='practice' then p_target_id end,case when p_kind='scouting' then p_target_id end) returning * into r;
 end if;
 -- Expiry permits another attempt, but never releases the old reservation/occupied bytes.
 update team_private.file_uploads set state='interrupted' where actor_id=a and state in ('reserved','uncertain') and expires_at<=clock_timestamp();
 if exists(select 1 from team_private.file_uploads where actor_id=a and state in ('reserved','uncertain')) then raise exception 'Another upload is active; reconcile it before starting another' using errcode='40001';end if;
 perform team_private.file_budget_lock(p_declared_bytes,false);
 insert into public.file_resource_versions(team_id,resource_id,author_user_id,operation_id,title,notes,declared_bytes,base_published_version_id) values(p_team_id,r.id,a,p_operation_id,p_title,p_notes,p_declared_bytes,r.published_version_id) returning * into v;
 insert into team_private.file_uploads(operation_id,version_id,actor_id,session_id,jwt_expires_at,reserved_bytes,object_path) values(p_operation_id,v.id,a,(auth.jwt()->>'session_id')::uuid,to_timestamp((auth.jwt()->>'exp')::double precision),p_declared_bytes,p_team_id::text||'/'||r.id::text||'/'||v.id::text);
 perform team_private.audit(p_team_id,a,'file.reserved',v.id);return to_jsonb(v);
end$$;
create function public.file_save(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_title text,p_notes text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare a uuid:=team_private.member_actor(p_team_id);v public.file_resource_versions;r public.file_resources;begin
 select * into v from public.file_resource_versions where id=p_version_id and team_id=p_team_id for update;select * into r from public.file_resources where id=v.resource_id;
 if v.id is null or v.author_user_id<>a or v.status not in ('uploading','ready') or r.archived_at is not null or not team_private.file_eligible(p_team_id,a,r.kind) then raise exception 'Editable own private proposal required' using errcode='42501';end if;
 if p_expected_revision is distinct from v.revision then raise exception 'Private file revision changed; reload' using errcode='40001';end if;
 if p_title is null or length(p_title)>120 or p_title~'[[:cntrl:]]' or p_notes is null or length(p_notes)>1000 or p_notes~'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' then raise exception 'Valid title and notes required' using errcode='22023';end if;
 update public.file_resource_versions set title=p_title,notes=p_notes,revision=revision+1,updated_at=now() where id=v.id returning * into v;perform team_private.audit(p_team_id,a,'file.saved',v.id);return to_jsonb(v);
end$$;
create function public.file_transition(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_action text,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare a uuid:=team_private.member_actor(p_team_id);v public.file_resource_versions;r public.file_resources;ns text;begin
 select * into v from public.file_resource_versions where id=p_version_id and team_id=p_team_id for update;select * into r from public.file_resources where id=v.resource_id for update;
 if v.id is null or r.archived_at is not null then raise exception 'Private file unavailable' using errcode='42501';end if;
 if p_expected_revision is distinct from v.revision then raise exception 'Private file revision changed; reload' using errcode='40001';end if;
 if p_action in ('submit','publish') then
  if v.author_user_id<>a or v.status<>'ready' or not team_private.file_eligible(p_team_id,a,r.kind) then raise exception 'Validated own eligible file required' using errcode='42501';end if;
  if p_action='publish' and (r.kind<>'practice' or not (team_private.has_capability(p_team_id,a,'practice.upload') or team_private.has_capability(p_team_id,a,'practice.publish'))) then raise exception 'Unrestricted practice upload required' using errcode='42501';end if;
 elsif p_action in ('approve','reject') then
  if not team_private.is_owner(p_team_id,a) or v.status<>'submitted' then raise exception 'Owner pending review required' using errcode='42501';end if;
 else raise exception 'Unknown private file action' using errcode='22023';end if;
 if p_reason is null or length(p_reason)>500 or v.byte_count is null or v.sha256 is null or length(btrim(v.title))=0 then raise exception 'Validated bytes and title required' using errcode='22023';end if;
 ns:=case when p_action='submit' then 'submitted' when p_action='reject' then 'rejected' else 'published' end;
 if ns='published' then
  if r.published_version_id is distinct from v.base_published_version_id then raise exception 'Published private file changed; open a successor' using errcode='40001';end if;
  -- A grant removed while pending is not bypassed by later owner approval.
  if not team_private.file_eligible(p_team_id,v.author_user_id,r.kind) then raise exception 'Contributor authority changed' using errcode='42501';end if;
  if r.kind='practice' and not exists(select 1 from public.plays where id=r.play_id and team_id=p_team_id and published_version_id is not null) then raise exception 'Published play required' using errcode='42501';end if;
 end if;
 update public.file_resource_versions set status=ns,revision=revision+1,updated_at=now(),review_reason=case when p_action in ('approve','reject') then p_reason else '' end,review_actor_user_id=case when p_action in ('approve','reject') then a else null end where id=v.id returning * into v;
 if ns='published' then update public.file_resources set published_version_id=v.id where id=r.id;end if;
 perform team_private.audit(p_team_id,a,'file.'||p_action,v.id);return to_jsonb(v);
end$$;
create function public.file_archive(p_team_id uuid,p_resource_id uuid,p_expected_published_version_id uuid) returns void language plpgsql security definer set search_path=pg_catalog as $$declare a uuid:=team_private.member_actor(p_team_id);r public.file_resources;begin
 if not team_private.is_owner(p_team_id,a) then raise exception 'Owner archive required' using errcode='42501';end if;
 select * into r from public.file_resources where id=p_resource_id and team_id=p_team_id for update;
 if r.id is null then raise exception 'Private file unavailable' using errcode='42501';end if;
 if r.published_version_id is distinct from p_expected_published_version_id then raise exception 'Published private file changed; reload' using errcode='40001';end if;
 update public.file_resources set archived_at=coalesce(archived_at,now()) where id=r.id;perform team_private.audit(p_team_id,a,'file.archived',r.id);
end$$;
-- User authorization is refreshed immediately before the trusted worker claims an upload.
create function public.file_upload_access(p_operation_id uuid,p_reconcile boolean default false) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare v public.file_resource_versions;r public.file_resources;a uuid;u team_private.file_uploads;begin
 select * into v from public.file_resource_versions where operation_id=p_operation_id; if v.id is null then raise exception 'Upload unavailable' using errcode='42501';end if;
 a:=team_private.member_actor(v.team_id);select * into r from public.file_resources where id=v.resource_id;select * into u from team_private.file_uploads where operation_id=p_operation_id for update;
 if a<>v.author_user_id or not team_private.file_eligible(v.team_id,a,r.kind) or r.archived_at is not null or v.status not in ('uploading','ready') then raise exception 'Upload denied' using errcode='42501';end if;
 if not p_reconcile and (u.state<>'reserved' or u.expires_at<=clock_timestamp()) then raise exception 'Upload outcome uncertain or expired; reconcile before retry' using errcode='40001';end if;
 update team_private.file_uploads set session_id=(auth.jwt()->>'session_id')::uuid,jwt_expires_at=to_timestamp((auth.jwt()->>'exp')::double precision) where operation_id=p_operation_id;return to_jsonb(v);
end$$;
create function public.file_delivery(p_team_id uuid,p_version_id uuid,p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare a uuid:=team_private.member_actor(p_team_id);v public.file_resource_versions;d team_private.file_deliveries;begin
 if p_operation_id is null or not team_private.file_can_fetch(p_team_id,p_version_id,a) then raise exception 'Private file retrieval denied' using errcode='42501';end if;
 select * into v from public.file_resource_versions where id=p_version_id;
 select * into d from team_private.file_deliveries where operation_id=p_operation_id for update;
 if found then
  if d.actor_id<>a or d.version_id<>v.id then raise exception 'Delivery identity changed' using errcode='40001';end if;
  if d.state<>'reserved' then raise exception 'Delivery already attempted; a new operation consumes a new allowance' using errcode='40001';end if;
  update team_private.file_deliveries set session_id=(auth.jwt()->>'session_id')::uuid,jwt_expires_at=to_timestamp((auth.jwt()->>'exp')::double precision) where operation_id=p_operation_id;
 else
  perform team_private.file_budget_lock(v.byte_count,true);
  insert into team_private.file_deliveries(operation_id,version_id,actor_id,session_id,jwt_expires_at,byte_count) values(p_operation_id,v.id,a,(auth.jwt()->>'session_id')::uuid,to_timestamp((auth.jwt()->>'exp')::double precision),v.byte_count);
 end if;
 return jsonb_build_object('operation_id',p_operation_id,'version_id',v.id,'byte_count',v.byte_count,'sha256',v.sha256,'content_type',v.content_type);
end$$;
-- Service-only helper cannot derive authority from service claims or client metadata.
create function team_private.file_worker_actor(t uuid,a uuid,s uuid,e timestamptz) returns void language plpgsql security definer set search_path=pg_catalog as $$begin
 perform 1 from public.teams where id=t for update;
 perform 1 from auth.sessions x join auth.users u on u.id=x.user_id where x.id=s and x.user_id=a and (x.not_after is null or x.not_after>clock_timestamp()) and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null) and u.is_anonymous is not true for share of x;
 if not found or e<=clock_timestamp() or not team_private.is_active(t,a) then raise exception 'Current verified authority required' using errcode='42501';end if;
end$$;
create function public.file_worker_claim_upload(p_operation_id uuid,p_reconcile boolean) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare v public.file_resource_versions;u team_private.file_uploads;r public.file_resources;begin
 select * into v from public.file_resource_versions where operation_id=p_operation_id;
 select * into u from team_private.file_uploads where operation_id=p_operation_id;
 if u.version_id is null then raise exception 'Upload unavailable' using errcode='42501';end if;
 perform team_private.file_worker_actor(v.team_id,u.actor_id,u.session_id,u.jwt_expires_at);
 select * into u from team_private.file_uploads where operation_id=p_operation_id for update;select * into r from public.file_resources where id=v.resource_id;
 if not team_private.file_eligible(v.team_id,u.actor_id,r.kind) or r.archived_at is not null then raise exception 'Current contributor authority required' using errcode='42501';end if;
 if not p_reconcile and (u.state<>'reserved' or u.expires_at<=clock_timestamp()) then raise exception 'Reconcile uncertain upload' using errcode='40001';end if;
 if p_reconcile then
  -- Reading quarantined bytes also consumes transfer; retained reservations are unchanged.
  perform team_private.file_budget_lock(u.reserved_bytes,true);
 else
  perform team_private.file_budget_lock(u.reserved_bytes,true); -- actual Storage durability readback is transfer too
 end if;
 update team_private.file_uploads set state=case when state='stored' then state else 'uncertain' end where operation_id=p_operation_id;
 return jsonb_build_object('version_id',v.id,'team_id',v.team_id,'kind',r.kind,'object_path',u.object_path,'declared_bytes',u.reserved_bytes,'status',v.status,'byte_count',v.byte_count,'sha256',v.sha256);
end$$;
create function public.file_worker_finish(p_operation_id uuid,p_byte_count bigint,p_sha256 text,p_content_type text,p_validation_details jsonb,p_failure_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare v public.file_resource_versions;u team_private.file_uploads;r public.file_resources;begin
 select * into v from public.file_resource_versions where operation_id=p_operation_id;select * into u from team_private.file_uploads where operation_id=p_operation_id;
 if u.version_id is null then raise exception 'Upload unavailable' using errcode='42501';end if;
 perform team_private.file_worker_actor(v.team_id,u.actor_id,u.session_id,u.jwt_expires_at);
 select * into v from public.file_resource_versions where id=v.id for update;select * into u from team_private.file_uploads where operation_id=p_operation_id for update;select * into r from public.file_resources where id=v.resource_id;
 if not team_private.file_eligible(v.team_id,u.actor_id,r.kind) or r.archived_at is not null then raise exception 'Current contributor authority required' using errcode='42501';end if;
 if u.state='stored' then
  if p_failure_reason is not null or p_byte_count is distinct from v.byte_count or p_sha256 is distinct from v.sha256 then raise exception 'Stored receipt differs' using errcode='40001';end if;return to_jsonb(v);
 end if;
 if v.status<>'uploading' or u.state not in ('uncertain','interrupted') then raise exception 'Uncertain upload required' using errcode='40001';end if;
 if p_failure_reason is not null then
  if length(p_failure_reason)>120 then raise exception 'Bounded failure code required' using errcode='22023';end if;
  update public.file_resource_versions set status='failed',revision=revision+1,review_reason=p_failure_reason,updated_at=now() where id=v.id returning * into v;
  update team_private.file_uploads set state='failed' where operation_id=p_operation_id;
 else
  if p_byte_count is null or p_byte_count<>u.reserved_bytes or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' or p_content_type is distinct from (case when r.kind='scouting' then 'application/pdf' else 'video/mp4' end) or p_validation_details is null or jsonb_typeof(p_validation_details)<>'object' or length(p_validation_details::text)>4000 then raise exception 'Exact trusted immutable byte receipt required' using errcode='22023';end if;
  update public.file_resource_versions set status='ready',byte_count=p_byte_count,sha256=p_sha256,content_type=p_content_type,validation_details=p_validation_details,revision=revision+1,updated_at=now() where id=v.id returning * into v;
  update team_private.file_uploads set state='stored' where operation_id=p_operation_id;
 end if;
 perform team_private.audit(v.team_id,u.actor_id,case when p_failure_reason is null then 'file.bytes_validated' else 'file.validation_failed' end,v.id);return to_jsonb(v);
end$$;
create function public.file_worker_missing(p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare v public.file_resource_versions;u team_private.file_uploads;r public.file_resources;begin
 select * into v from public.file_resource_versions where operation_id=p_operation_id;select * into u from team_private.file_uploads where operation_id=p_operation_id;
 if u.version_id is null then raise exception 'Upload unavailable' using errcode='42501';end if;
 perform team_private.file_worker_actor(v.team_id,u.actor_id,u.session_id,u.jwt_expires_at);
 select * into u from team_private.file_uploads where operation_id=p_operation_id for update;
 select * into r from public.file_resources where id=v.resource_id;
 if not team_private.file_eligible(v.team_id,u.actor_id,r.kind) or r.archived_at is not null then raise exception 'Current contributor authority required' using errcode='42501';end if;
 if u.state not in ('uncertain','interrupted') or v.status<>'uploading' then raise exception 'Uncertain upload required' using errcode='40001';end if;
 update team_private.file_uploads set state='interrupted' where operation_id=p_operation_id;
 perform team_private.audit(v.team_id,u.actor_id,'file.missing_reconciled',v.id);
 return to_jsonb(v); -- reservation retained, old identity never overwritten/reused
end$$;
create function public.file_worker_claim_delivery(p_operation_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog as $$declare d team_private.file_deliveries;v public.file_resource_versions;u team_private.file_uploads;begin
 select * into d from team_private.file_deliveries where operation_id=p_operation_id;
 if d.version_id is null then raise exception 'Delivery unavailable' using errcode='42501';end if;
 select * into v from public.file_resource_versions where id=d.version_id;
 perform team_private.file_worker_actor(v.team_id,d.actor_id,d.session_id,d.jwt_expires_at);
 select * into d from team_private.file_deliveries where operation_id=p_operation_id for update;
 if d.state<>'reserved' or not team_private.file_can_fetch(v.team_id,v.id,d.actor_id) then raise exception 'Delivery denied or already attempted' using errcode='42501';end if;
 select * into u from team_private.file_uploads where version_id=v.id;
 if u.state<>'stored' then raise exception 'Durable private file unavailable' using errcode='42501';end if;
 perform 1 from team_private.file_budget where id and known_until>clock_timestamp() and storage_limit is not null and transfer_limit is not null for update;
 if not found then raise exception 'Private file capacity no longer verified' using errcode='P0001';end if;
 update team_private.file_deliveries set state='started' where operation_id=p_operation_id;
 return jsonb_build_object('version_id',v.id,'object_path',u.object_path,'byte_count',v.byte_count,'sha256',v.sha256,'content_type',v.content_type);
end$$;
-- Storage is private; restrictive policies prevent an unrelated permissive policy bypass.
do $$begin
 if to_regclass('storage.buckets') is not null then
  insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('teamstats-private','teamstats-private',false,10485760,array['application/pdf','video/mp4']) on conflict(id) do nothing;
  if exists(select 1 from storage.buckets where id='teamstats-private' and public) then raise exception 'Existing TeamStats bucket is public; trusted review required';end if;
  execute 'create policy teamstats_private_bytes_denied on storage.objects as restrictive for all to anon,authenticated using (bucket_id<>''teamstats-private'') with check(bucket_id<>''teamstats-private'')';
 end if;
end$$;
revoke execute on function team_private.file_eligible(uuid,uuid,text),team_private.file_can_fetch(uuid,uuid,uuid),team_private.file_visible(uuid,uuid),team_private.file_parent_visible(uuid,uuid),team_private.file_guard(),team_private.file_resource_guard(),team_private.file_budget_lock(bigint,boolean),team_private.file_worker_actor(uuid,uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function team_private.file_visible(uuid,uuid),team_private.file_parent_visible(uuid,uuid) to authenticated;
revoke execute on function public.file_reserve(uuid,uuid,text,uuid,uuid,bigint,text,text,uuid),public.file_save(uuid,uuid,bigint,text,text),public.file_transition(uuid,uuid,bigint,text,text),public.file_archive(uuid,uuid,uuid),public.file_upload_access(uuid,boolean),public.file_delivery(uuid,uuid,uuid) from public,anon;
grant execute on function public.file_reserve(uuid,uuid,text,uuid,uuid,bigint,text,text,uuid),public.file_save(uuid,uuid,bigint,text,text),public.file_transition(uuid,uuid,bigint,text,text),public.file_archive(uuid,uuid,uuid),public.file_upload_access(uuid,boolean),public.file_delivery(uuid,uuid,uuid) to authenticated;
revoke execute on function public.file_worker_claim_upload(uuid,boolean),public.file_worker_finish(uuid,bigint,text,text,jsonb,text),public.file_worker_claim_delivery(uuid),public.file_worker_missing(uuid) from public,anon,authenticated;
grant execute on function public.file_worker_claim_upload(uuid,boolean),public.file_worker_finish(uuid,bigint,text,text,jsonb,text),public.file_worker_claim_delivery(uuid),public.file_worker_missing(uuid) to service_role;
notify pgrst,'reload schema';
commit;
