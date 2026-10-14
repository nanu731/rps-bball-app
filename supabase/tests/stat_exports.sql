-- Synthetic public-command/RLS fixtures; every record is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
select has_function('public','stats_export_reserve',array['uuid'],'trusted worker reserves a stable accepted export');
insert into auth.users(id,email,email_confirmed_at)
select ('a1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'export-fixture-'||n||'@example.invalid',now()
from generate_series(1,2) n;
insert into auth.sessions(id,user_id,not_after)
select ('a2000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('a1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now()+interval '1 day'
from generate_series(1,2) n;
insert into auth.sessions(id,user_id,not_after) values('a2000000-0000-4000-8000-000000000003',
 'a1000000-0000-4000-8000-000000000001',now()-interval '1 day');
create function pg_temp.team() returns uuid language sql as $$select 'a3000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.game() returns uuid language sql as $$select 'a4000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.login(n integer,session_n integer default null) returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub','a1000000-0000-4000-8000-'||lpad(n::text,12,'0'),
 'session_id','a2000000-0000-4000-8000-'||lpad(coalesce(session_n,n)::text,12,'0'),'role','authenticated',
 'is_anonymous',false,'exp',extract(epoch from now()+interval '1 hour'))::text,true);
end $$;
create temporary table results(name text primary key,body jsonb);
grant select,insert,update on results to authenticated,service_role;
create function pg_temp.keep(n text,b jsonb) returns jsonb language plpgsql as $$
begin insert into results values(n,b) on conflict(name) do update set body=excluded.body; return b; end $$;
create function pg_temp.body(n text) returns jsonb language sql as $$select body from results where name=n$$;
create function pg_temp.id(n text) returns uuid language sql as $$select (body->>'id')::uuid from results where name=n$$;
create function pg_temp.rev(n text) returns bigint language sql as $$select (body->>'revision')::bigint from results where name=n$$;
create function pg_temp.job(n text) returns uuid language sql as $$select (body->>'job_id')::uuid from results where name=n$$;
create function pg_temp.receipt(n text) returns jsonb language sql as $$
 select body - array['job_id','payload_text','ledger_sheet_id','state'] from results where name=n
$$;
create function pg_temp.roster() returns jsonb language sql as $$select '[{"id":"a5000000-0000-4000-8000-000000000001","version":1}]'::jsonb$$;
create function pg_temp.box(v jsonb) returns jsonb language sql as $$
 select jsonb_build_array(jsonb_build_object('gameID',pg_temp.game(),'playerID','a5000000-0000-4000-8000-000000000001','values',v))
$$;
insert into public.teams(id,name,owner_auth_uuid) values(pg_temp.team(),'SYNTHETIC EXPORT TEAM','a1000000-0000-4000-8000-000000000001');
insert into public.team_memberships(team_id,user_id,status) values(pg_temp.team(),'a1000000-0000-4000-8000-000000000002','active');
insert into public.roster_entries(id,team_id,display_name,jersey_number)
 values('a5000000-0000-4000-8000-000000000001',pg_temp.team(),'=SYNTHETIC historical player','90');
insert into public.teams(id,name,owner_auth_uuid) values('a3000000-0000-4000-8000-000000000002','SYNTHETIC OTHER EXPORT TEAM','a1000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.login(1);
select public.stats_create_game(pg_temp.team(),pg_temp.game(),'2026-10-10','=SYNTHETIC opponent','away','regularSeason');
select pg_temp.keep('first',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'box_scores'));
select is(jsonb_array_length(public.stats_export_status(pg_temp.team())),0,'unfinished draft produces no export');
select pg_temp.keep('first',public.stats_save_draft(pg_temp.team(),pg_temp.id('first'),pg_temp.rev('first'),
 pg_temp.box('{"points":null,"assists":0}'),pg_temp.roster()));
select pg_temp.keep('first',public.stats_complete(pg_temp.team(),pg_temp.id('first'),pg_temp.rev('first'),true));
select is(jsonb_array_length(public.stats_export_status(pg_temp.team())),0,'completion alone produces no export');
select lives_ok($$select pg_temp.keep('first',public.stats_publish(pg_temp.team(),pg_temp.id('first'),pg_temp.rev('first')))$$,
 'publication queues atomically without a configured Google destination');
select pg_temp.keep('first-status',public.stats_export_status(pg_temp.team())->0);
select is(pg_temp.body('first-status')->>'state','queued','owner sees truthful queued status');
select is(jsonb_array_length(public.stats_export_latest(pg_temp.team())),1,'latest projection includes accepted dataset');
select throws_ok($$select public.stats_export_reserve(pg_temp.job('first-status'))$$,'42501',null,'mobile cannot reserve export jobs');
select throws_ok($$select public.stats_export_jobs(3)$$,'42501',null,'mobile cannot fetch export payloads');
select throws_ok($$select public.stats_export_configure(pg_temp.team(),'SYNTHETIC',0,100,101,3)$$,'42501',null,'mobile cannot configure destination');
select throws_ok($$select public.stats_export_finish(pg_temp.job('first-status'),'{}')$$,'42501',null,'mobile cannot fake an acknowledgement');
select throws_ok($$select public.stats_export_fail(pg_temp.job('first-status'),'provider_timeout')$$,'42501',null,'mobile cannot alter delivery status');
select throws_ok($$select * from public.stat_export_snapshots$$,'42501',null,'mobile cannot read trusted export payload table');
select throws_ok($$select spreadsheet_id from public.stat_export_deliveries$$,'42501',null,'mobile cannot read trusted destination column');
select throws_ok($$update public.stat_export_deliveries set state='delivered'$$,'42501',null,'mobile cannot bypass worker receipt');
set local role service_role;
select throws_ok($$select public.stats_export_reserve(pg_temp.job('first-status'))$$,'55000',null,'unconfigured job stays safely pending');
select throws_ok($$select public.stats_export_configure(pg_temp.team(),'SYNTHETIC_EXPORT_DESTINATION',100,100,101,3)$$,
 '22023',null,'ledger and snapshot ranges cannot overlap');
select lives_ok($$select public.stats_export_configure(pg_temp.team(),'SYNTHETIC_EXPORT_DESTINATION',0,100,101,3)$$,'trusted configuration binds destination');
select lives_ok($$select public.stats_export_configure(pg_temp.team(),'SYNTHETIC_EXPORT_DESTINATION',0,100,101,3)$$,'same trusted configuration retries safely');
select throws_ok($$select public.stats_export_configure(pg_temp.team(),'DIFFERENT_DESTINATION',0,100,101,3)$$,
 'PT409',null,'destination cannot be silently rebound');
select throws_ok($$select public.stats_export_configure('a3000000-0000-4000-8000-000000000002','SYNTHETIC_EXPORT_DESTINATION',0,100,101,3)$$,
 '23505',null,'one destination cannot allocate overlapping ranges for a second team');
select pg_temp.keep('r1',public.stats_export_reserve(pg_temp.job('first-status')));
select is((pg_temp.body('r1')->>'sheet_id')::integer,100,'first persistent snapshot gets first reserved ID');
select is((pg_temp.body('r1')->>'ledger_row')::integer,1,'first snapshot reserves row after header');
select is(public.stats_export_reserve(pg_temp.job('r1')),pg_temp.body('r1'),'retry retains exact identity/hash/destination/reservation');
select is(pg_temp.body('r1')->'payload_text' is not null,true,'trusted command supplies immutable payload');
select is((pg_temp.body('r1')->>'payload_text')::jsonb->'records'->0->'values'->'points','null'::jsonb,'missing count stays missing');
select is((pg_temp.body('r1')->>'payload_text')::jsonb->'records'->0->'values'->'assists','0'::jsonb,'explicit zero stays zero');
select throws_ok($$select public.stats_export_jobs(11)$$,'22023',null,'worker cannot fetch an unbounded batch');
select throws_ok($$select public.stats_export_finish(pg_temp.job('r1'),pg_temp.receipt('r1')||'{"payload_sha256":"wrong"}')$$,
 '22023',null,'wrong hash receipt cannot acknowledge delivery');
select throws_ok($$select public.stats_export_finish(pg_temp.job('r1'),pg_temp.receipt('r1')||'{"accepted_version_id":"a6000000-0000-4000-8000-000000000001"}')$$,
 '22023',null,'different accepted UUID cannot acknowledge delivery');
select throws_ok($$select public.stats_export_finish(pg_temp.job('r1'),pg_temp.receipt('r1')||'{"sheet_id":101}')$$,
 '22023',null,'wrong reserved range cannot acknowledge delivery');
select throws_ok($$select public.stats_export_fail(pg_temp.job('r1'),'Bearer SECRET')$$,'22023',null,'arbitrary error text cannot leak credentials');
select public.stats_export_fail(pg_temp.job('r1'),'provider_timeout');
set local role authenticated;
select pg_temp.login(1);
select is(public.stats_export_status(pg_temp.team())->0->>'state','failed','owner sees retryable provider failure');
select is(public.stats_export_status(pg_temp.team())->0->>'error_code','provider_timeout','owner sees sanitized failure code');
select public.team_save_roster(pg_temp.team(),'SYNTHETIC new label','91',
 (select access_revision from public.teams where id=pg_temp.team()),'a5000000-0000-4000-8000-000000000001',1);
select pg_temp.keep('request',public.stats_request_edit(pg_temp.team(),pg_temp.id('first'),pg_temp.rev('first')));
select pg_temp.keep('review',public.stats_review_edit(pg_temp.team(),pg_temp.id('request'),pg_temp.rev('request'),true));
select pg_temp.keep('second',pg_temp.body('review')->'version');
select pg_temp.keep('second',public.stats_save_draft(pg_temp.team(),pg_temp.id('second'),pg_temp.rev('second'),pg_temp.box('{"points":0}'),pg_temp.roster()));
select pg_temp.keep('second',public.stats_complete(pg_temp.team(),pg_temp.id('second'),pg_temp.rev('second'),true));
select pg_temp.keep('second',public.stats_publish(pg_temp.team(),pg_temp.id('second'),pg_temp.rev('second')));
select pg_temp.keep('second-status',public.stats_export_status(pg_temp.team())->1);
set local role service_role;
select pg_temp.keep('r2',public.stats_export_reserve(pg_temp.job('second-status')));
select is((pg_temp.body('r2')->>'sheet_id')::integer,101,'correction receives a distinct persisted snapshot ID');
select is((pg_temp.body('r2')->>'ledger_row')::integer,2,'correction receives a nonoverlapping ledger row');
select is((pg_temp.body('r2')->>'payload_text')::jsonb->'roster'->0->>'display_name','=SYNTHETIC historical player',
 'snapshot exports referenced historical roster label after current rename');
select isnt(pg_temp.body('r2')->>'payload_sha256',pg_temp.body('r1')->>'payload_sha256','accepted corrections bind a different payload hash');
select lives_ok($$select public.stats_export_finish(pg_temp.job('r2'),pg_temp.receipt('r2'))$$,'verified newer receipt records delivery');
select lives_ok($$select public.stats_export_finish(pg_temp.job('r1'),pg_temp.receipt('r1'))$$,'delayed older verified receipt remains valid');
select lives_ok($$select public.stats_export_finish(pg_temp.job('r1'),pg_temp.receipt('r1'))$$,'duplicate verified acknowledgement is idempotent');
select public.stats_export_fail(pg_temp.job('r1'),'provider_timeout');
set local role authenticated;
select pg_temp.login(1);
select is(public.stats_export_latest(pg_temp.team())->0->>'accepted_version_id',pg_temp.body('second')->>'id',
 'older retry never reverts fixed latest accepted projection');
select is(public.stats_export_latest(pg_temp.team())->0->>'publication_generation','2','latest chooses maximal game/dataset generation');
select is(public.stats_export_status(pg_temp.team())->0->>'state','delivered','late older failure cannot undo confirmed delivery');
select pg_temp.keep('third',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'our_possessions'));
select pg_temp.keep('third',public.stats_save_draft(pg_temp.team(),pg_temp.id('third'),pg_temp.rev('third'),
 '[{"id":"a6000000-0000-4000-8000-000000000001","gameID":"a4000000-0000-4000-8000-000000000001","team":"ours","number":1,"turnover":false,"values":{}}]'));
select pg_temp.keep('third',public.stats_complete(pg_temp.team(),pg_temp.id('third'),pg_temp.rev('third'),false,true));
select pg_temp.keep('third',public.stats_publish(pg_temp.team(),pg_temp.id('third'),pg_temp.rev('third')));
select pg_temp.keep('third-status',public.stats_export_status(pg_temp.team())->2);
select is(jsonb_array_length(public.stats_export_latest(pg_temp.team())),2,'latest projection is independently per dataset');
set local role service_role;
select throws_ok($$select public.stats_export_reserve(pg_temp.job('third-status'))$$,'54000',null,'bounded allocation refuses exhaustion instead of reuse');
set local role authenticated;
select pg_temp.login(2);
select throws_ok($$select public.stats_export_status(pg_temp.team())$$,'42501',null,'active nonowner cannot see delivery status');
select throws_ok($$select public.stats_export_latest(pg_temp.team())$$,'42501',null,'active nonowner cannot fetch trusted latest export status');
select is((select count(*)::integer from public.stat_export_deliveries),0,'delivery status RLS hides owner data from members');
select pg_temp.keep('pending',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'opponent_possessions'));
select pg_temp.keep('pending',public.stats_save_draft(pg_temp.team(),pg_temp.id('pending'),pg_temp.rev('pending'),
 '[{"id":"a6000000-0000-4000-8000-000000000002","gameID":"a4000000-0000-4000-8000-000000000001","team":"opponent","number":1,"turnover":false,"values":{}}]'));
select pg_temp.keep('pending',public.stats_complete(pg_temp.team(),pg_temp.id('pending'),pg_temp.rev('pending'),false,true));
select pg_temp.keep('pending',public.stats_submit(pg_temp.team(),pg_temp.id('pending'),pg_temp.rev('pending')));
select pg_temp.login(1);
select is(jsonb_array_length(public.stats_export_status(pg_temp.team())),3,'submitted proposal never exports before acceptance');
select pg_temp.login(1,3);
select throws_ok($$select public.stats_export_status(pg_temp.team())$$,'42501',null,'expired owner session cannot read status');
select is((select count(*)::integer from public.stat_export_deliveries),0,'expired owner session denied delivery RLS');
set local role anon;
select throws_ok($$select public.stats_export_jobs(1)$$,'42501',null,'anonymous worker RPC denied');
select throws_ok($$select public.stats_export_status(pg_temp.team())$$,'42501',null,'anonymous owner-status RPC denied');
reset role;
select throws_ok($$update public.stat_export_snapshots set payload_text='{}' where job_id=pg_temp.job('r1')$$,
 '42501',null,'accepted export snapshot remains append-only even for direct trusted mutation');
select * from finish();
rollback;
