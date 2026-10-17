-- ONLY synthetic recovery fixtures, never a hosted/original database.
-- Rollback preserves restored records. Concurrent committed admissions are checked separately.
begin;
create function pg_temp.require(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Admission assertion: %',message; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin
 begin execute command; exception when insufficient_privilege then return; end;
 raise exception 'Expected permission denial';
end $$;
select pg_temp.require(not has_table_privilege('authenticated','team_private.file_request_windows','select')
 and not has_table_privilege('authenticated','team_private.file_request_windows','insert')
 and not has_table_privilege('service_role','team_private.file_request_windows','update'), 'private counter exposed');
select pg_temp.require((select relrowsecurity from pg_class where oid='team_private.file_request_windows'::regclass), 'RLS required');
set local role anon;
select pg_temp.denied('select public.file_request_admission()');
reset role;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000004','exp',extract(epoch from now()+interval '1 hour'))::text,true);
select pg_temp.denied('select public.file_request_admission()'); -- Session absent.
select set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','exp',1)::text,true);
select pg_temp.denied('select public.file_request_admission()'); -- Expired access claim.
select set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','exp',extract(epoch from now()+interval '1 hour'))::text,true);
do $$ declare reply jsonb; begin
 for i in 1..30 loop
  reply := public.file_request_admission();
  perform pg_temp.require(reply='{"allowed":true,"retry_after":0}', 'early rejection');
 end loop;
 reply := public.file_request_admission();
 perform pg_temp.require((reply->>'allowed')::boolean=false and (reply->>'retry_after')::integer between 1 and 60, 'missing throttling');
end $$;
reset role;
select pg_temp.require((select requests=31 from team_private.file_request_windows where actor_id='f1000000-0000-4000-8000-000000000001'), 'counter identity/count');
-- Move only this synthetic fixture's bucket past its window, without waiting or changing server time.
update team_private.file_request_windows set window_start=clock_timestamp()-interval '61 seconds';
set local role authenticated;
select pg_temp.require(public.file_request_admission()='{"allowed":true,"retry_after":0}', 'window did not recover');
select set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000002',
 'session_id','f2000000-0000-4000-8000-000000000002','exp',extract(epoch from now()+interval '1 hour'))::text,true);
select pg_temp.require(public.file_request_admission()='{"allowed":true,"retry_after":0}', 'another actor charged');
reset role;
select pg_temp.require((select count(*)=2 from team_private.file_request_windows), 'caller-selected bucket or row growth');
rollback;
