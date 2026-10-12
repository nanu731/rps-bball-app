-- Approved-recovery regression: authenticated current-version reopening must preserve unfinished work.
-- Distinct synthetic identities; every fixture and command effect rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,email_confirmed_at) select ('d7000001-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'synthetic-stat-edit-diagnosis-'||n||'@example.invalid',now() from generate_series(1,3) n;
insert into auth.sessions(id,user_id,not_after) select ('d7000002-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 ('d7000001-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now()+interval '1 day' from generate_series(1,3) n;
create function pg_temp.login(n int) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub','d7000001-0000-4000-8000-'||lpad(n::text,12,'0'),
 'session_id','d7000002-0000-4000-8000-'||lpad(n::text,12,'0'),'exp',extract(epoch from now()+interval '1 hour'),
 'role','authenticated','is_anonymous',false)::text,true); end $$;
create function pg_temp.team() returns uuid language sql as $$select 'd7000003-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.game() returns uuid language sql as $$select 'd7000004-0000-4000-8000-000000000001'::uuid$$;
create temp table results(name text primary key,body jsonb);
grant select,insert,update on results to authenticated;
create function pg_temp.keep(n text,b jsonb) returns jsonb language plpgsql as $$begin insert into results values(n,b) on conflict(name) do update set body=excluded.body; return b; end $$;
create function pg_temp.body(n text) returns jsonb language sql as $$select body from results where name=n$$;
create function pg_temp.id(n text) returns uuid language sql as $$select (body->>'id')::uuid from results where name=n$$;
create function pg_temp.rev(n text) returns bigint language sql as $$select (body->>'revision')::bigint from results where name=n$$;
create function pg_temp.records(touches int,answer boolean) returns jsonb language sql as $$select jsonb_build_array(jsonb_build_object(
 'id','d7000005-0000-4000-8000-000000000001','gameID',pg_temp.game(),'team','ours','number',1,'turnover',answer,
 'values',jsonb_build_object('paintTouches',touches,'offensiveRebounds',0,'twosMade',0,'twosMissed',0,'threesMade',0,'threesMissed',0,'freeThrowsMade',0,'freeThrowsMissed',0)))$$;
insert into public.teams(id,name,owner_auth_uuid) values(pg_temp.team(),'SYNTHETIC STAT EDIT DIAGNOSIS','d7000001-0000-4000-8000-000000000001');
insert into public.team_memberships(team_id,user_id,status) select pg_temp.team(),('d7000001-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'active' from generate_series(2,3) n;
insert into public.capability_grants(team_id,user_id,capability,issued_by) values
 (pg_temp.team(),'d7000001-0000-4000-8000-000000000003','stats.publish','d7000001-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.login(1);
select lives_ok($$select public.stats_create_game(pg_temp.team(),pg_temp.game(),'2026-10-11','SYNTHETIC OPPONENT','home','regularSeason')$$,'synthetic game creation');
select lives_ok($$select pg_temp.keep('v1',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'our_possessions'))$$,'owner opens initial dataset');
select lives_ok($$select pg_temp.keep('v1',public.stats_save_draft(pg_temp.team(),pg_temp.id('v1'),pg_temp.rev('v1'),pg_temp.records(1,false)))$$,'owner records initial valid possession');
select lives_ok($$select pg_temp.keep('v1',public.stats_complete(pg_temp.team(),pg_temp.id('v1'),pg_temp.rev('v1')))$$,'owner completes valid initial data');
select lives_ok($$select pg_temp.keep('v1',public.stats_publish(pg_temp.team(),pg_temp.id('v1'),pg_temp.rev('v1')))$$,'initial V1 published');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('a-request',public.stats_request_edit(pg_temp.team(),pg_temp.id('v1'),pg_temp.rev('v1'),'SYNTHETIC AUTHOR A CORRECTION'))$$,'A requests V1 edit');
select pg_temp.login(1);
select lives_ok($$select pg_temp.keep('a-approved',public.stats_review_edit(pg_temp.team(),pg_temp.id('a-request'),pg_temp.rev('a-request'),true))$$,'owner approves A revision from V1');
select pg_temp.keep('a-draft',pg_temp.body('a-approved')->'version');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('a-draft',public.stats_save_draft(pg_temp.team(),pg_temp.id('a-draft'),pg_temp.rev('a-draft'),pg_temp.records(9,null)))$$,'A saves incomplete draft with unanswered turnover');
select pg_temp.login(3);
select lives_ok($$select pg_temp.keep('b-request',public.stats_request_edit(pg_temp.team(),pg_temp.id('v1'),pg_temp.rev('v1'),'SYNTHETIC AUTHOR B CORRECTION'))$$,'B independently requests V1 edit');
select pg_temp.login(1);
select lives_ok($$select pg_temp.keep('b-approved',public.stats_review_edit(pg_temp.team(),pg_temp.id('b-request'),pg_temp.rev('b-request'),true))$$,'owner approves B concurrent revision');
select pg_temp.keep('v2',pg_temp.body('b-approved')->'version');
select pg_temp.login(3);
select lives_ok($$select pg_temp.keep('v2',public.stats_save_draft(pg_temp.team(),pg_temp.id('v2'),pg_temp.rev('v2'),pg_temp.records(2,false)))$$,'B saves valid correction');
select lives_ok($$select pg_temp.keep('v2',public.stats_complete(pg_temp.team(),pg_temp.id('v2'),pg_temp.rev('v2')))$$,'B completes correction');
select lives_ok($$select pg_temp.keep('v2',public.stats_publish(pg_temp.team(),pg_temp.id('v2'),pg_temp.rev('v2')))$$,'B publishes V2 while A draft remains unfinished');
select pg_temp.login(2);
select is(public.stats_open_draft(pg_temp.team(),pg_temp.game(),'our_possessions'),pg_temp.body('a-draft'),'ordinary open retains A stale unfinished draft');
select lives_ok($$select pg_temp.keep('a-current-request',public.stats_request_edit(pg_temp.team(),pg_temp.id('v2'),pg_temp.rev('v2'),'SYNTHETIC A CURRENT VERSION REQUEST'))$$,'A requests edit of current V2');
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('a-draft'),pg_temp.rev('a-draft'))$$,'22023',null,'unanswered source cannot be falsely completed just to free working slot');
select pg_temp.login(1);
select lives_ok($$select pg_temp.keep('a-current-approved',public.stats_review_edit(pg_temp.team(),pg_temp.id('a-current-request'),pg_temp.rev('a-current-request'),true))$$,'authorized current-version edit allows preserved unfinished work recovery');
select is((select published_version_id from public.stat_datasets where game_id=pg_temp.game() and dataset_type='our_possessions'),pg_temp.id('v2'),'latest accepted V2 remains unchanged');
select pg_temp.login(2);
select is((select records from public.stat_versions where id=pg_temp.id('a-draft')),pg_temp.records(9,null),'A saved missing value and draft data remain intact');
select is((select status from public.stat_edit_requests where id=pg_temp.id('a-current-request')),'approved','current-source request is approved');
select is((select status from public.stat_versions where id=pg_temp.id('a-draft')),'superseded','stale saved draft is explicitly superseded rather than completed');
select is((select covered_roster from public.stat_versions where id=pg_temp.id('a-draft')),'[]'::jsonb,'saved covered roster preserved exactly');
select is(pg_temp.body('a-current-approved')->'version'->'records',pg_temp.records(2,false),'approved working copy comes from authorized current V2 rather than stale draft');
select is(pg_temp.body('a-current-approved')->'version'->>'recovery_source_version_id',pg_temp.id('a-draft')::text,'approved draft identifies retained saved source');
select is(pg_temp.body('a-current-approved')->'version'->>'base_published_version_id',pg_temp.id('v2')::text,'approved working draft captures current accepted base');
select is((select count(*)::int from public.stat_versions where author_user_id='d7000001-0000-4000-8000-000000000002' and status='draft'),1,'one current author draft retained');
select pg_temp.login(1);
select is((select count(*)::int from public.stat_export_outbox where game_id=pg_temp.game()),2,'recovery creates no publication or export');
select pg_temp.login(2);
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('a-draft'),pg_temp.rev('a-draft')+1,pg_temp.records(7,false))$$,'42501',null,'retained saved draft is readonly');
select throws_ok($$select public.stats_request_edit(pg_temp.team(),pg_temp.id('a-draft'),pg_temp.rev('a-draft')+1,'SYNTHETIC INVALID COMPLETION')$$,'42501',null,'superseded draft cannot claim completed-source editing eligibility');
select lives_ok($$select pg_temp.keep('same-base-request',public.stats_request_edit(pg_temp.team(),pg_temp.id('v2'),pg_temp.rev('v2'),'SYNTHETIC SAME BASE REQUEST'))$$,'author can request current source again but existing current working data remains protected');
select pg_temp.login(1);
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('same-base-request'),pg_temp.rev('same-base-request'),true)$$,'40001',null,'same-base unfinished draft still rejects approval');
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('a-current-request'),1,true)$$,'40001',null,'approval cannot be replayed with stale request revision');
reset role;
select throws_ok($$update public.stat_versions set records='[]',revision=revision+1 where id=pg_temp.id('a-draft')$$,'42501',null,'superseded saved records immutable even through trusted update');
set local role authenticated;
select pg_temp.login(2);
select diag('Observed A saved-version state: '||(select status from public.stat_versions where id=pg_temp.id('a-draft')));
reset role;
insert into auth.users(id,email,email_confirmed_at) values('d7000001-0000-4000-8000-000000000004','synthetic-stat-edit-revoked-reviewer@example.invalid',now());
insert into auth.sessions(id,user_id,not_after) values('d7000002-0000-4000-8000-000000000004','d7000001-0000-4000-8000-000000000004',now()+interval '1 day');
insert into public.team_memberships(team_id,user_id,status) values(pg_temp.team(),'d7000001-0000-4000-8000-000000000004','active');
insert into public.capability_grants(team_id,user_id,capability,issued_by,revoked_at) values(pg_temp.team(),'d7000001-0000-4000-8000-000000000004','datasets.reopen','d7000001-0000-4000-8000-000000000001',now());
set local role authenticated;
select pg_temp.login(4);
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('same-base-request'),pg_temp.rev('same-base-request'),true)$$,'42501',null,'revoked dataset reviewer cannot approve recovery');
select pg_temp.login(2);
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('same-base-request'),pg_temp.rev('same-base-request'),true)$$,'42501',null,'ordinary author cannot bypass reopening approval');
reset role;
update auth.sessions set not_after=now()-interval '1 hour' where id='d7000002-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.login(2);
select is((select count(*)::int from public.stat_versions where author_user_id='d7000001-0000-4000-8000-000000000002'),0,'expired live session loses retained and current draft access');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),(pg_temp.body('a-current-approved')->'version'->>'id')::uuid,1,pg_temp.records(7,null))$$,'42501',null,'expired author cannot save recovered draft');
select * from finish();
rollback;
