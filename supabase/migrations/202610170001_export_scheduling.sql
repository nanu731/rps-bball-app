-- Preparation only. Apply through a separate reviewed activation; no schedule or provider calls.
begin;
alter table public.stat_export_deliveries
 add column queue_state text not null default 'ready' check(queue_state in ('ready','claimed','manual_review','settled')),
 add column next_attempt_at timestamptz default now(),
 add column cycle_started_at timestamptz not null default now(),
 add column retry_attempts integer not null default 0 check(retry_attempts between 0 and 5),
 add column claim_total bigint not null default 0 check(claim_total>=0),
 add column review_cycles bigint not null default 0 check(review_cycles>=0),
 add column last_review_reason text,
 add column last_failure_code text,
 add column claim_token uuid,
 add column claim_until timestamptz,
 add column provider_not_before timestamptz,
 add column provider_pause boolean not null default false;
update public.stat_export_deliveries set queue_state='settled',next_attempt_at=null where state='delivered';
-- Prior retries have no durable provider delay/claim evidence. Never auto-resume them.
update public.stat_export_deliveries set queue_state='manual_review',next_attempt_at=null,
 last_failure_code=error_code,last_review_reason='legacy_failure_review' where state='failed';
alter table public.stat_export_deliveries add constraint export_claim_shape check(
 (queue_state='claimed' and claim_token is not null and claim_until is not null and next_attempt_at is null)
 or (queue_state<>'claimed' and claim_until is null));

-- Private timing seam allows deterministic synthetic tests; clients cannot set time/jitter.
create function team_private.export_now() returns timestamptz language sql volatile set search_path=pg_catalog as $$select clock_timestamp()$$;
create function team_private.export_jitter() returns double precision language sql volatile set search_path=pg_catalog as $$select random()$$;
create function team_private.export_retry(p_job_id uuid,p_code text,p_retry_after integer default null) returns void
language plpgsql set search_path=pg_catalog as $$
declare d public.stat_export_deliveries; delay integer; terminal boolean; t timestamptz:=team_private.export_now();
begin
 select * into strict d from public.stat_export_deliveries where job_id=p_job_id for update;
 delay:=floor(least(3600,30*power(2,least(d.retry_attempts,5)-1))*(0.5+team_private.export_jitter()*0.5))::integer;
 delay:=greatest(delay,coalesce(p_retry_after,0));
 terminal:=p_code not in ('provider_timeout','provider_transport','provider_response','provider_http_408','provider_http_429',
   'provider_http_500','provider_http_502','provider_http_503','provider_http_504','backend_transport','claim_expired','run_deadline','request_limit')
   or d.retry_attempts>=5 or t+make_interval(secs=>delay)>d.cycle_started_at+interval '7 days'
   or coalesce(p_retry_after>86400,false);
 update public.stat_export_deliveries set state='failed',error_code=p_code,last_failure_code=p_code,
   queue_state=case when terminal then 'manual_review' else 'ready' end,
   last_review_reason=case when terminal then case when d.retry_attempts>=5 then 'retry_exhausted' else p_code end else last_review_reason end,
   next_attempt_at=case when terminal then null else t+make_interval(secs=>delay) end,
   provider_not_before=case when p_code in ('provider_http_429','provider_http_503') then t+make_interval(secs=>delay) else provider_not_before end,
   provider_pause=case when p_code in ('provider_http_429','provider_http_503') then coalesce(p_retry_after>86400,false) else provider_pause end,
   claim_token=null,claim_until=null,updated_at=t where job_id=p_job_id;
end $$;

create function team_private.export_provider_paused() returns boolean language sql volatile set search_path=pg_catalog as $$
 select exists(select 1 from public.stat_export_deliveries where provider_pause or provider_not_before>team_private.export_now())
$$;
create function public.stats_export_claim() returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare d public.stat_export_deliveries; t timestamptz:=team_private.export_now(); token uuid;
begin
 perform team_private.export_service();
 -- Bounded recovery work. Crashes consume claims and get backoff, never immediate replay.
 for d in select * from public.stat_export_deliveries where queue_state='claimed' and claim_until<=t
   order by claim_until,job_id for update skip locked limit 3 loop
   perform team_private.export_retry(d.job_id,'claim_expired');
 end loop;
 if team_private.export_provider_paused() then return null; end if;
 -- Bound stale cycles too; no unbounded scan/update before selecting work.
 for d in select * from public.stat_export_deliveries where queue_state='ready' and state<>'delivered'
   and (cycle_started_at+interval '7 days'<=t or retry_attempts>=5 or claim_total=9223372036854775807)
   order by next_attempt_at,job_id for update skip locked limit 3 loop
   perform team_private.export_retry(d.job_id,'retry_exhausted');
 end loop;
 select * into d from public.stat_export_deliveries where queue_state='ready' and state<>'delivered'
   and next_attempt_at<=t and retry_attempts<5 and claim_total<9223372036854775807
   and cycle_started_at+interval '7 days'>t order by next_attempt_at,job_id for update skip locked limit 1;
 if not found then return null; end if;
 token:=gen_random_uuid();
 update public.stat_export_deliveries set queue_state='claimed',next_attempt_at=null,claim_token=token,
   claim_until=least(t+interval '5 minutes',d.cycle_started_at+interval '7 days'),retry_attempts=retry_attempts+1,claim_total=claim_total+1,updated_at=t where job_id=d.job_id;
 return jsonb_build_object('job_id',d.job_id,'claim_token',token);
end $$;
create function team_private.export_assert_claim(p_job_id uuid,p_claim_token uuid) returns void
language plpgsql set search_path=pg_catalog as $$
declare d public.stat_export_deliveries;
begin
 perform team_private.export_service();
 -- Keep team-before-delivery lock order used by immutable reservation/publication.
 perform 1 from public.teams where id=(select team_id from public.stat_export_deliveries where job_id=p_job_id) for update;
 select * into d from public.stat_export_deliveries where job_id=p_job_id for update;
 if not found or p_claim_token is null or d.claim_token is distinct from p_claim_token
   or (d.state<>'delivered' and (d.queue_state<>'claimed' or d.claim_until<=team_private.export_now())) then
   raise exception 'Current export claim required' using errcode='PT409';
 end if;
end $$;
create function public.stats_export_claimed_reserve(p_job_id uuid,p_claim_token uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
begin
 perform team_private.export_assert_claim(p_job_id,p_claim_token);
 return public.stats_export_reserve(p_job_id);
end $$;
create function public.stats_export_acknowledge(p_job_id uuid,p_claim_token uuid,p_receipt jsonb) returns void
language plpgsql security definer set search_path=pg_catalog as $$
begin
 perform team_private.export_assert_claim(p_job_id,p_claim_token);
 perform public.stats_export_finish(p_job_id,p_receipt);
 update public.stat_export_deliveries set queue_state='settled',next_attempt_at=null,claim_until=null where job_id=p_job_id;
end $$;
create function public.stats_export_record_failure(p_job_id uuid,p_claim_token uuid,p_error_code text,p_retry_after integer default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
begin
 perform team_private.export_assert_claim(p_job_id,p_claim_token);
 if (select state='delivered' from public.stat_export_deliveries where job_id=p_job_id) then return jsonb_build_object('state','delivered'); end if;
 if p_error_code is null or p_error_code not in ('budget_disabled','configuration_invalid','request_limit','payload_too_large',
   'payload_hash_mismatch','payload_identity_mismatch','destination_conflict','destination_capacity','provider_response',
   'provider_timeout','provider_transport','response_too_large','redirect_denied','backend_transport','claim_expired','run_deadline',
   'retry_exhausted','destination_unavailable') and p_error_code !~ '^provider_http_[1-5][0-9]{2}$'
   or p_retry_after<0 then raise exception 'Fixed export failure required' using errcode='22023'; end if;
 perform team_private.export_retry(p_job_id,p_error_code,p_retry_after);
 return jsonb_build_object('state','failed');
end $$;
create function public.stats_export_resume(p_job_id uuid,p_provider_pause_resolved boolean default false) returns void
language plpgsql security definer set search_path=pg_catalog as $$
declare d public.stat_export_deliveries;
begin
 perform team_private.export_service();
 select * into d from public.stat_export_deliveries where job_id=p_job_id for update;
 if not found or (d.provider_pause and p_provider_pause_resolved is distinct from true) or d.queue_state<>'manual_review' or d.state='delivered' or d.review_cycles=9223372036854775807 then
   raise exception 'Stopped export requires trusted review' using errcode='PT409'; end if;
 update public.stat_export_deliveries set queue_state='ready',next_attempt_at=team_private.export_now(),
   cycle_started_at=team_private.export_now(),retry_attempts=0,review_cycles=review_cycles+1,
   provider_pause=false,claim_token=null,claim_until=null,updated_at=team_private.export_now() where job_id=p_job_id;
end $$;
-- No legacy worker can bypass fencing. Owners retain the compatible failed/delivered view.
revoke execute on function public.stats_export_reserve(uuid),public.stats_export_finish(uuid,jsonb),public.stats_export_fail(uuid,text) from service_role;
create or replace function public.stats_export_jobs(p_limit integer default 3) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
begin
 perform team_private.export_service();
 if p_limit is null or p_limit not between 1 and 10 then raise exception 'Bounded job count required' using errcode='22023'; end if;
 if team_private.export_provider_paused() then return '[]'::jsonb; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('job_id',q.job_id)),'[]') from
   (select job_id from public.stat_export_deliveries where state<>'delivered' and queue_state='ready'
    and next_attempt_at<=team_private.export_now() and retry_attempts<5
    and cycle_started_at+interval '7 days'>team_private.export_now() order by next_attempt_at,job_id limit p_limit) q);
end $$;
-- Extend the explicit owner-only projection; never expose tokens or destination bindings.
create or replace function public.stats_export_status(p_team_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid := team_private.member_actor(p_team_id);
begin
  if not team_private.is_owner(p_team_id,actor) then raise exception 'Owner export status required' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('job_id',o.id,'game_id',o.game_id,'accepted_version_id',o.accepted_version_id,
    'provider_not_before',d.provider_not_before,'provider_pause',d.provider_pause,'queue_state',d.queue_state,'next_attempt_at',d.next_attempt_at,'retry_attempts',d.retry_attempts,
    'claim_total',d.claim_total,'review_cycles',d.review_cycles,'last_review_reason',d.last_review_reason,
    'last_failure_code',d.last_failure_code,'dataset_type',v.dataset_type,'publication_generation',o.publication_generation,'state',d.state,'attempts',d.attempts,
    'error_code',d.error_code,'delivered_at',d.delivered_at) order by o.created_at,o.publication_generation),'[]'::jsonb)
    from public.stat_export_outbox o join public.stat_versions v on v.id=o.accepted_version_id
    join public.stat_export_deliveries d on d.job_id=o.id where o.team_id=p_team_id);
end $$;
revoke all on function team_private.export_now(),team_private.export_jitter(),team_private.export_provider_paused(),team_private.export_retry(uuid,text,integer),team_private.export_assert_claim(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.stats_export_claim(),public.stats_export_claimed_reserve(uuid,uuid),public.stats_export_acknowledge(uuid,uuid,jsonb),public.stats_export_record_failure(uuid,uuid,text,integer),public.stats_export_resume(uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.stats_export_claim(),public.stats_export_claimed_reserve(uuid,uuid),public.stats_export_acknowledge(uuid,uuid,jsonb),public.stats_export_record_failure(uuid,uuid,text,integer),public.stats_export_resume(uuid,boolean) to service_role;
commit;
