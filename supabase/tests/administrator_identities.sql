-- Isolated synthetic fixtures; all setup and mutations roll back.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();
insert into auth.users(id,email,email_confirmed_at,phone,phone_confirmed_at,raw_user_meta_data)
select ('72000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'identity-'||n||'@example.invalid', case when n not in (3,5) then now() end,
  case when n=3 then '+15555550103' end, case when n=3 then now() end,
  '{"email":"spoof@example.invalid","phone":"+15555550999","role":"owner"}'::jsonb
from generate_series(1,7) n;
insert into auth.sessions(id,user_id,not_after)
select ('73000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('72000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid, now()+interval '1 day'
from generate_series(1,7) n;
create function pg_temp.identity_login(n integer) returns void language plpgsql as $$
begin
perform set_config('request.jwt.claims',jsonb_build_object('sub','72000000-0000-4000-8000-'||lpad(n::text,12,'0'),
  'session_id','73000000-0000-4000-8000-'||lpad(n::text,12,'0'),'role','authenticated',
  'is_anonymous',false,'exp',extract(epoch from now()+interval '1 hour'))::text,true);
end $$;
insert into public.teams(id,name,owner_auth_uuid) values
('74000000-0000-4000-8000-000000000001','SYNTHETIC IDENTITY TEAM','72000000-0000-4000-8000-000000000001'),
('74000000-0000-4000-8000-000000000002','SYNTHETIC OTHER TEAM','72000000-0000-4000-8000-000000000007');
insert into public.team_memberships(team_id,user_id,status)
select '74000000-0000-4000-8000-000000000001', ('72000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
case when n=5 then 'pending' when n=6 then 'removed' else 'active' end from generate_series(2,6) n;
insert into public.capability_grants(team_id,user_id,capability,issued_by)
values ('74000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000002','members.manage','72000000-0000-4000-8000-000000000001');
insert into public.delegation_envelopes(team_id,delegate_user_id,allowed_capabilities,expires_at,issued_by)
values ('74000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000003',array['roster.manage'],now()+interval '1 day','72000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.identity_login(1);
select is((select count(*)::int from public.team_administrator_identities('74000000-0000-4000-8000-000000000001')),6,'owner identifies existing same-team memberships only');
select is((select email from public.team_administrator_identities('74000000-0000-4000-8000-000000000001') where user_id='72000000-0000-4000-8000-000000000002'),'identity-2@example.invalid','confirmed email comes from trusted Auth');
select is((select phone from public.team_administrator_identities('74000000-0000-4000-8000-000000000001') where user_id='72000000-0000-4000-8000-000000000003'),'+15555550103','confirmed phone is returned independently');
select is((select email from public.team_administrator_identities('74000000-0000-4000-8000-000000000001') where user_id='72000000-0000-4000-8000-000000000003'),null::text,'unconfirmed email remains missing even with confirmed phone');
select is((select email from public.team_administrator_identities('74000000-0000-4000-8000-000000000001') where user_id='72000000-0000-4000-8000-000000000005'),null::text,'unverified Auth and spoofed metadata do not manufacture a contact');
select is((select count(*)::int from public.team_administrator_identities('74000000-0000-4000-8000-000000000001') where user_id='72000000-0000-4000-8000-000000000007'),0,'nonmember Auth account is never exposed');
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000002')$$,'42501',null,'owner of one team cannot identify another team');
select pg_temp.identity_login(2);
select is((select count(*)::int from public.team_administrator_identities('74000000-0000-4000-8000-000000000001')),6,'membership administrator may identify team members');
select pg_temp.identity_login(3);
select is((select count(*)::int from public.team_administrator_identities('74000000-0000-4000-8000-000000000001')),6,'active bounded delegate may identify grant targets');
select pg_temp.identity_login(4);
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'ordinary member with spoofed owner metadata cannot identify contacts');
select pg_temp.identity_login(5);
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'unverified pending account denied');
select pg_temp.identity_login(6);
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'removed verified account denied');
reset role;
update public.delegation_envelopes set expires_at=now()-interval '1 second' where team_id='74000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.identity_login(3);
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'expired delegate loses contact access');
reset role;
update public.delegation_envelopes set expires_at=now()+interval '1 day' where team_id='74000000-0000-4000-8000-000000000001';
update auth.users set banned_until=now()+interval '1 day' where id='72000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.identity_login(1);
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'banned owner cannot identify contacts');
reset role;
update auth.users set banned_until=null where id='72000000-0000-4000-8000-000000000001';
update auth.users set is_anonymous=true where id='72000000-0000-4000-8000-000000000004';
set local role authenticated;
select pg_temp.identity_login(1);
select is((select email from public.team_administrator_identities('74000000-0000-4000-8000-000000000001') where user_id='72000000-0000-4000-8000-000000000004'),null::text,'anonymous subject has UUID fallback even with confirmation timestamp');
reset role;
update auth.users set deleted_at=now() where id='72000000-0000-4000-8000-000000000005';
set local role authenticated;
select pg_temp.identity_login(1);
select is((select phone from public.team_administrator_identities('74000000-0000-4000-8000-000000000001') where user_id='72000000-0000-4000-8000-000000000005'),null::text,'deleted subject does not expose a contact');
reset role;
update public.capability_grants set revoked_at=now() where team_id='74000000-0000-4000-8000-000000000001';
update public.delegation_envelopes set revoked_at=now() where team_id='74000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.identity_login(2);
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'revoked membership authority loses contact access immediately');
select pg_temp.identity_login(3);
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'revoked delegate loses contact access immediately');
reset role;
delete from auth.sessions where id='73000000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.identity_login(1);
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'removed owner session cannot identify contacts');
reset role;
set local role anon;
select throws_ok($$select public.team_administrator_identities('74000000-0000-4000-8000-000000000001')$$,'42501',null,'anonymous role cannot execute lookup');
reset role;
select * from finish();
rollback;
