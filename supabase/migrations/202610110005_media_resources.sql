-- Reviewed user-authored HTTPS links only. This does not implement uploads/playback.
begin;
create table public.media_resources (
  id uuid primary key,
  team_id uuid not null references public.teams(id) on delete restrict,
  kind text not null check (kind in ('practice','film')),
  play_id uuid,
  game_id uuid,
  published_version_id uuid,
  created_at timestamptz not null default now(),
  unique(team_id,id),
  check ((kind='practice' and play_id is not null and game_id is null)
    or (kind='film' and game_id is not null and play_id is null)),
  foreign key(team_id,play_id) references public.plays(team_id,id) on delete restrict,
  foreign key(team_id,game_id) references public.games(team_id,id) on delete restrict
);
create table public.media_resource_versions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  resource_id uuid not null,
  author_user_id uuid not null references auth.users(id) on delete restrict,
  revision bigint not null default 1 check (revision>0),
  status text not null default 'draft' check (status in ('draft','submitted','rejected','published')),
  title text not null default '' check (length(title)<=120),
  link_url text not null default '' check (length(link_url)<=2048),
  notes text not null default '' check (length(notes)<=1000),
  base_published_version_id uuid,
  review_actor_user_id uuid references auth.users(id) on delete restrict,
  review_reason text not null default '' check (length(review_reason)<=500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(team_id,resource_id) references public.media_resources(team_id,id) on delete restrict,
  unique(resource_id,id)
);
alter table public.media_resources add foreign key(id,published_version_id)
  references public.media_resource_versions(resource_id,id) on delete restrict;
alter table public.media_resource_versions add foreign key(resource_id,base_published_version_id)
  references public.media_resource_versions(resource_id,id) on delete restrict;
create unique index media_author_working on public.media_resource_versions(resource_id,author_user_id)
  where status in ('draft','submitted');
create index media_team_versions on public.media_resource_versions(team_id,created_at,id);
create function team_private.media_visible(p_team uuid,p_author uuid,p_status text,p_kind text)
returns boolean language sql stable security definer set search_path=pg_catalog as $$
  select team_private.can_read(p_team) and (p_status='published' or p_author=team_private.actor()
    or (p_status in ('submitted','rejected') and (team_private.is_owner(p_team,team_private.actor()) or
      team_private.has_capability(p_team,team_private.actor(),p_kind||'.review'))))
$$;
create function team_private.media_eligible(p_team uuid,p_actor uuid,p_kind text)
returns boolean language sql stable security definer set search_path=pg_catalog as $$
  select team_private.is_active(p_team,p_actor) and (p_kind='practice' or
    (p_kind='film' and team_private.has_capability(p_team,p_actor,'film.upload')))
$$;
-- Never fetch links server-side. Credentials/fragments/control characters are rejected.
create function team_private.media_link_valid(p_link text) returns boolean
language plpgsql immutable set search_path=pg_catalog as $$
declare q text; item text; name text;
begin
  if p_link is null or length(p_link)>2048 or p_link !~ '^https://[A-Za-z0-9][A-Za-z0-9.-]*(:443)?([/?][!-~]*)?$'
    or p_link ~ '[#@\\]' or p_link ~ '%(?![0-9A-Fa-f]{2})' then return false; end if;
  q := split_part(p_link,'?',2);
  foreach item in array string_to_array(q,'&') loop
    name := lower(split_part(item,'=',1));
    if name like '%\%%' escape '\' or name in
      ('token','access_token','refresh_token','id_token','auth','authorization','key','api_key','apikey',
       'secret','password','credential','signature','sig','code','jwt','x-amz-signature','x-amz-credential') then return false; end if;
  end loop;
  return true;
end $$;
create function team_private.media_text_valid(p_title text,p_link text,p_notes text,p_complete boolean) returns boolean
language sql immutable set search_path=pg_catalog as $$
  select p_title is not null and p_link is not null and p_notes is not null
    and length(p_title)<=120 and length(p_notes)<=1000
    and p_title !~ '[[:cntrl:]]' and p_notes !~ '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'
    and ((p_link='' and not p_complete) or team_private.media_link_valid(p_link))
    and (not p_complete or length(btrim(p_title))>0)
$$;
create function team_private.media_immutable() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
  if tg_op='DELETE' or old.status in ('published','rejected') or new.id<>old.id or new.team_id<>old.team_id
    or new.resource_id<>old.resource_id or new.author_user_id<>old.author_user_id
    or new.base_published_version_id is distinct from old.base_published_version_id
    or (old.status='submitted' and (new.title<>old.title or new.link_url<>old.link_url or new.notes<>old.notes)) then
    raise exception 'Media history is immutable; open a successor draft' using errcode='42501'; end if;
  return new;
end $$;
create trigger media_history_immutable before update or delete on public.media_resource_versions
for each row execute function team_private.media_immutable();
create function team_private.media_parent_immutable() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
  if tg_op='DELETE' or new.id<>old.id or new.team_id<>old.team_id or new.kind<>old.kind
    or new.play_id is distinct from old.play_id or new.game_id is distinct from old.game_id then
    raise exception 'Media linkage is immutable' using errcode='42501'; end if;
  return new;
end $$;
create trigger media_linkage_immutable before update or delete on public.media_resources
for each row execute function team_private.media_parent_immutable();
alter table public.media_resources enable row level security;
alter table public.media_resource_versions enable row level security;
create function team_private.media_parent_visible(p_team uuid,p_resource uuid,p_kind text) returns boolean
language sql stable security definer set search_path=pg_catalog as $$
  select exists(select 1 from public.media_resource_versions v where v.team_id=p_team and v.resource_id=p_resource
    and team_private.media_visible(p_team,v.author_user_id,v.status,p_kind))
$$;
create policy media_parent_read on public.media_resources for select to authenticated
using(team_private.media_parent_visible(team_id,id,kind));
create policy media_version_read on public.media_resource_versions for select to authenticated using (
  team_private.media_visible(team_id,author_user_id,status,(select kind from public.media_resources r where r.id=resource_id)));
revoke all on public.media_resources,public.media_resource_versions from public,anon,authenticated;
grant select on public.media_resources,public.media_resource_versions to authenticated;
create function public.media_open_draft(p_team_id uuid,p_resource_id uuid,p_kind text,p_target_id uuid,p_source_version_id uuid default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id); r public.media_resources; v public.media_resource_versions; source public.media_resource_versions;
begin
  if p_resource_id is null or p_target_id is null or p_kind is null or p_kind not in ('practice','film') then
    raise exception 'Valid media identity and target required' using errcode='22023'; end if;
  if not team_private.media_eligible(p_team_id,a,p_kind) then raise exception 'Film contribution eligibility required' using errcode='42501'; end if;
  if (p_kind='practice' and not exists(select 1 from public.plays where team_id=p_team_id and id=p_target_id and published_version_id is not null))
    or (p_kind='film' and not exists(select 1 from public.games where team_id=p_team_id and id=p_target_id)) then
    raise exception 'Existing published play or shared game required' using errcode='22023'; end if;
  select * into r from public.media_resources where id=p_resource_id for update;
  if found then
    if r.team_id<>p_team_id or r.kind<>p_kind or coalesce(r.play_id,r.game_id)<>p_target_id then
      raise exception 'Media identity already has different linkage' using errcode='40001'; end if;
  else
    if p_source_version_id is not null then raise exception 'Source does not belong to this resource' using errcode='22023'; end if;
    insert into public.media_resources(id,team_id,kind,play_id,game_id)
      values(p_resource_id,p_team_id,p_kind,case when p_kind='practice' then p_target_id end,case when p_kind='film' then p_target_id end) returning * into r;
  end if;
  select * into v from public.media_resource_versions where resource_id=r.id and author_user_id=a and status in ('draft','submitted');
  if found then
    if v.status='submitted' then raise exception 'Pending resource is frozen' using errcode='42501'; end if;
    return to_jsonb(v);
  end if;
  if p_source_version_id is not null then
    select * into source from public.media_resource_versions where id=p_source_version_id and resource_id=r.id;
    if not found or not (source.status='published' or (source.status='rejected' and source.author_user_id=a)) then
      raise exception 'Published or own rejected source required' using errcode='42501'; end if;
  elsif r.published_version_id is not null then
    raise exception 'Select a source revision to propose a correction' using errcode='22023'; end if;
  insert into public.media_resource_versions(team_id,resource_id,author_user_id,title,link_url,notes,base_published_version_id)
    values(p_team_id,r.id,a,coalesce(source.title,''),coalesce(source.link_url,''),coalesce(source.notes,''),r.published_version_id) returning * into v;
  perform team_private.audit(p_team_id,a,'media.draft_opened',v.id); return to_jsonb(v);
end $$;
create function public.media_save_draft(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_title text,p_link_url text,p_notes text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id); r public.media_resources; v public.media_resource_versions;
begin
  select * into v from public.media_resource_versions where id=p_version_id and team_id=p_team_id for update;
  if not found then raise exception 'Media access denied' using errcode='42501'; end if;
  select * into r from public.media_resources where id=v.resource_id for update;
  if v.author_user_id<>a or v.status<>'draft' or not team_private.media_eligible(p_team_id,a,r.kind) then
    raise exception 'Eligible draft author required' using errcode='42501'; end if;
  if p_expected_revision is distinct from v.revision then raise exception 'Media revision changed; reload' using errcode='40001'; end if;
  if not team_private.media_text_valid(p_title,p_link_url,p_notes,false) then raise exception 'Invalid media text or HTTPS link' using errcode='22023'; end if;
  update public.media_resource_versions set title=p_title,link_url=p_link_url,notes=p_notes,revision=revision+1,updated_at=now() where id=v.id returning * into v;
  perform team_private.audit(p_team_id,a,'media.draft_saved',v.id); return to_jsonb(v);
end $$;
create function public.media_transition(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_action text,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id); r public.media_resources; v public.media_resource_versions; next_status text;
begin
  select * into v from public.media_resource_versions where id=p_version_id and team_id=p_team_id for update;
  if not found then raise exception 'Media access denied' using errcode='42501'; end if;
  select * into r from public.media_resources where id=v.resource_id for update;
  if p_expected_revision is distinct from v.revision then raise exception 'Media revision changed; reload' using errcode='40001'; end if;
  if p_reason is null or length(p_reason)>500 or p_action is null or p_action not in ('submit','publish','approve','reject') then
    raise exception 'Invalid media transition' using errcode='22023'; end if;
  if p_action in ('submit','publish') then
    if v.author_user_id<>a or v.status<>'draft' or not team_private.media_eligible(p_team_id,a,r.kind) then
      raise exception 'Eligible draft author required' using errcode='42501'; end if;
    if p_action='publish' and not team_private.has_capability(p_team_id,a,r.kind||'.publish') then
      raise exception 'Own publication bypass required' using errcode='42501'; end if;
  elsif v.status<>'submitted' or not team_private.is_owner(p_team_id,a) then
    raise exception 'Only the owner reviews pending videos' using errcode='42501'; end if;
  if p_action<>'reject' and not team_private.media_text_valid(v.title,v.link_url,v.notes,true) then
    raise exception 'Title and valid HTTPS link required' using errcode='22023'; end if;
  next_status:=case when p_action='submit' then 'submitted' when p_action='reject' then 'rejected' else 'published' end;
  if next_status='published' and r.published_version_id is distinct from v.base_published_version_id then
    raise exception 'Published resource changed; open a fresh successor' using errcode='40001'; end if;
  update public.media_resource_versions set status=next_status,revision=revision+1,updated_at=now(),
    review_actor_user_id=case when p_action in ('approve','reject') then a else null end,
    review_reason=case when p_action in ('approve','reject') then p_reason else '' end where id=v.id returning * into v;
  if next_status='published' then update public.media_resources set published_version_id=v.id where id=r.id; end if;
  perform team_private.audit(p_team_id,a,'media.'||p_action,v.id); return to_jsonb(v);
end $$;
revoke execute on function team_private.media_visible(uuid,uuid,text,text),team_private.media_eligible(uuid,uuid,text),
  team_private.media_link_valid(text),team_private.media_text_valid(text,text,text,boolean),team_private.media_immutable(),
  team_private.media_parent_immutable(),team_private.media_parent_visible(uuid,uuid,text) from public,anon,authenticated;
grant execute on function team_private.media_visible(uuid,uuid,text,text),team_private.media_parent_visible(uuid,uuid,text) to authenticated;
revoke execute on function public.media_open_draft(uuid,uuid,text,uuid,uuid),
  public.media_save_draft(uuid,uuid,bigint,text,text,text),public.media_transition(uuid,uuid,bigint,text,text) from public,anon;
grant execute on function public.media_open_draft(uuid,uuid,text,uuid,uuid),
  public.media_save_draft(uuid,uuid,bigint,text,text,text),public.media_transition(uuid,uuid,bigint,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
