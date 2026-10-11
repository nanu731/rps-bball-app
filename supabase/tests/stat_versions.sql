-- Synthetic fixture identities; each run rolls back all changes.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
select has_function('public','stats_create_game',array['uuid','uuid','date','text','text','text'],
  'active member game creation is exposed through an authenticated command');

insert into auth.users(id,email,email_confirmed_at)
select ('91000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'stat-fixture-'||n||'@example.invalid',now()
from generate_series(1,10) n;
insert into auth.sessions(id,user_id,not_after)
select ('92000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('91000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case when n=9 then now()-interval '1 hour' else now()+interval '1 day' end
from generate_series(1,10) n;
create function pg_temp.login(n integer) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','91000000-0000-4000-8000-'||lpad(n::text,12,'0'),
    'session_id','92000000-0000-4000-8000-'||lpad(n::text,12,'0'),'role','authenticated','is_anonymous',false,
    'exp',extract(epoch from now()+interval '1 hour'))::text,true);
end $$;
create function pg_temp.team() returns uuid language sql as $$select '93000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.game() returns uuid language sql as $$select '94000000-0000-4000-8000-000000000001'::uuid$$;
create temporary table results(name text primary key,body jsonb);
grant select,insert,update on results to authenticated;
create function pg_temp.keep(n text,b jsonb) returns jsonb language plpgsql as $$
begin insert into results values(n,b) on conflict(name) do update set body=excluded.body; return b; end $$;
create function pg_temp.body(n text) returns jsonb language sql as $$select body from results where name=n$$;
create function pg_temp.id(n text) returns uuid language sql as $$select (body->>'id')::uuid from results where name=n$$;
create function pg_temp.rev(n text) returns bigint language sql as $$select (body->>'revision')::bigint from results where name=n$$;
create function pg_temp.roster() returns jsonb language sql as $$select '[{"id":"95000000-0000-4000-8000-000000000001","version":1}]'::jsonb$$;
create function pg_temp.box(v jsonb) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('gameID',pg_temp.game(),'playerID','95000000-0000-4000-8000-000000000001','values',v))
$$;
insert into public.teams(id,name,owner_auth_uuid) values(pg_temp.team(),'SYNTHETIC STATS TEST TEAM','91000000-0000-4000-8000-000000000001');
insert into public.team_memberships(team_id,user_id,status)
select pg_temp.team(),('91000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case when n=8 then 'removed' else 'active' end from generate_series(2,10) n where n<>7;
insert into public.roster_entries(id,team_id,display_name,jersey_number)
values('95000000-0000-4000-8000-000000000001',pg_temp.team(),'SYNTHETIC STAT PLAYER','90');
insert into public.capability_grants(team_id,user_id,capability,issued_by)
values(pg_temp.team(),'91000000-0000-4000-8000-000000000003','stats.review','91000000-0000-4000-8000-000000000001'),
(pg_temp.team(),'91000000-0000-4000-8000-000000000004','stats.publish','91000000-0000-4000-8000-000000000001'),
(pg_temp.team(),'91000000-0000-4000-8000-000000000005','datasets.reopen','91000000-0000-4000-8000-000000000001');
insert into public.teams(id,name,owner_auth_uuid) values('93000000-0000-4000-8000-000000000002','SYNTHETIC OTHER TEAM','91000000-0000-4000-8000-000000000001');
insert into public.roster_entries(id,team_id,display_name,jersey_number)
values('95000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000002','SYNTHETIC OTHER PLAYER','91');
set local role authenticated;
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('game',public.stats_create_game(pg_temp.team(),pg_temp.game(),'2026-10-10','SYNTHETIC OPPONENT','away','regularSeason'))$$,
 'active member creates four-field game');
select is(public.stats_create_game(pg_temp.team(),pg_temp.game(),'2026-10-10','SYNTHETIC OPPONENT','away','regularSeason'),pg_temp.body('game'),
 'stable game retry returns identical metadata');
select throws_ok($$select public.stats_create_game(pg_temp.team(),pg_temp.game(),'2026-10-10','CHANGED','away','regularSeason')$$,
 '40001',null,'same game identity cannot overwrite metadata');
select is((select count(*)::int from public.games),1,'game retries never duplicate rows');
select throws_ok($$insert into public.games(id,team_id,date,opponent,home_away,game_type,created_by)
 values(gen_random_uuid(),pg_temp.team(),'2026-10-10','SYNTHETIC','home','playoff','91000000-0000-4000-8000-000000000002')$$,
 '42501',null,'raw game write denied');
select lives_ok($$select pg_temp.keep('box',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'box_scores'))$$,'active member opens draft');
select is(public.stats_open_draft(pg_temp.team(),pg_temp.game(),'box_scores'),pg_temp.body('box'),'open retry preserves author draft UUID');
select is(pg_temp.body('box')->'records','[]'::jsonb,'opening a sheet creates no roster placeholders');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),
 jsonb_build_array(pg_temp.box('{}')->0 || '{"playerID":"95000000-0000-4000-8000-000000000002"}'),pg_temp.roster())$$,
 '22023',null,'another team roster identity is rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{}'),
 '[{"id":"95000000-0000-4000-8000-000000000001","version":99}]')$$,
 '22023',null,'invented roster history revision rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{}'),pg_temp.roster()||pg_temp.roster())$$,
 '22023',null,'duplicate covered roster identities rejected');
select lives_ok($$select pg_temp.keep('box',public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),
 pg_temp.box('{"points":4,"threesMade":7}'),pg_temp.roster()))$$,'proven scoring contradiction remains saveable draft');
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),true)$$,
 '22023',null,'completion rejects partial scoring lower-bound contradiction');
select is(pg_temp.body('box')->'records'->0->'values'->'points','4'::jsonb,'contradictory entered points stay visible');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),1,pg_temp.box('{}'),pg_temp.roster())$$,
 '40001',null,'stale save cannot replace newer draft');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{"points":-1}'),pg_temp.roster())$$,
 '22023',null,'negative counts rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{"points":1.5}'),pg_temp.roster())$$,
 '22023',null,'fractional counts rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{"points":9223372036854775808}'),pg_temp.roster())$$,
 '22023',null,'native integer overflow rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{"period":1}'),pg_temp.roster())$$,
 '22023',null,'unrequested collection field rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),
 jsonb_build_array(pg_temp.box('{}')->0 || '{"status":"published","author_user_id":"91000000-0000-4000-8000-000000000001"}'),pg_temp.roster())$$,
 '22023',null,'client approval and author metadata rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{}')||pg_temp.box('{}'),pg_temp.roster())$$,
 '22023',null,'duplicate game-player records rejected atomically');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),
 '[{"gameID":"94000000-0000-4000-8000-000000000002","playerID":"95000000-0000-4000-8000-000000000001","values":{}}]',pg_temp.roster())$$,
 '22023',null,'cross-game records rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),
 '[{"gameID":"94000000-0000-4000-8000-000000000001","playerID":"temporary-1","values":{}}]',pg_temp.roster())$$,
 '22023',null,'temporary player identities are never converted');
select lives_ok($$select pg_temp.keep('box',public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{"points":0,"assists":null}'),pg_temp.roster()))$$,
 'valid draft preserves explicit zero, null and absent counts');
select is(pg_temp.body('box')->'records'->0->'values','{"points":0,"assists":null}'::jsonb,'saving never manufactures missing counts');
select pg_temp.login(6);
select is((select count(*)::int from public.stat_versions),0,'another active member cannot read author draft');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{}'),pg_temp.roster())$$,
 '42501',null,'another author cannot edit draft');
select pg_temp.login(3);
select is((select count(*)::int from public.stat_versions),0,'stats reviewer cannot inspect unfinished author draft');
select pg_temp.login(2);
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'))$$,
 '22023',null,'box completion requires actual covered-roster confirmation');
select lives_ok($$select pg_temp.keep('box',public.stats_complete(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),true))$$,
 'box completion permits uncollected optional measurements');
select is(pg_temp.body('box')->'records'->0->'values','{"points":0,"assists":null}'::jsonb,'box completion does not replace missing with zeros');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),pg_temp.box('{}'),pg_temp.roster())$$,
 '42501',null,'completed dataset cannot be edited directly');
select throws_ok($$select public.stats_open_draft(pg_temp.team(),pg_temp.game(),'box_scores')$$,
 '42501',null,'opening again cannot bypass completed-data reopening approval');
select throws_ok($$select public.stats_publish(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'))$$,
 '42501',null,'ordinary author cannot self-publish completed data');
select pg_temp.login(3);
select is((select count(*)::int from public.stat_versions),0,'unsubmitted completed data remains author-private');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('box',public.stats_submit(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box')))$$,'author submits completed proposal');
select pg_temp.login(6);
select is((select count(*)::int from public.stat_versions),0,'viewer cannot read pending proposal');
select pg_temp.login(3);
select is((select count(*)::int from public.stat_versions),1,'relevant stats reviewer sees submitted full record');
select lives_ok($$select pg_temp.keep('box',public.stats_review(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),true,'Synthetic reviewed acceptance'))$$,
 'independent reviewer publishes accepted version');
select pg_temp.login(6);
select is((select count(*)::int from public.stat_versions where status='published'),1,'active member sees accepted data');
select is((select published_version_id from public.stat_datasets where dataset_type='box_scores'),pg_temp.id('box'),'dataset points at accepted version');
select throws_ok($$update public.stat_versions set records='[]' where id=pg_temp.id('box')$$,'42501',null,'raw accepted-data overwrite denied');
select pg_temp.login(1);
select is((select count(*)::int from public.stat_export_outbox),1,'publication enqueues one accepted version');
select is((select publication_generation from public.games where id=pg_temp.game()),1::bigint,'publication advances game generation exactly once');
select is((select count(*)::int from public.team_audit_events where action='stats.published'),1,'publication decision is audited atomically');
select is((select review_reason from public.stat_versions where id=pg_temp.id('box')),'Synthetic reviewed acceptance','review reason is retained');
select is((select access_revision from public.teams where id=pg_temp.team()),1::bigint,'statistics do not change administration revision');

-- Independent possession completion, deliberate zeros, per-user suppression.
create function pg_temp.pos(side text,vals jsonb,answer jsonb) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('id','96000000-0000-4000-8000-000000000001','gameID',pg_temp.game(),
    'team',side,'number',1,'values',vals,'turnover',answer))
$$;
select pg_temp.login(2);
select pg_temp.keep('ours',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'our_possessions'));
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),false,true)$$,
 '22023',null,'empty possession sheet is honest incomplete data');
select pg_temp.keep('ours',public.stats_save_draft(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),pg_temp.pos('ours','{}','null')));
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),false,true,true)$$,
 '22023',null,'unanswered historical turnover blocks new completion');
select is(public.stats_preferences(pg_temp.team())->>'suppress_numeric_warning','false','failed completion does not save suppression');
select is((select records->0->'turnover' from public.stat_versions where id=pg_temp.id('ours')),'null'::jsonb,'historical nil turnover stays unchanged');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),pg_temp.pos('opponent','{}','false'))$$,
 '22023',null,'wrong team rejected for independent possession sheet');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),pg_temp.pos('ours','{}','false')||pg_temp.pos('ours','{}','false'))$$,
 '22023',null,'duplicate possession IDs/numbers rejected');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),
 jsonb_build_array(pg_temp.pos('ours','{}','false')->0 || '{"number":2}'))$$,
 '22023',null,'independent sheet numbering starts at one');
select pg_temp.keep('ours',public.stats_save_draft(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),pg_temp.pos('ours','{"paintTouches":0,"twosMade":null}','false')));
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'))$$,
 '22023',null,'numeric blanks require deliberate zero confirmation');
select is((select records->0->'values' from public.stat_versions where id=pg_temp.id('ours')),'{"paintTouches":0,"twosMade":null}'::jsonb,
 'go-back equivalent leaves all numeric missingness and status intact');
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),false,false,true)$$,
 '22023',null,'suppression cannot be enabled without explicit confirmation');
select lives_ok($$select pg_temp.keep('ours',public.stats_complete(pg_temp.team(),pg_temp.id('ours'),pg_temp.rev('ours'),false,true,true))$$,
 'confirmed completion converts existing numeric blanks atomically');
select is(pg_temp.body('ours')->'records'->0->'values',
 '{"paintTouches":0,"offensiveRebounds":0,"twosMade":0,"twosMissed":0,"threesMade":0,"threesMissed":0,"freeThrowsMade":0,"freeThrowsMissed":0}'::jsonb,
 'all eight existing possession numeric fields become explicit zero');
select is(jsonb_array_length(pg_temp.body('ours')->'records'),1,'completion creates no unadded paired-cell placeholders');
select is(public.stats_preferences(pg_temp.team())->>'suppress_numeric_warning','true','confirmation persists suppression for this author');
select pg_temp.keep('opponent',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'opponent_possessions'));
select pg_temp.keep('opponent',public.stats_save_draft(pg_temp.team(),pg_temp.id('opponent'),pg_temp.rev('opponent'),pg_temp.pos('opponent','{}','true')));
select lives_ok($$select pg_temp.keep('opponent',public.stats_complete(pg_temp.team(),pg_temp.id('opponent'),pg_temp.rev('opponent')))$$,
 'same user later explicitly completes without repeating confirmed warning');
select pg_temp.login(6);
select is(public.stats_preferences(pg_temp.team())->>'suppress_numeric_warning','false','another user never inherits suppression');
select pg_temp.keep('viewer-pos',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'our_possessions'));
select pg_temp.keep('viewer-pos',public.stats_save_draft(pg_temp.team(),pg_temp.id('viewer-pos'),pg_temp.rev('viewer-pos'),pg_temp.pos('ours','{}','false')));
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('viewer-pos'),pg_temp.rev('viewer-pos'))$$,
 '22023',null,'another author still gets zero-confirmation requirement');
select throws_ok($$insert into public.stat_user_preferences(user_id,suppress_numeric_warning)
 values('91000000-0000-4000-8000-000000000006',true)$$,'42501',null,'raw preference write cannot bypass confirmation');
-- Player paint touches stay independent and optional, even for direct publishers.
select pg_temp.login(4);
select pg_temp.keep('paint',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'player_paint_touches'));
select pg_temp.keep('paint',public.stats_save_draft(pg_temp.team(),pg_temp.id('paint'),pg_temp.rev('paint'),
 '[{"gameID":"94000000-0000-4000-8000-000000000001","playerID":"95000000-0000-4000-8000-000000000001","total":null}]',pg_temp.roster()));
select lives_ok($$select pg_temp.keep('paint',public.stats_complete(pg_temp.team(),pg_temp.id('paint'),pg_temp.rev('paint'),true))$$,
 'paint completion preserves an explicitly uncollected optional total');
select lives_ok($$select pg_temp.keep('paint',public.stats_publish(pg_temp.team(),pg_temp.id('paint'),pg_temp.rev('paint')))$$,
 'stats.publish author may directly publish completed dataset');
select is(pg_temp.body('paint')->'records'->0->'total','null'::jsonb,'published paint total remains missing');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('paint'),pg_temp.rev('paint'),'[]',pg_temp.roster())$$,
 '42501',null,'publication capability never bypasses completed-data editing approval');
select throws_ok($$select public.stats_publish(pg_temp.team(),pg_temp.id('paint'),pg_temp.rev('paint')-1)$$,
 '40001',null,'old publish retry cannot enqueue duplicate work');
-- Approved edit requests keep acceptance visible and preserve competing drafts.
select pg_temp.login(2);
select pg_temp.keep('request',public.stats_request_edit(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),'Synthetic correction request'));
select is(public.stats_request_edit(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box'),'Synthetic correction request'),pg_temp.body('request'),
 'identical edit request retry returns one pending request');
select pg_temp.login(5);
select pg_temp.keep('selfrequest',public.stats_request_edit(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box')));
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('selfrequest'),pg_temp.rev('selfrequest'),true)$$,
 '42501',null,'datasets.reopen reviewer cannot approve own request');
select lives_ok($$select pg_temp.keep('approved',public.stats_review_edit(pg_temp.team(),pg_temp.id('request'),pg_temp.rev('request'),true,'Synthetic reopen review'))$$,
 'independent reopen reviewer creates copied working revision');
select pg_temp.keep('edit',pg_temp.body('approved')->'version');
select is(pg_temp.body('edit')->'records',pg_temp.body('box')->'records','reopen copies frozen authorized data without invention');
select is(pg_temp.body('edit')->>'author_user_id','91000000-0000-4000-8000-000000000002','approved draft belongs to requester');
select is((select published_version_id from public.stat_datasets where dataset_type='box_scores'),pg_temp.id('box'),
 'reopening keeps previous accepted pointer visible');
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('request'),1,true)$$,
 '40001',null,'stale edit approval cannot create another working revision');
select pg_temp.login(6);
select pg_temp.keep('viewer-request',public.stats_request_edit(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box')));
select pg_temp.login(5);
select pg_temp.keep('viewer-approved',public.stats_review_edit(pg_temp.team(),pg_temp.id('viewer-request'),pg_temp.rev('viewer-request'),true));
select pg_temp.keep('viewer-edit',pg_temp.body('viewer-approved')->'version');
select pg_temp.login(2);
select pg_temp.keep('secondrequest',public.stats_request_edit(pg_temp.team(),pg_temp.id('box'),pg_temp.rev('box')));
select pg_temp.login(5);
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('secondrequest'),pg_temp.rev('secondrequest'),true)$$,
 '40001',null,'approval never overwrites requester existing unfinished draft');
select lives_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('secondrequest'),pg_temp.rev('secondrequest'),false,'Already has a working draft')$$,
 'reviewer can decline conflicting request without changing working data');
select pg_temp.login(2);
select pg_temp.keep('edit',public.stats_save_draft(pg_temp.team(),pg_temp.id('edit'),pg_temp.rev('edit'),pg_temp.box('{"points":2,"twosMade":1,"threesMade":0,"freeThrowsMade":0}'),pg_temp.roster()));
select pg_temp.keep('edit',public.stats_complete(pg_temp.team(),pg_temp.id('edit'),pg_temp.rev('edit'),true));
select pg_temp.keep('edit',public.stats_submit(pg_temp.team(),pg_temp.id('edit'),pg_temp.rev('edit')));
select pg_temp.login(6);
select is((select records from public.stat_versions where id=pg_temp.id('box')),pg_temp.body('box')->'records',
 'accepted version remains immutable while correction awaits review');
select pg_temp.keep('viewer-edit',public.stats_complete(pg_temp.team(),pg_temp.id('viewer-edit'),pg_temp.rev('viewer-edit'),true));
select pg_temp.keep('viewer-edit',public.stats_submit(pg_temp.team(),pg_temp.id('viewer-edit'),pg_temp.rev('viewer-edit')));
select pg_temp.login(3);
select lives_ok($$select pg_temp.keep('edit',public.stats_review(pg_temp.team(),pg_temp.id('edit'),pg_temp.rev('edit'),true))$$,
 'review acceptance replaces only accepted pointer and queues correction');
select throws_ok($$select public.stats_review(pg_temp.team(),pg_temp.id('viewer-edit'),pg_temp.rev('viewer-edit'),true)$$,
 '40001',null,'proposal captured from older accepted base cannot overwrite newer acceptance');
select pg_temp.login(1);
select is((select published_version_id from public.stat_datasets where dataset_type='box_scores'),pg_temp.id('edit'),'new accepted correction is current');
select is((select count(*)::int from public.stat_export_outbox),3,'one outbox item per box, paint and accepted correction');
select is((select publication_generation from public.games where id=pg_temp.game()),3::bigint,'stale acceptance does not advance publication generation');
select is((select records from public.stat_versions where id=pg_temp.id('box')),pg_temp.body('box')->'records','previous accepted history is unchanged after correction');
select throws_ok($$update public.stat_export_outbox set publication_generation=99$$,'42501',null,'raw outbox generation tampering denied');
select has_function('public','stats_save_drafts',array['uuid','jsonb'],'paired editable datasets save through one atomic command');

-- Paired-sheet Save is a single transaction, including revisions and audit.
create function pg_temp.item(n text,records jsonb,rev bigint default null) returns jsonb language sql as $$
  select jsonb_build_object('version_id',pg_temp.id(n),'expected_revision',coalesce(rev,pg_temp.rev(n)),'records',records,'covered_roster','[]'::jsonb)
$$;
select pg_temp.login(6);
select pg_temp.keep('viewer-opponent',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'opponent_possessions'));
select throws_ok($$select public.stats_save_drafts(pg_temp.team(),jsonb_build_array(
 pg_temp.item('viewer-pos',pg_temp.pos('ours','{"paintTouches":7}','false')),
 pg_temp.item('viewer-opponent',pg_temp.pos('opponent','{}','false'),999)))$$,
 '40001',null,'stale second batch item rolls back first sheet save');
select is((select revision from public.stat_versions where id=pg_temp.id('viewer-pos')),pg_temp.rev('viewer-pos'),'failed batch preserves first draft revision');
select is((select records from public.stat_versions where id=pg_temp.id('viewer-pos')),pg_temp.body('viewer-pos')->'records','failed batch preserves first draft values');
select throws_ok($$select public.stats_save_drafts(pg_temp.team(),jsonb_build_array(
 pg_temp.item('viewer-pos',pg_temp.pos('ours','{}','false')),
 pg_temp.item('viewer-pos',pg_temp.pos('ours','{}','false'))))$$,
 '22023',null,'duplicate version items rejected before batch mutation');
select throws_ok($$select public.stats_save_drafts(pg_temp.team(),jsonb_build_array(
 pg_temp.item('viewer-pos',pg_temp.pos('ours','{}','false')) || '{"author_user_id":"91000000-0000-4000-8000-000000000001"}'))$$,
 '22023',null,'batch cannot accept client ownership metadata');
select throws_ok($$select public.stats_save_drafts(pg_temp.team(),jsonb_build_array(
 pg_temp.item('viewer-pos',pg_temp.pos('ours','{"paintTouches":7}','false')),
 pg_temp.item('viewer-opponent',pg_temp.pos('opponent','{"period":1}','false'))))$$,
 '22023',null,'invalid second batch item rolls back first sheet save');
select is((select revision from public.stat_versions where id=pg_temp.id('viewer-pos')),pg_temp.rev('viewer-pos'),'invalid batch also preserves first revision');
select lives_ok($$select pg_temp.keep('batch',public.stats_save_drafts(pg_temp.team(),jsonb_build_array(
 pg_temp.item('viewer-pos',pg_temp.pos('ours','{"paintTouches":0}','false')),
 pg_temp.item('viewer-opponent','[]'))))$$,
 'valid paired batch saves both independent datasets atomically');
select pg_temp.keep('viewer-pos',pg_temp.body('batch')->0);
select pg_temp.keep('viewer-opponent',pg_temp.body('batch')->1);
select is(pg_temp.body('viewer-pos')->'records'->0->'values','{"paintTouches":0}'::jsonb,'paired Save preserves zero and absent fields');
select is(jsonb_array_length(pg_temp.body('viewer-opponent')->'records'),0,'unadded opposing paired cells remain absent');
-- Reviewers cannot approve their own proposals; rejection stays frozen until reopening.
select pg_temp.login(3);
select pg_temp.keep('self-proposal',public.stats_open_draft(pg_temp.team(),pg_temp.game(),'our_possessions'));
select pg_temp.keep('self-proposal',public.stats_save_draft(pg_temp.team(),pg_temp.id('self-proposal'),pg_temp.rev('self-proposal'),pg_temp.pos('ours','{}','false')));
select pg_temp.keep('self-proposal',public.stats_complete(pg_temp.team(),pg_temp.id('self-proposal'),pg_temp.rev('self-proposal'),false,true));
select pg_temp.keep('self-proposal',public.stats_submit(pg_temp.team(),pg_temp.id('self-proposal'),pg_temp.rev('self-proposal')));
select throws_ok($$select public.stats_review(pg_temp.team(),pg_temp.id('self-proposal'),pg_temp.rev('self-proposal'),true)$$,
 '42501',null,'stats reviewer cannot approve own submission');
select pg_temp.login(1);
select pg_temp.keep('self-proposal',public.stats_review(pg_temp.team(),pg_temp.id('self-proposal'),pg_temp.rev('self-proposal'),false,'Synthetic rejected proposal'));
select pg_temp.login(3);
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('self-proposal'),pg_temp.rev('self-proposal'),pg_temp.pos('ours','{}','false'))$$,
 '42501',null,'rejected completed proposal cannot silently become mutable');
select pg_temp.keep('private-request',public.stats_request_edit(pg_temp.team(),pg_temp.id('self-proposal'),pg_temp.rev('self-proposal')));
select pg_temp.login(5);
select is((select count(*)::int from public.stat_versions where id=pg_temp.id('self-proposal')),1,
 'reopen reviewer may inspect frozen source while exact edit request is pending');
select pg_temp.keep('private-reopen',public.stats_review_edit(pg_temp.team(),pg_temp.id('private-request'),pg_temp.rev('private-request'),true));
select pg_temp.keep('private-draft',pg_temp.body('private-reopen')->'version');
select is((select count(*)::int from public.stat_versions where id=pg_temp.id('self-proposal')),0,
 'reopen reviewer loses private source access after completing requested review');
select pg_temp.login(3);
select lives_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('private-draft'),pg_temp.rev('private-draft'),pg_temp.pos('ours','{}','false'))$$,
 'approved request makes separate author working revision editable');
-- Count and coverage edge cases are validated without overwriting drafts.
select pg_temp.login(6);
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('viewer-pos'),pg_temp.rev('viewer-pos'),pg_temp.pos('ours','{"paintTouches":"3"}','false'))$$,
 '22023',null,'string counts rejected rather than silently parsed');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('viewer-pos'),pg_temp.rev('viewer-pos'),pg_temp.pos('ours','{}','"No"'))$$,
 '22023',null,'turnover requires Boolean or null');
select pg_temp.keep('viewer-pos',public.stats_save_draft(pg_temp.team(),pg_temp.id('viewer-pos'),pg_temp.rev('viewer-pos'),pg_temp.pos('ours','{"twosMade":9223372036854775807}','false')));
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('viewer-pos'),pg_temp.rev('viewer-pos'),false,true)$$,
 '22023',null,'derived scoring overflow blocks completion without deleting valid individual counts');
select is((select records->0->'values'->'twosMade' from public.stat_versions where id=pg_temp.id('viewer-pos')),'9223372036854775807'::jsonb,
 'overflow contradiction remains available to author for correction');
select lives_ok($$select pg_temp.keep('viewer-pos',public.stats_save_draft(pg_temp.team(),pg_temp.id('viewer-pos'),pg_temp.rev('viewer-pos'),
 (select jsonb_agg(jsonb_build_object('id',('97000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'gameID',pg_temp.game(),
 'team','ours','number',n,'values','{}'::jsonb,'turnover',false)) from generate_series(1,151) n)))$$,
 'server imposes no basketball possession count limit');
select is(jsonb_array_length(pg_temp.body('viewer-pos')->'records'),151,'all explicitly added possessions persist');

-- Verified immutable historical roster snapshots and owner exceptions.
select pg_temp.login(1);
select public.team_save_roster(pg_temp.team(),'SYNTHETIC RENAMED PLAYER','92',
 (select access_revision from public.teams where id=pg_temp.team()),'95000000-0000-4000-8000-000000000001',1);
select public.team_archive_roster(pg_temp.team(),'95000000-0000-4000-8000-000000000001',2,
 (select access_revision from public.teams where id=pg_temp.team()));
select is((select covered_roster from public.stat_versions where id=pg_temp.id('edit')),pg_temp.roster(),
 'accepted covered roster retains its actual historical revision after rename/archive');
select pg_temp.keep('owner-request',public.stats_request_edit(pg_temp.team(),pg_temp.id('edit'),pg_temp.rev('edit')));
select lives_ok($$select pg_temp.keep('owner-approved',public.stats_review_edit(pg_temp.team(),pg_temp.id('owner-request'),pg_temp.rev('owner-request'),true))$$,
 'owner retains authority to approve own edit request');
select pg_temp.keep('owner-edit',pg_temp.body('owner-approved')->'version');
select pg_temp.keep('owner-edit',public.stats_complete(pg_temp.team(),pg_temp.id('owner-edit'),pg_temp.rev('owner-edit'),true));
select pg_temp.keep('owner-edit',public.stats_submit(pg_temp.team(),pg_temp.id('owner-edit'),pg_temp.rev('owner-edit')));
select lives_ok($$select pg_temp.keep('owner-edit',public.stats_review(pg_temp.team(),pg_temp.id('owner-edit'),pg_temp.rev('owner-edit'),true))$$,
 'owner retains authority to accept own submitted revision');
select is((select publication_generation from public.games where id=pg_temp.game()),4::bigint,'owner acceptance advances same atomic publication generation');
select pg_temp.login(10);
select pg_temp.keep('newgame',public.stats_create_game(pg_temp.team(),'94000000-0000-4000-8000-000000000002','2026-10-09','SYNTHETIC SECOND OPPONENT','home','playoff'));
select pg_temp.keep('archive-box',public.stats_open_draft(pg_temp.team(),'94000000-0000-4000-8000-000000000002','box_scores'));
select pg_temp.keep('archive-box',public.stats_save_draft(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box'),
 '[{"gameID":"94000000-0000-4000-8000-000000000002","playerID":"95000000-0000-4000-8000-000000000001","values":{"points":3,"twosMade":1,"threesMade":0,"freeThrowsMade":0}}]',pg_temp.roster()));
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box'),true)$$,
 '22023',null,'exact all-makes scoring mismatch blocks completion');
select pg_temp.keep('archive-box',public.stats_save_draft(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box'),
 '[{"gameID":"94000000-0000-4000-8000-000000000002","playerID":"95000000-0000-4000-8000-000000000001","values":{}}]'));
select throws_ok($$select public.stats_complete(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box'),true)$$,
 '22023',null,'covered roster cannot be empty when player records exist');
select pg_temp.keep('archive-box',public.stats_save_draft(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box'),
 '[{"gameID":"94000000-0000-4000-8000-000000000002","playerID":"95000000-0000-4000-8000-000000000001","values":{}}]',pg_temp.roster()));
select lives_ok($$select pg_temp.keep('archive-box',public.stats_complete(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box'),true))$$,
 'real archived player may retain actual verified historical roster snapshot');
select pg_temp.keep('archive-request',public.stats_request_edit(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box')));
select pg_temp.login(5);
select is((select count(*)::int from public.stat_versions where id=pg_temp.id('archive-box')),1,'pending reopen reviewer can inspect unsubmitted completed source');
select pg_temp.login(1);
select public.team_set_capability(pg_temp.team(),'91000000-0000-4000-8000-000000000005','datasets.reopen',true,
 (select access_revision from public.teams where id=pg_temp.team()),clock_timestamp()+interval '1 hour');
reset role;
update public.capability_grants set expires_at=clock_timestamp()-interval '1 minute'
 where team_id=pg_temp.team() and user_id='91000000-0000-4000-8000-000000000005' and revoked_at is null;
set local role authenticated;
select pg_temp.login(5);
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('archive-request'),pg_temp.rev('archive-request'),true)$$,
 '42501',null,'expired reopen grant cannot approve pending request');
select is((select count(*)::int from public.stat_versions where id=pg_temp.id('archive-box')),0,'expired reopen grant loses requested private source visibility');
select throws_ok($$select public.stats_review_edit(pg_temp.team(),pg_temp.id('archive-request'),pg_temp.rev('archive-request'),false)$$,
 '42501',null,'expired reopen grant cannot decline pending request');
select pg_temp.login(10);
select pg_temp.keep('archive-box',public.stats_submit(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box')));
select pg_temp.login(1);
select public.team_set_capability(pg_temp.team(),'91000000-0000-4000-8000-000000000003','stats.review',true,
 (select access_revision from public.teams where id=pg_temp.team()),clock_timestamp()+interval '1 hour');
reset role;
update public.capability_grants set expires_at=clock_timestamp()-interval '1 minute'
 where team_id=pg_temp.team() and user_id='91000000-0000-4000-8000-000000000003' and revoked_at is null;
set local role authenticated;
select pg_temp.login(3);
select throws_ok($$select public.stats_review(pg_temp.team(),pg_temp.id('archive-box'),pg_temp.rev('archive-box'),true)$$,
 '42501',null,'expired stats review grant cannot accept pending data');
select pg_temp.login(1);
select public.team_set_capability(pg_temp.team(),'91000000-0000-4000-8000-000000000003','stats.review',true,
 (select access_revision from public.teams where id=pg_temp.team()));
-- Current access is rechecked for reads and all commands.
select pg_temp.login(7);
select is((select count(*)::int from public.games),0,'nonmember cannot read existing games');
select is((select count(*)::int from public.stat_versions),0,'nonmember cannot read published history');
select throws_ok($$select public.stats_open_draft(pg_temp.team(),pg_temp.game(),'box_scores')$$,'42501',null,'nonmember command denied');
select pg_temp.login(8);
select is((select count(*)::int from public.stat_versions),0,'removed member cannot read published history');
select pg_temp.login(9);
select is((select count(*)::int from public.games),0,'expired Auth session cannot read existing game');
select throws_ok($$select public.stats_request_edit(pg_temp.team(),pg_temp.id('edit'),pg_temp.rev('edit'))$$,'42501',null,'expired Auth session command denied');
select pg_temp.login(1);
select public.team_set_capability(pg_temp.team(),'91000000-0000-4000-8000-000000000003','stats.review',false,
 (select access_revision from public.teams where id=pg_temp.team()));
select pg_temp.login(3);
select throws_ok($$select public.stats_review(pg_temp.team(),pg_temp.id('viewer-edit'),pg_temp.rev('viewer-edit'),true)$$,
 '42501',null,'revoked review grant cannot accept already submitted work');
select is((select count(*)::int from public.stat_versions where id=pg_temp.id('viewer-edit')),0,'revoked review grant removes pending full-row visibility');
select pg_temp.login(1);
select public.team_set_membership(pg_temp.team(),'91000000-0000-4000-8000-000000000002','removed',
 (select access_revision from public.teams where id=pg_temp.team()));
select pg_temp.login(2);
select is((select count(*)::int from public.stat_versions),0,'removed author cannot read own private or accepted versions');
select throws_ok($$select public.stats_request_edit(pg_temp.team(),pg_temp.id('edit'),pg_temp.rev('edit'))$$,
 '42501',null,'removed author cannot reopen own former published data');
reset role;
delete from auth.sessions where id='92000000-0000-4000-8000-000000000006';
set local role authenticated;
select pg_temp.login(6);
select is((select count(*)::int from public.stat_versions),0,'revoked session cannot read own unfinished drafts or published history');
select throws_ok($$select public.stats_save_draft(pg_temp.team(),pg_temp.id('viewer-pos'),pg_temp.rev('viewer-pos'),'[]')$$,
 '42501',null,'revoked session cannot mutate own draft');
set local role anon;
select throws_ok($$select public.stats_open_draft(pg_temp.team(),pg_temp.game(),'box_scores')$$,'42501',null,'anonymous RPC execute denied');
select throws_ok($$select * from public.stat_versions$$,'42501',null,'anonymous protected-table select denied');
reset role;
select * from finish();
rollback;
