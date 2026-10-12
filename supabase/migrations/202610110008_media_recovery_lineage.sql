-- Exact recovery provenance for deliberate attachment after a lost acknowledgment.
-- Nullable for historical revisions; no guessed lineage or data backfill.
begin;
alter table public.media_resource_versions add column recovery_source_version_id uuid;
alter table public.media_resource_versions add foreign key(resource_id,recovery_source_version_id)
  references public.media_resource_versions(resource_id,id) on delete restrict;
create unique index media_unique_recovery_source on public.media_resource_versions(recovery_source_version_id)
  where recovery_source_version_id is not null;
create or replace function team_private.media_immutable() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
  if tg_op='DELETE' or old.status in ('published','rejected','superseded') or new.id<>old.id or new.team_id<>old.team_id
    or new.resource_id<>old.resource_id or new.author_user_id<>old.author_user_id or new.created_at<>old.created_at
    or new.recovery_source_version_id is distinct from old.recovery_source_version_id
    or new.base_published_version_id is distinct from old.base_published_version_id or new.revision<>old.revision+1
    or (old.status='submitted' and (new.title<>old.title or new.link_url<>old.link_url or new.notes<>old.notes)) then
    raise exception 'Media history is immutable; open a successor draft' using errcode='42501'; end if;
  return new;
end $$;
create or replace function public.media_resume_draft(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_expected_published_version_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid:=team_private.member_actor(p_team_id); r public.media_resources;
  previous public.media_resource_versions; fresh public.media_resource_versions;
begin
  select * into previous from public.media_resource_versions where id=p_version_id and team_id=p_team_id for update;
  if not found then raise exception 'Media access denied' using errcode='42501'; end if;
  select * into r from public.media_resources where id=previous.resource_id for update;
  if previous.author_user_id<>a or previous.status<>'draft' or not team_private.media_eligible(p_team_id,a,r.kind) then
    raise exception 'Eligible stale draft author required' using errcode='42501'; end if;
  if p_expected_revision is distinct from previous.revision or p_expected_published_version_id is null
    or p_expected_published_version_id is distinct from r.published_version_id then
    raise exception 'Current media publication changed; reload before resuming' using errcode='40001'; end if;
  if previous.base_published_version_id is not distinct from r.published_version_id then
    raise exception 'Draft already uses current accepted link' using errcode='22023'; end if;
  update public.media_resource_versions set status='superseded',revision=revision+1,updated_at=now()
    where id=previous.id returning * into previous;
  insert into public.media_resource_versions(team_id,resource_id,author_user_id,title,link_url,notes,base_published_version_id,recovery_source_version_id)
    values(previous.team_id,previous.resource_id,a,previous.title,previous.link_url,previous.notes,r.published_version_id,previous.id) returning * into fresh;
  perform team_private.audit(p_team_id,a,'media.draft_superseded',previous.id);
  perform team_private.audit(p_team_id,a,'media.draft_resumed',fresh.id);
  return jsonb_build_object('previous',to_jsonb(previous),'draft',to_jsonb(fresh));
end $$;
notify pgrst,'reload schema';
commit;
