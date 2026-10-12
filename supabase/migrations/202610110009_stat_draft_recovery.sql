-- Approved current-source reopening can retain an author's stale unfinished draft.
begin;
alter table public.stat_versions drop constraint stat_versions_status_check;
alter table public.stat_versions add constraint stat_versions_status_check
 check(status in ('draft','completed','submitted','rejected','published','superseded'));
alter table public.stat_versions add column recovery_source_version_id uuid;
alter table public.stat_versions add constraint stat_recovery_source_same_dataset
 foreign key(dataset_id,recovery_source_version_id) references public.stat_versions(dataset_id,id);
create unique index one_stat_recovery_per_source on public.stat_versions(recovery_source_version_id)
 where recovery_source_version_id is not null;
create or replace function team_private.stat_immutable() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
  if tg_op='DELETE' or old.status in ('published','superseded') or new.id<>old.id or new.team_id<>old.team_id
    or new.game_id<>old.game_id or new.dataset_id<>old.dataset_id or new.dataset_type<>old.dataset_type
    or new.author_user_id<>old.author_user_id or new.base_published_version_id is distinct from old.base_published_version_id
    or new.recovery_source_version_id is distinct from old.recovery_source_version_id
    or new.created_at<>old.created_at or new.revision<>old.revision+1
    or (old.status<>'draft' and (new.records is distinct from old.records or new.covered_roster is distinct from old.covered_roster))
    or (new.status='superseded' and (old.status<>'draft' or new.records is distinct from old.records or new.covered_roster is distinct from old.covered_roster)) then
    raise exception 'Completed version data is immutable' using errcode='42501';
  end if;
  return new;
end $$;

create or replace function public.stats_request_edit(p_team_id uuid,p_source_version_id uuid,p_expected_revision bigint,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); v public.stat_versions; req public.stat_edit_requests;
begin
  v := team_private.lock_stat(p_team_id,p_source_version_id,p_expected_revision);
  if v.status not in ('completed','submitted','rejected','published') or (v.status<>'published' and v.author_user_id<>a) then
    raise exception 'Published viewer or completed author required' using errcode='42501';
  end if;
  if p_reason is null or length(p_reason)>500 then raise exception 'Invalid edit request reason' using errcode='22023'; end if;
  select * into req from public.stat_edit_requests where source_version_id=v.id and requester_user_id=a and status='pending';
  if found then
    if req.reason<>p_reason then raise exception 'Pending request already has different reason' using errcode='40001'; end if;
    return to_jsonb(req);
  end if;
  insert into public.stat_edit_requests(team_id,source_version_id,requester_user_id,reason)
    values(p_team_id,v.id,a,p_reason) returning * into req;
  perform team_private.audit(p_team_id,a,'stats.edit_requested',req.id);
  return to_jsonb(req);
end $$;

create or replace function public.stats_review_edit(p_team_id uuid,p_request_id uuid,p_expected_revision bigint,p_approve boolean,p_reason text default '')
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare a uuid := team_private.member_actor(p_team_id); req public.stat_edit_requests; source public.stat_versions;
  v public.stat_versions; retained public.stat_versions; base uuid;
begin
  select * into req from public.stat_edit_requests where team_id=p_team_id and id=p_request_id;
  if not found then raise exception 'Edit request access denied' using errcode='42501'; end if;
  select * into source from public.stat_versions where id=req.source_version_id and team_id=p_team_id;
  if not found or source.status='superseded' then raise exception 'Completed source required' using errcode='42501'; end if;
  perform 1 from public.games where id=source.game_id for update;
  select * into req from public.stat_edit_requests where id=p_request_id for update;
  if req.revision is distinct from p_expected_revision then raise exception 'Edit request revision changed; reload' using errcode='40001'; end if;
  if req.status<>'pending' or not team_private.has_capability(p_team_id,a,'datasets.reopen')
    or (p_approve is true and req.requester_user_id=a and not team_private.is_owner(p_team_id,a))
    or not team_private.is_active(p_team_id,req.requester_user_id) then
    raise exception 'Independent completed-data review required' using errcode='42501';
  end if;
  if p_approve is null or p_reason is null or length(p_reason)>500 then raise exception 'Invalid edit review decision' using errcode='22023'; end if;
  if p_approve then
    select published_version_id into base from public.stat_datasets where id=source.dataset_id for update;
    if source.status='published' and source.id is distinct from base
      or source.status<>'published' and source.base_published_version_id is distinct from base then
      raise exception 'Source acceptance changed; request from current version' using errcode='40001';
    end if;
    select * into retained from public.stat_versions where dataset_id=source.dataset_id
      and author_user_id=req.requester_user_id and status='draft' for update;
    if found then
      if retained.base_published_version_id is not distinct from base then
        raise exception 'Existing unfinished draft must be preserved' using errcode='40001';
      end if;
      -- The approved current-source edit retains stale saved work without claiming completion.
      update public.stat_versions set status='superseded',revision=revision+1,updated_at=now()
        where id=retained.id returning * into retained;
      perform team_private.audit(p_team_id,a,'stats.draft_superseded',retained.id);
    end if;
    insert into public.stat_versions(team_id,game_id,dataset_id,dataset_type,author_user_id,records,covered_roster,base_published_version_id,recovery_source_version_id)
      values(p_team_id,source.game_id,source.dataset_id,source.dataset_type,req.requester_user_id,source.records,source.covered_roster,base,retained.id)
      returning * into v;
  end if;
  update public.stat_edit_requests set status=case when p_approve then 'approved' else 'rejected' end,
    revision=revision+1,review_reason=p_reason,working_version_id=v.id,reviewed_at=now() where id=req.id returning * into req;
  perform team_private.audit(p_team_id,a,case when p_approve then 'stats.edit_approved' else 'stats.edit_rejected' end,req.id);
  return jsonb_build_object('request',to_jsonb(req),'version',case when v.id is null then null else to_jsonb(v) end);
end $$;

commit;
