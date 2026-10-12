-- Explicit stale-base recovery; preserve saved work rather than mutating its accepted base.
begin;
alter table public.play_versions drop constraint play_versions_status_check;
alter table public.play_versions add constraint play_versions_status_check
 check(status in ('draft','submitted','rejected','published','superseded'));
alter table public.play_versions add column recovery_source_version_id uuid;
alter table public.play_versions add constraint play_recovery_source_same_play
 foreign key(play_id,recovery_source_version_id) references public.play_versions(play_id,id);
create unique index one_play_recovery_per_source on public.play_versions(recovery_source_version_id)
 where recovery_source_version_id is not null;
create or replace function team_private.play_immutable() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
 if tg_op='DELETE' or old.status in ('published','rejected','superseded') or new.id<>old.id or new.team_id<>old.team_id
 or new.play_id<>old.play_id or new.author_user_id<>old.author_user_id or new.created_at<>old.created_at
 or new.base_published_version_id is distinct from old.base_published_version_id
 or new.recovery_source_version_id is distinct from old.recovery_source_version_id or new.revision<>old.revision+1
 or (old.status<>'draft' and (new.title is distinct from old.title or new.diagram is distinct from old.diagram))
 or (new.status='superseded' and (old.status<>'draft' or new.title is distinct from old.title or new.diagram is distinct from old.diagram)) then
 raise exception 'Frozen play revisions cannot be changed' using errcode='42501'; end if;
 return new;
end $$;
create function public.play_recover_draft(p_team_id uuid,p_version_id uuid,p_expected_revision bigint,p_expected_published_version_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid; old_saved public.play_versions; new_draft public.play_versions; pointer uuid;
begin
 actor:=team_private.member_actor(p_team_id);
 select * into old_saved from public.play_versions where id=p_version_id and team_id=p_team_id for update;
 if not found or old_saved.author_user_id<>actor or old_saved.status<>'draft'
 or not team_private.has_capability(p_team_id,actor,'plays.author') then
 raise exception 'Current author draft and authoring permission required' using errcode='42501'; end if;
 select published_version_id into pointer from public.plays where id=old_saved.play_id for update;
 if old_saved.revision is distinct from p_expected_revision or pointer is distinct from p_expected_published_version_id then
 raise exception 'Recovery inputs changed; reload current saved and published revisions' using errcode='40001'; end if;
 if pointer is null or old_saved.base_published_version_id is not distinct from pointer then
 raise exception 'Only a stale published-base draft needs explicit recovery' using errcode='22023'; end if;
 perform team_private.validate_play(old_saved.title,old_saved.diagram,false);
 update public.play_versions set status='superseded',revision=revision+1,updated_at=now()
 where id=old_saved.id returning * into old_saved;
 insert into public.play_versions(team_id,play_id,author_user_id,title,diagram,base_published_version_id,recovery_source_version_id)
 values(p_team_id,old_saved.play_id,actor,old_saved.title,old_saved.diagram,pointer,old_saved.id) returning * into new_draft;
 perform team_private.audit(p_team_id,actor,'play.draft.supersede',old_saved.id);
 perform team_private.audit(p_team_id,actor,'play.draft.recover',new_draft.id);
 return jsonb_build_object('superseded',to_jsonb(old_saved),'draft',to_jsonb(new_draft));
end $$;
revoke execute on function public.play_recover_draft(uuid,uuid,bigint,uuid) from public,anon,authenticated;
grant execute on function public.play_recover_draft(uuid,uuid,bigint,uuid) to authenticated;
commit;
