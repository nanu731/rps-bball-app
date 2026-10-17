-- Source/local preparation only. Role creation is cluster-wide: separate reviewed activation required.
begin;
-- A collision aborts the transaction; never adopt or alter an unknown existing role.
create role teamstats_export_worker nologin noinherit nobypassrls nosuperuser nocreatedb nocreaterole noreplication;
grant teamstats_export_worker to authenticator with admin false, inherit false, set true;
grant usage on schema public to teamstats_export_worker;
grant execute on function public.stats_export_claim(),public.stats_export_claimed_reserve(uuid,uuid),
 public.stats_export_acknowledge(uuid,uuid,jsonb),public.stats_export_record_failure(uuid,uuid,text,integer)
 to teamstats_export_worker;

create or replace function team_private.export_service() returns void language plpgsql set search_path=pg_catalog as $$
declare claims jsonb; issued numeric; expires numeric; t numeric:=extract(epoch from clock_timestamp());
begin
 if current_setting('role',true)='service_role' then return; end if; -- Existing trusted administration compatibility.
 if current_setting('role',true) is distinct from 'teamstats_export_worker' then
  raise exception 'Trusted export runtime required' using errcode='42501';
 end if;
 begin
  claims:=current_setting('request.jwt.claims',true)::jsonb;
  if claims->>'role' is distinct from 'teamstats_export_worker'
   or claims->>'aud' is distinct from 'authenticated'
   or jsonb_typeof(claims->'iat') is distinct from 'number'
   or jsonb_typeof(claims->'exp') is distinct from 'number'
   or (claims->>'iat') !~ '^[0-9]{1,12}$' or (claims->>'exp') !~ '^[0-9]{1,12}$' then
   raise exception 'Invalid export claims';
  end if;
  issued:=(claims->>'iat')::numeric; expires:=(claims->>'exp')::numeric;
  if issued>t+30 or expires<=t or expires<=issued or expires-issued>900 then
   raise exception 'Expired or unbounded export claims';
  end if;
 exception when others then
  raise exception 'Current bounded export credential required' using errcode='42501';
 end;
end $$;
-- Effective PUBLIC privileges count too. Abort rather than changing unrelated grants.
do $$
begin
 if has_schema_privilege('teamstats_export_worker','public','CREATE')
  or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
   and has_function_privilege('teamstats_export_worker',p.oid,'EXECUTE')
   and p.oid not in ('public.stats_export_claim()'::regprocedure,'public.stats_export_claimed_reserve(uuid,uuid)'::regprocedure,
    'public.stats_export_acknowledge(uuid,uuid,jsonb)'::regprocedure,'public.stats_export_record_failure(uuid,uuid,text,integer)'::regprocedure))
  or exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','auth','storage','team_private','supabase_migrations') and c.relkind in ('r','v','m','p','f')
   and (has_table_privilege('teamstats_export_worker',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    or has_any_column_privilege('teamstats_export_worker',c.oid,'SELECT,INSERT,UPDATE,REFERENCES'))) then
  raise exception 'Unexpected inherited export privileges' using errcode='42501';
 end if;
end $$;
commit;
