-- Conservative development admission, not provider/ingress protection or a $0 guarantee.
-- One current window per verified actor; no per-request history or caller-selected key.
create table team_private.file_request_windows (
  actor_id uuid primary key references auth.users(id),
  window_start timestamptz not null,
  requests integer not null check (requests between 1 and 31)
);
alter table team_private.file_request_windows enable row level security;
revoke all on team_private.file_request_windows from public, anon, authenticated, service_role;

create function public.file_request_admission() returns jsonb
language plpgsql security definer set search_path = pg_catalog as $$
declare
  actor uuid := team_private.actor();
  observed timestamptz := clock_timestamp();
  bucket team_private.file_request_windows;
begin
  if actor is null then raise insufficient_privilege using message='Verified current session required'; end if;
  insert into team_private.file_request_windows as w values (actor, observed, 1)
  on conflict (actor_id) do update set
    window_start = case when w.window_start + interval '60 seconds' <= observed then observed else w.window_start end,
    requests = case when w.window_start + interval '60 seconds' <= observed then 1 else least(w.requests+1,31) end
  returning * into bucket;
  return jsonb_build_object('allowed',bucket.requests <= 30,
    'retry_after',case when bucket.requests <= 30 then 0 else
      greatest(1,least(60,ceil(extract(epoch from bucket.window_start + interval '60 seconds' - observed))::integer)) end);
end;
$$;
revoke all on function public.file_request_admission() from public, anon, service_role;
grant execute on function public.file_request_admission() to authenticated;
comment on function public.file_request_admission() is
'Own committed admission transaction before file body/transfer. All upload/reconcile/delivery attempts share30 per60s per live verified actor. No automatic retries; unknown replies may retain a charge. Fixed-window boundary bursts remain possible. Not Auth/direct-RPC/invalid-token ingress protection.';
