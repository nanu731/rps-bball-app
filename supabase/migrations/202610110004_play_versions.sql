-- Authored play geometry is independent of roster identities and game statistics.
begin;
create table public.plays (
 id uuid primary key, team_id uuid not null references public.teams(id),
 published_version_id uuid, created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), unique(team_id,id)
);
create table public.play_versions (
 id uuid primary key default gen_random_uuid(), team_id uuid not null,
 play_id uuid not null, author_user_id uuid not null references auth.users(id),
 revision bigint not null default 1 check(revision>0),
 status text not null default 'draft' check(status in ('draft','submitted','rejected','published')),
 title text not null default '' check(length(title)<=100),
 diagram jsonb not null default '{"markers":[],"steps":[]}',
 base_published_version_id uuid references public.play_versions(id),
 review_actor_user_id uuid references auth.users(id), review_reason text not null default '' check(length(review_reason)<=500),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(team_id,play_id) references public.plays(team_id,id), unique(play_id,id)
);
alter table public.plays add constraint play_published_pointer foreign key(id,published_version_id)
 references public.play_versions(play_id,id);
create unique index one_play_author_draft on public.play_versions(play_id,author_user_id) where status='draft';
create index play_versions_team on public.play_versions(team_id,play_id);
create function team_private.play_version_visible(p_team uuid,p_author uuid,p_status text) returns boolean
language sql stable security definer set search_path=pg_catalog as $$
 select team_private.can_read(p_team) and (p_status='published' or p_author=team_private.actor()
 or (p_status in ('submitted','rejected') and team_private.has_capability(p_team,team_private.actor(),'plays.review')))
$$;
create function team_private.play_visible(p_team uuid,p_play uuid) returns boolean
language sql stable security definer set search_path=pg_catalog as $$
 select team_private.can_read(p_team) and exists(select 1 from public.play_versions v where v.play_id=p_play
 and team_private.play_version_visible(p_team,v.author_user_id,v.status))
$$;
create function team_private.play_immutable() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
 if tg_op='DELETE' or old.status in ('published','rejected') or new.id<>old.id or new.team_id<>old.team_id
 or new.play_id<>old.play_id or new.author_user_id<>old.author_user_id or new.created_at<>old.created_at
 or new.base_published_version_id is distinct from old.base_published_version_id or new.revision<>old.revision+1
 or (old.status<>'draft' and (new.title is distinct from old.title or new.diagram is distinct from old.diagram)) then
 raise exception 'Frozen play revisions cannot be changed' using errcode='42501'; end if;
 return new;
end $$;
create trigger play_version_immutable before update or delete on public.play_versions for each row execute function team_private.play_immutable();
create function team_private.valid_point(p jsonb) returns boolean language sql immutable set search_path=pg_catalog as $$
 select jsonb_typeof(p)='object' and p ?& array['x','y']
 and not exists(select 1 from jsonb_object_keys(p) k where k not in ('x','y'))
 and jsonb_typeof(p->'x')='number' and jsonb_typeof(p->'y')='number'
 and (p->>'x')::numeric between 0 and 1 and (p->>'y')::numeric between 0 and 1
$$;
create function team_private.validate_play(p_title text,p_diagram jsonb,p_publish boolean) returns void
language plpgsql set search_path=pg_catalog as $$
declare m jsonb; s jsonb; pos jsonb; ids uuid[]:='{}'; numbers bigint[]:='{}'; steps uuid[]:='{}'; positions uuid[]; ident uuid; number bigint;
begin
 if p_title is null or length(p_title)>100 or p_diagram is null or jsonb_typeof(p_diagram)<>'object'
 or not p_diagram ?& array['markers','steps'] or octet_length(p_diagram::text)>1048576
 or exists(select 1 from jsonb_object_keys(p_diagram) k where k not in ('markers','steps'))
 or jsonb_typeof(p_diagram->'markers')<>'array' or jsonb_typeof(p_diagram->'steps')<>'array' then
 raise exception 'Valid title and play diagram within 1 MiB required' using errcode='22023'; end if;
 for m in select value from jsonb_array_elements(p_diagram->'markers') loop
  if jsonb_typeof(m)<>'object' or not m ?& array['id','number','label','origin']
  or exists(select 1 from jsonb_object_keys(m) k where k not in ('id','number','label','origin'))
  or jsonb_typeof(m->'id')<>'string' or jsonb_typeof(m->'label')<>'string' or length(m->>'label')>80
  or not coalesce(team_private.valid_count(m->'number'),false) or m->>'number' is null
  or not coalesce(team_private.valid_point(m->'origin'),false) then
  raise exception 'Invalid numbered marker' using errcode='22023'; end if;
  ident:=(m->>'id')::uuid; number:=(m->>'number')::bigint;
  if ident is null or ident=any(ids) or number<1 or number=any(numbers) then raise exception 'Duplicate or invalid marker' using errcode='22023'; end if;
  ids:=array_append(ids,ident); numbers:=array_append(numbers,number);
 end loop;
 for s in select value from jsonb_array_elements(p_diagram->'steps') loop
  if jsonb_typeof(s)<>'object' or not s ?& array['id','duration','positions']
  or exists(select 1 from jsonb_object_keys(s) k where k not in ('id','duration','positions'))
  or jsonb_typeof(s->'id')<>'string' or jsonb_typeof(s->'duration')<>'number'
  or (s->>'duration')::numeric not between 0.1 and 30 or jsonb_typeof(s->'positions')<>'array' then
  raise exception 'Invalid movement step' using errcode='22023'; end if;
  ident:=(s->>'id')::uuid;
  if ident is null or ident=any(steps) then raise exception 'Duplicate step identity' using errcode='22023'; end if;
  steps:=array_append(steps,ident); positions:='{}';
  for pos in select value from jsonb_array_elements(s->'positions') loop
   if jsonb_typeof(pos)<>'object' or not pos ?& array['markerID','point']
   or exists(select 1 from jsonb_object_keys(pos) k where k not in ('markerID','point'))
   or jsonb_typeof(pos->'markerID')<>'string' or not coalesce(team_private.valid_point(pos->'point'),false) then
   raise exception 'Invalid marker position' using errcode='22023'; end if;
   ident:=(pos->>'markerID')::uuid;
   if ident is null or not ident=any(ids) or ident=any(positions) then raise exception 'Unknown or duplicate marker position' using errcode='22023'; end if;
   positions:=array_append(positions,ident);
  end loop;
  if cardinality(positions)<>cardinality(ids) then raise exception 'Every step must position each marker' using errcode='22023'; end if;
 end loop;
 if p_publish and (length(btrim(p_title))=0 or cardinality(ids)=0 or cardinality(steps)=0) then
 raise exception 'Name, markers and movement steps required for review or publication' using errcode='22023'; end if;
end $$;
create function public.play_open_draft(p_team_id uuid,p_play_id uuid,p_source_version_id uuid default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid; play public.plays; version public.play_versions; source public.play_versions;
begin
 actor:=team_private.member_actor(p_team_id);
 if not team_private.has_capability(p_team_id,actor,'plays.author') then raise exception 'Play authoring permission required' using errcode='42501'; end if;
 select * into play from public.plays where id=p_play_id and team_id=p_team_id for update;
 if not found then
  if p_source_version_id is not null then raise exception 'Play not found' using errcode='42501'; end if;
  insert into public.plays(id,team_id,created_by) values(p_play_id,p_team_id,actor) returning * into play;
 end if;
 select * into version from public.play_versions where play_id=play.id and author_user_id=actor and status='draft';
 if found then return to_jsonb(version); end if;
 if p_source_version_id is not null then
  select * into source from public.play_versions where id=p_source_version_id and play_id=play.id
   and (status='published' or (status='rejected' and author_user_id=actor));
  if not found or (source.status='published' and source.id is distinct from play.published_version_id)
   or (source.status='rejected' and source.base_published_version_id is distinct from play.published_version_id) then
   raise exception 'Current visible revision required' using errcode='40001'; end if;
 elsif play.published_version_id is not null then
  raise exception 'Choose current published revision to create a successor' using errcode='22023';
 elsif exists(select 1 from public.play_versions where play_id=play.id and author_user_id<>actor) then
  raise exception 'Unpublished play access denied' using errcode='42501';
 end if;
 insert into public.play_versions(team_id,play_id,author_user_id,title,diagram,base_published_version_id)
 values(p_team_id,play.id,actor,coalesce(source.title,''),coalesce(source.diagram,'{"markers":[],"steps":[]}'),play.published_version_id)
 returning * into version;
 perform team_private.audit(p_team_id,actor,'play.draft.open',version.id);
 return to_jsonb(version);
end $$;
create function public.play_save_draft(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_title text,p_diagram jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid; version public.play_versions; pointer uuid;
begin
 actor:=team_private.member_actor(p_team_id);
 select * into version from public.play_versions where id=p_version_id and team_id=p_team_id for update;
 if not found or version.author_user_id<>actor or version.status<>'draft'
 or not team_private.has_capability(p_team_id,actor,'plays.author') then raise exception 'Editable author draft required' using errcode='42501'; end if;
 select published_version_id into pointer from public.plays where id=version.play_id for update;
 if version.revision is distinct from p_expected_revision or version.base_published_version_id is distinct from pointer then
 raise exception 'Play changed; reload current revision' using errcode='40001'; end if;
 perform team_private.validate_play(p_title,p_diagram,false);
 update public.play_versions set title=p_title,diagram=p_diagram,revision=revision+1,updated_at=now() where id=version.id returning * into version;
 perform team_private.audit(p_team_id,actor,'play.draft.save',version.id);
 return to_jsonb(version);
end $$;
create function public.play_transition(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_action text,p_reason text default '') returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid; version public.play_versions; pointer uuid; reviewer boolean;
begin
 actor:=team_private.member_actor(p_team_id);
 select * into version from public.play_versions where id=p_version_id and team_id=p_team_id for update;
 if not found then raise exception 'Play access denied' using errcode='42501'; end if;
 select published_version_id into pointer from public.plays where id=version.play_id for update;
 if version.revision is distinct from p_expected_revision or version.base_published_version_id is distinct from pointer then
 raise exception 'Play changed; reload current revision' using errcode='40001'; end if;
 if p_reason is null or length(p_reason)>500 then raise exception 'Review reason must be at most 500 characters' using errcode='22023'; end if;
 reviewer:=team_private.has_capability(p_team_id,actor,'plays.review') and (actor<>version.author_user_id or team_private.is_owner(p_team_id,actor));
 if p_action='submit' then
  if version.status<>'draft' or version.author_user_id<>actor or not team_private.has_capability(p_team_id,actor,'plays.author') then
  raise exception 'Author draft submission required' using errcode='42501'; end if;
 elsif p_action='publish' then
  if version.status not in ('draft','submitted') or version.author_user_id<>actor or not team_private.has_capability(p_team_id,actor,'plays.publish') then
  raise exception 'Own play publication permission required' using errcode='42501'; end if;
 elsif p_action in ('approve','reject') then
  if version.status<>'submitted' or not reviewer then raise exception 'Independent play reviewer required' using errcode='42501'; end if;
 else raise exception 'Unknown play action' using errcode='22023'; end if;
 perform team_private.validate_play(version.title,version.diagram,true);
 update public.play_versions set status=case when p_action='submit' then 'submitted' when p_action='reject' then 'rejected' else 'published' end,
 revision=revision+1,updated_at=now(),review_actor_user_id=case when p_action='submit' then null else actor end,
 review_reason=p_reason where id=version.id returning * into version;
 if version.status='published' then update public.plays set published_version_id=version.id where id=version.play_id; end if;
 perform team_private.audit(p_team_id,actor,'play.'||p_action,version.id);
 return to_jsonb(version);
end $$;
alter table public.plays enable row level security;
alter table public.play_versions enable row level security;
create policy play_member_visible on public.plays for select to authenticated using(team_private.play_visible(team_id,id));
create policy play_revision_visible on public.play_versions for select to authenticated using(team_private.play_version_visible(team_id,author_user_id,status));
revoke all on public.plays,public.play_versions from public,anon,authenticated;
grant select on public.plays,public.play_versions to authenticated;
revoke execute on function team_private.play_version_visible(uuid,uuid,text),team_private.play_visible(uuid,uuid),
 team_private.play_immutable(),team_private.valid_point(jsonb),team_private.validate_play(text,jsonb,boolean) from public,anon,authenticated;
grant execute on function team_private.play_version_visible(uuid,uuid,text),team_private.play_visible(uuid,uuid) to authenticated;
revoke execute on function public.play_open_draft(uuid,uuid,uuid),public.play_save_draft(uuid,uuid,bigint,text,jsonb),
 public.play_transition(uuid,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.play_open_draft(uuid,uuid,uuid),public.play_save_draft(uuid,uuid,bigint,text,jsonb),
 public.play_transition(uuid,uuid,bigint,text,text) to authenticated;
commit;
