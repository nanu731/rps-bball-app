-- New game-film saves/submissions are Hudl shortcuts, not hosted video files.
-- Existing versions are not rewritten; opening a successor can retain historical text.
begin;
create function team_private.hudl_link_valid(p_link text) returns boolean
language sql immutable set search_path=pg_catalog as $$
  select team_private.media_link_valid(p_link)
    and p_link ~* '^https://(www[.])?hudl[.]com(:443)?([/?]|$)'
$$;
create function team_private.media_hudl_shortcut_guard() returns trigger
language plpgsql set search_path=pg_catalog as $$
begin
  if exists (select 1 from public.media_resources r where r.id=new.resource_id and r.team_id=new.team_id and r.kind='film')
    and ((old.status='draft' and new.status='draft') or new.status in ('submitted','published'))
    and not (new.link_url='' and new.status='draft')
    and not team_private.hudl_link_valid(new.link_url) then
    raise exception 'Game film requires an HTTPS Hudl shortcut on hudl.com or www.hudl.com' using errcode='22023';
  end if;
  return new;
end $$;
-- RPCs already enforce authorization/revision locks; this adds destination validation
-- without replacing those commands or touching existing records and review grants.
create trigger media_hudl_shortcut_guard before update on public.media_resource_versions
  for each row execute function team_private.media_hudl_shortcut_guard();
revoke all on function team_private.hudl_link_valid(text),team_private.media_hudl_shortcut_guard() from public,anon,authenticated;
commit;
