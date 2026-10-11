-- Synthetic identities only. Run against a disposable local Supabase database.
-- Tests are authored before the migration; pre-migration failure is expected.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();

insert into auth.users (id, email, email_confirmed_at)
select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       'synthetic-' || n || '@example.invalid', now()
from generate_series(1, 6) n;
insert into auth.sessions (id, user_id, not_after)
select ('10000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       now() + interval '1 day'
from generate_series(1, 6) n;
create function pg_temp.login(n integer) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', '00000000-0000-4000-8000-' || lpad(n::text,12,'0'),
    'session_id', '10000000-0000-4000-8000-' || lpad(n::text,12,'0'),
    'role', 'authenticated', 'is_anonymous', false,
    'exp', extract(epoch from now() + interval '1 hour'))::text, true);
end $$;
create temporary table test_roster_result (id uuid);
grant select, insert on test_roster_result to authenticated;
create temporary table test_audit_result (event_count bigint);
grant select, insert on test_audit_result to authenticated;
-- Trusted setup after verified Auth UUID; not an authenticated bootstrap RPC.
insert into public.teams (id, name, owner_auth_uuid)
values ('20000000-0000-4000-8000-000000000001', 'SYNTHETIC TEST TEAM',
        '00000000-0000-4000-8000-000000000001');
insert into public.teams (id,name,owner_auth_uuid)
values ('20000000-0000-4000-8000-000000000002','SYNTHETIC SECOND TEAM',
        '00000000-0000-4000-8000-000000000001');
-- Existing data makes denied-read assertions meaningful, rather than empty-table successes.
insert into public.roster_entries(team_id,display_name,jersey_number)
values ('20000000-0000-4000-8000-000000000001','SYNTHETIC VISIBILITY FIXTURE','99');

set local role authenticated;
select pg_temp.login(2);
select lives_ok($$select public.team_request_membership('20000000-0000-4000-8000-000000000001')$$,
  'verified account may request pending admission');
select is(public.team_request_membership('20000000-0000-4000-8000-000000000001'),'pending',
  'retry returns server-confirmed pending membership without activating it');
select is((select count(*)::int from public.teams), 0, 'pending member cannot read team');
select is((select count(*)::int from public.roster_entries),0,'pending member cannot read existing roster data');
select throws_ok($$select public.team_access('20000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'pending member cannot read access');
select throws_ok($$select public.team_save_roster('20000000-0000-4000-8000-000000000001', 'SYNTHETIC PLAYER', '1')$$,
  '42501', null, 'pending member cannot manage roster');
select pg_temp.login(1);
select lives_ok($$select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','active')$$,
  'owner admits verified pending account');
select pg_temp.login(2);
select is((select count(*)::int from public.teams), 1, 'active member reads team');
select is((select count(*)::int from public.roster_entries),1,'active member reads existing roster data');
select is((public.team_access('20000000-0000-4000-8000-000000000001')->>'can_propose_stats')::boolean,
  true, 'stats proposals are active-member baseline');
select throws_ok($$select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','active')$$,
  '42501', null, 'ordinary member cannot admit others');
select throws_ok($$insert into public.team_memberships(team_id,user_id,status) values ('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','active')$$,
  '42501', null, 'direct self-role table write denied');
select pg_temp.login(3);
select is((select count(*)::int from public.roster_entries),0,'nonmember cannot read roster');
select throws_ok($$select public.team_access('20000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'nonmember access command denied');
select pg_temp.login(1);
select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','active');
select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','active');
select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','roster.manage',true);
select pg_temp.login(2);
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','roster.manage',true)$$,
  '42501', null, 'operational permission cannot grant permissions');
select throws_ok($$select public.team_delegate('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003',array['roster.manage'],now()+interval '1 day')$$,
  '42501', null, 'operational permission cannot create delegation');
select pg_temp.login(1);
select public.team_delegate('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002',array['roster.manage'],now()+interval '1 hour');
select public.team_set_membership('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','active');
select public.team_set_membership('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003','active');
select pg_temp.login(2);
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003','roster.manage',true,now()+interval '5 minutes')$$,
  '42501', null, 'delegation cannot cross team scope');
select lives_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','roster.manage',true,now()+interval '30 minutes')$$,
  'delegate grants enumerated capability to another active member');
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','roster.manage',true,now()+interval '30 minutes')$$,
  '42501', null, 'delegate self-grant denied');
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','stats.publish',true,now()+interval '30 minutes')$$,
  '42501', null, 'delegate over-capability grant denied');
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','roster.manage',true,now()+interval '2 days')$$,
  '42501', null, 'delegate cannot extend grant beyond envelope expiry');
select throws_ok($$select public.team_delegate('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003',array['roster.manage'],now()+interval '1 day')$$,
  '42501', null, 'delegate cannot delegate onward');
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','roster.manage',false)$$,
  '42501', null, 'delegate cannot alter owner');
select pg_temp.login(1);
select throws_ok($$select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','removed')$$,
  '42501', null, 'owner cannot be removed');
select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','members.manage',true);
select pg_temp.login(2);
select throws_ok($$select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','removed')$$,
  '42501', null, 'membership administrator cannot remove owner');
select throws_ok($$select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','active')$$,
  '42501', null, 'membership administrator cannot change own admission');
select pg_temp.login(3);
insert into test_roster_result select public.team_save_roster('20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER','1');
select lives_ok(format('select public.team_save_roster(%L,%L,%L,%L,1)',
  '20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER EDIT','2', (select id from test_roster_result)),
  'authorized roster edit retains identity');
select throws_ok(format('select public.team_save_roster(%L,%L,%L,%L,1)',
  '20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER STALE','3', (select id from test_roster_result)),
  '40001', null, 'stale roster save rejected');
select public.team_archive_roster('20000000-0000-4000-8000-000000000001', (select id from test_roster_result), 2);
select is((select count(*)::int from public.roster_entries where id=(select id from test_roster_result) and archived_at is not null),1,
  'archived roster identity remains readable for historical references');
select is((select count(*)::int from public.roster_entry_revisions where roster_id=(select id from test_roster_result)),3,
  'add, edit and archive retain all roster revisions');
select is((select display_name from public.roster_entry_revisions where roster_id=(select id from test_roster_result) and version=1),
  'SYNTHETIC PLAYER','roster edit preserves original historical label');
select isnt(public.team_save_roster('20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER EDIT','2')::text,
  (select id::text from test_roster_result), 'new real player gets fresh identity despite matching display values');
select throws_ok(format('select public.team_save_roster(%L,%L,%L,%L,3)',
  '20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER','4', (select id from test_roster_result)),
  '42501', null, 'archived identity cannot be repurposed');
select pg_temp.login(1);
select public.team_revoke_delegation('20000000-0000-4000-8000-000000000001',
  (select id from public.delegation_envelopes where delegate_user_id='00000000-0000-4000-8000-000000000002' and revoked_at is null));
select pg_temp.login(2);
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','roster.manage',true,now()+interval '5 minutes')$$,
  '42501', null, 'revoked delegate cannot grant');
select pg_temp.login(3);
select throws_ok($$select public.team_save_roster('20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER','5')$$,
  '42501', null, 'revoking envelope disables grants derived from it');
reset role;
-- Trusted fixture advances an envelope into the past; no wait or fake command implementation.
select pg_temp.login(1);
set local role authenticated;
select public.team_delegate('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004',array['roster.manage'],now()+interval '1 hour');
reset role;
update public.delegation_envelopes set expires_at=now()-interval '1 second'
where delegate_user_id='00000000-0000-4000-8000-000000000004';
set local role authenticated;
select pg_temp.login(4);
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','roster.manage',true,now()+interval '5 minutes')$$,
  '42501', null, 'expired delegate cannot grant');
select pg_temp.login(1);
select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','roster.manage',false);
select pg_temp.login(2);
select throws_ok($$select public.team_save_roster('20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER','6')$$,
  '42501', null, 'revoked direct operational grant denies roster mutation');
select pg_temp.login(1);
select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','roster.manage',true);
select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','removed');
select pg_temp.login(4);
select is((select count(*)::int from public.teams),0,'removed member immediately loses team reads');
select is(public.team_request_membership('20000000-0000-4000-8000-000000000001'),'removed',
  'removed membership request cannot readmit or mislabel itself');
select throws_ok($$select public.team_access('20000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'removed member access command denied');
select pg_temp.login(1);
select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','active');
select pg_temp.login(4);
select throws_ok($$select public.team_save_roster('20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER','7')$$,
  '42501', null, 'readmission never restores old capabilities');
select is(jsonb_array_length(public.team_access('20000000-0000-4000-8000-000000000001')->'grant_envelopes'),0,
  'readmission never restores old delegation');
select set_config('request.jwt.claims', (current_setting('request.jwt.claims')::jsonb ||
  jsonb_build_object('user_metadata',jsonb_build_object('role','owner','capabilities',array['members.manage'])))::text,true);
select throws_ok($$select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000005','active')$$,
  '42501', null, 'writable role/capability metadata cannot grant authority');
select throws_ok($$insert into public.teams(name,owner_auth_uuid) values ('SYNTHETIC FORGED TEAM','00000000-0000-4000-8000-000000000004')$$,
  '42501', null, 'authenticated user cannot bootstrap owner authority');
select throws_ok($$update public.teams set owner_auth_uuid='00000000-0000-4000-8000-000000000004'$$,
  '42501', null, 'direct owner tampering denied');
select throws_ok($$insert into public.capability_grants(team_id,user_id,capability,issued_by) values ('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','stats.publish','00000000-0000-4000-8000-000000000004')$$,
  '42501', null, 'direct capability tampering denied');
select throws_ok($$update public.delegation_envelopes set allowed_capabilities=array['stats.publish']$$,
  '42501', null, 'direct delegation expansion denied');
select throws_ok($$delete from public.roster_entries$$,
  '42501', null, 'direct roster deletion denied');
select throws_ok($$update public.roster_entry_revisions set display_name='SYNTHETIC FORGED HISTORY'$$,
  '42501', null, 'direct history rewriting denied');
select pg_temp.login(1);
insert into test_audit_result select count(*) from public.team_audit_events;
select public.team_save_roster('20000000-0000-4000-8000-000000000001','SYNTHETIC AUDITED PLAYER','9');
select is((select count(*) from public.team_audit_events), (select event_count+1 from test_audit_result),
  'successful public roster command appends exactly one audit event');
select throws_ok($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','stats.publish',true)$$,
  '42501', null, 'owner self-grant also denied');
select is((select count(*) from public.team_audit_events), (select event_count+1 from test_audit_result),
  'denied command leaves audit and mutations unchanged');
select throws_ok($$update public.team_audit_events set action='forged'$$,
  '42501', null, 'authenticated audit rewriting denied');
select throws_ok($$delete from public.team_audit_events$$,
  '42501', null, 'authenticated audit deletion denied');
reset role;
select throws_ok($$update public.teams set owner_auth_uuid='00000000-0000-4000-8000-000000000002'$$,
  '42501', null, 'owner UUID immutable even to ordinary trusted SQL updates');
select throws_ok($$delete from public.team_audit_events$$,
  '42501', null, 'audit append-only trigger protects trusted updates too');
delete from auth.sessions where user_id='00000000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.login(2);
select is((select count(*)::int from public.teams),0,'revoked server session denies table reads');
select throws_ok($$select public.team_access('20000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'revoked session denies commands');
reset role;
-- Identity confirmation and session constraints use the actual Auth tables.
update auth.users set email_confirmed_at=null where id='00000000-0000-4000-8000-000000000006';
set local role authenticated;
select pg_temp.login(6);
select throws_ok($$select public.team_request_membership('20000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'unverified account cannot request admission');
select pg_temp.login(1);
select set_config('request.jwt.claims', (current_setting('request.jwt.claims')::jsonb ||
  jsonb_build_object('is_anonymous',true,'user_metadata',jsonb_build_object('role','owner')))::text,true);
select throws_ok($$select public.team_access('20000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'anonymous session and writable owner metadata confer no access');
select pg_temp.login(1);
select set_config('request.jwt.claims', (current_setting('request.jwt.claims')::jsonb ||
  jsonb_build_object('exp',extract(epoch from now()-interval '1 second')))::text,true);
select throws_ok($$select public.team_access('20000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'expired JWT cannot read access');
reset role;
update auth.sessions set not_after=now()-interval '1 second' where user_id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.login(1);
select throws_ok($$select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000005','active')$$,
  '42501', null, 'expired server session cannot administer');
reset role;
set local role anon;
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select public.team_access('20000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'anonymous RPC denied');
select throws_ok($$select * from public.teams$$,
  '42501', null, 'anonymous table access denied');
select throws_ok(command,'42501',null,description) from (values
  ($$select public.team_request_membership('20000000-0000-4000-8000-000000000001')$$,'anonymous admission RPC denied'),
  ($$select public.team_set_membership('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','active')$$,'anonymous membership RPC denied'),
  ($$select public.team_set_capability('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','stats.publish',true)$$,'anonymous grant RPC denied'),
  ($$select public.team_delegate('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002',array['roster.manage'],now()+interval '1 hour')$$,'anonymous delegation RPC denied'),
  ($$select public.team_revoke_delegation('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001')$$,'anonymous delegation revocation RPC denied'),
  ($$select public.team_save_roster('20000000-0000-4000-8000-000000000001','SYNTHETIC PLAYER','8')$$,'anonymous roster save RPC denied'),
  ($$select public.team_archive_roster('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1)$$,'anonymous roster archive RPC denied')
) cases(command,description);
reset role;
select * from finish();
rollback;
