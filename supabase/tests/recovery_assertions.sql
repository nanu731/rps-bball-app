-- Run ONLY after restoring the synthetic archive, never after reseeding it.
-- Claims exercise database policies; they are NOT signed Auth/gateway evidence.
begin;
create function pg_temp.require(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Recovery assertion: %',message; end if; end $$;
create function pg_temp.denied(command text) returns void language plpgsql as $$
begin
 begin execute command; exception when insufficient_privilege then return; end;
 raise exception 'Expected permission denial';
end $$;
create function pg_temp.no_rows(command text) returns void language plpgsql as $$
declare count_rows bigint;
begin
 begin execute command into count_rows; exception when insufficient_privilege then return; end;
 perform pg_temp.require(count_rows=0,'protected rows were exposed');
end $$;
create function pg_temp.login(actor integer, session_number integer) returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claims',jsonb_build_object(
 'sub','f1000000-0000-4000-8000-'||lpad(actor::text,12,'0'),
 'session_id','f2000000-0000-4000-8000-'||lpad(session_number::text,12,'0'),
 'role','authenticated','is_anonymous',false,
 'exp',extract(epoch from now()+interval '1 hour'))::text,true);
end $$;
select pg_temp.require((select count(*)=1 from public.teams),'source team was not restored');
select pg_temp.require((select count(*)=2 from public.stat_versions),'version history missing');
select pg_temp.require((select count(*)=1 from public.stat_datasets d join public.stat_versions v
 on v.id=d.published_version_id where v.status='published'),'accepted pointer relationship');
select pg_temp.require((select count(*)=1 from public.roster_entry_revisions),'historical roster missing');
select pg_temp.require((select records->0->'values'->'points'='0'::jsonb
 and not (records->0->'values' ? 'assists') from public.stat_versions
 where id='f7000000-0000-4000-8000-000000000001'),'missing versus explicit zero');
select pg_temp.require((select count(*)=1 from public.team_audit_events),'audit history missing');
select pg_temp.require((select count(*)=1 from public.stat_export_deliveries
 where state='queued' and attempts=0),'outbox must stay queued, not dispatched');
select pg_temp.require((select count(*)=0 from public.stat_export_destinations),'no external destination');
select pg_temp.require((select storage_limit is null and transfer_limit is null and known_until is null
 from team_private.file_budget),'unknown media capacity must remain disabled');
select pg_temp.require(not exists(select 1 from pg_tables where schemaname='public' and not rowsecurity),
 'app-table RLS disabled');
select pg_temp.require(not has_schema_privilege('anon','supabase_migrations','usage')
 and not has_schema_privilege('authenticated','supabase_migrations','usage')
 and not has_table_privilege('anon','supabase_migrations.schema_migrations','select')
 and not has_table_privilege('authenticated','supabase_migrations.schema_migrations','select'),
 'migration-history privileges exposed');
select pg_temp.denied($q$update public.stat_versions set records='[]'
 where id='f7000000-0000-4000-8000-000000000001'$q$);
select pg_temp.denied($q$delete from public.team_audit_events$q$);
set local role anon;
select pg_temp.no_rows('select count(*) from public.teams');
select pg_temp.no_rows('select count(*) from storage.objects');
select pg_temp.denied($q$select public.team_access('f3000000-0000-4000-8000-000000000001')$q$);
reset role;
set local role authenticated;
select pg_temp.login(2,2);
select pg_temp.require((select count(*)=1 from public.teams),'active member lost access');
select pg_temp.require((select count(*)=1 from public.stat_versions),'member must see accepted version only');
select pg_temp.require(public.team_access('f3000000-0000-4000-8000-000000000001')->'capabilities' ? 'stats.review',
 'restored grant missing');
select pg_temp.denied($q$select public.team_set_membership(
 'f3000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000003','active',1)$q$);
select pg_temp.no_rows('select count(*) from storage.objects');
select pg_temp.login(3,3);
select pg_temp.no_rows('select count(*) from public.teams');
select pg_temp.denied($q$select public.team_access('f3000000-0000-4000-8000-000000000001')$q$);
select pg_temp.login(1,1);
select pg_temp.require((public.team_access('f3000000-0000-4000-8000-000000000001')->>'is_owner')::boolean,
 'verified synthetic owner UUID relationship lost');
select pg_temp.require((select count(*)=2 from public.stat_versions),'owner draft/history visibility');
select pg_temp.login(1,4); -- This session does not exist: retained UUID is not authority.
select pg_temp.no_rows('select count(*) from public.teams');
select pg_temp.denied($q$select public.team_access('f3000000-0000-4000-8000-000000000001')$q$);
rollback;
