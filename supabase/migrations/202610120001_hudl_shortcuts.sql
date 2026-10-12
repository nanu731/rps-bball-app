-- New game-film saves/submissions are Hudl shortcuts, not hosted video files.
-- Existing versions are not rewritten; opening a successor can retain historical text.
begin;
-- Inspect the entire query after its first question mark; later question marks
-- are query content and cannot hide credential parameters. Existing rows stay intact.
create or replace function team_private.media_link_valid(p_link text) returns boolean
language plpgsql immutable set search_path=pg_catalog as $$
declare q text; item text; name text;
begin
  if p_link is null or length(p_link)>2048 or p_link !~ '^https://[A-Za-z0-9][A-Za-z0-9.-]*(:443)?([/?][!-~]*)?$'
    or p_link ~ '[#@\\]' or p_link ~ '%(?![0-9A-Fa-f]{2})' then return false; end if;
  q := case when position('?' in p_link)>0 then substr(p_link,position('?' in p_link)+1) else '' end;
  foreach item in array string_to_array(q,'&') loop
    name := lower(split_part(item,'=',1));
    if name like '%\%%' escape '\' or name in
      ('token','access_token','refresh_token','id_token','auth','authorization','key','api_key','apikey',
       'secret','password','credential','signature','sig','code','jwt','x-amz-signature','x-amz-credential') then return false; end if;
  end loop;
  return true;
end $$;
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
