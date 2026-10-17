-- Request intake only. No account/record deletion, processing queue or owner transfer.
-- Source/local preparation: do not activate on existing environments without review.
begin;
create table team_private.account_deletion_requests (
  user_id uuid primary key references auth.users(id) on delete restrict,
  id uuid not null unique default gen_random_uuid(),
  requested_at timestamptz not null default clock_timestamp() check (isfinite(requested_at))
);
alter table team_private.account_deletion_requests enable row level security;
revoke all on team_private.account_deletion_requests from public, anon, authenticated, service_role;

-- Account-level eligibility must not depend on team admission. Serialize receipt
-- transactions with session revocation/account disable, using the existing command
-- lock/recheck pattern. No role/contact supplied by the client establishes identity.
create function team_private.account_request_actor() returns uuid
language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.actor();
begin
  if v_actor is null then
    raise exception using errcode='42501',message='Verified current account required';
  end if;
  perform 1 from auth.users where id=v_actor and deleted_at is null
    and (banned_until is null or banned_until <= clock_timestamp()) for share;
  if not found then
    raise exception using errcode='42501',message='Verified current account required';
  end if;
  perform 1 from auth.sessions where id=(auth.jwt()->>'session_id')::uuid and user_id=v_actor
    and (not_after is null or not_after > clock_timestamp()) for share;
  if not found or team_private.actor() is distinct from v_actor then
    raise exception using errcode='42501',message='Verified current account required';
  end if;
  return v_actor;
end $$;
revoke all on function team_private.account_request_actor() from public, anon, authenticated, service_role;

create function public.account_deletion_receipt() returns jsonb
language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.account_request_actor();
begin
  return (select to_jsonb(r) from team_private.account_deletion_requests r where r.user_id=v_actor);
end $$;

create function public.account_request_deletion() returns jsonb
language plpgsql security definer set search_path = pg_catalog as $$
declare v_actor uuid := team_private.account_request_actor();
begin
  -- Concurrent callers wait on the unique account key. The next statement reads
  -- the committed winner; neither retries nor app restarts rewrite its receipt.
  insert into team_private.account_deletion_requests(user_id) values(v_actor)
    on conflict(user_id) do nothing;
  -- Count any elapsed token/session expiry during a concurrent insert wait.
  perform team_private.account_request_actor();
  return (select to_jsonb(r) from team_private.account_deletion_requests r where r.user_id=v_actor);
end $$;
revoke all on function public.account_deletion_receipt(), public.account_request_deletion()
  from public, anon, authenticated, service_role;
grant execute on function public.account_deletion_receipt(), public.account_request_deletion() to authenticated;
commit;
