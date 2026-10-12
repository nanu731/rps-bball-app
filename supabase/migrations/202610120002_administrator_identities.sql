-- Private identification for existing team administration; identifiers grant no authority.
begin;
create function public.team_administrator_identities(p_team_id uuid)
returns table(user_id uuid,email text,phone text)
language plpgsql stable security definer set search_path = pg_catalog as $$
begin
  if not team_private.can_admin_read(p_team_id) or not exists (
    select 1 from auth.users actor where actor.id=team_private.actor()
      and actor.deleted_at is null
      and (actor.banned_until is null or actor.banned_until <= clock_timestamp())
  ) then
    raise exception using errcode='42501',message='Team administration access required';
  end if;
  return query select m.user_id,
    case when u.email_confirmed_at is not null and u.is_anonymous is not true
      and u.deleted_at is null then nullif(u.email,'') end,
    case when u.phone_confirmed_at is not null and u.is_anonymous is not true
      and u.deleted_at is null then nullif(u.phone,'') end
  from public.team_memberships m join auth.users u on u.id=m.user_id
  where m.team_id=p_team_id order by m.user_id;
end $$;
revoke all on function public.team_administrator_identities(uuid) from public,anon,authenticated;
grant execute on function public.team_administrator_identities(uuid) to authenticated;
commit;
