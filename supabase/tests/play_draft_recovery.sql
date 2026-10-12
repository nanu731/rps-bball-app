-- Public recovery command with two authors; every synthetic change rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
select has_function('public','play_recover_draft',array['uuid','uuid','bigint','uuid'],'explicit recovery command exists');
insert into auth.users(id,email,email_confirmed_at) select ('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'synthetic-play-recovery-'||n||'@example.invalid',now() from generate_series(1,5) n;
insert into auth.sessions(id,user_id,not_after) select ('b2000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 ('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now()+interval '1 day' from generate_series(1,5) n;
create function pg_temp.login(n int) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub','b1000000-0000-4000-8000-'||lpad(n::text,12,'0'),
 'session_id','b2000000-0000-4000-8000-'||lpad(n::text,12,'0'),'exp',extract(epoch from now()+interval '1 hour'),
 'role','authenticated','is_anonymous',false)::text,true); end $$;
create function pg_temp.team() returns uuid language sql as $$select 'b3000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.play() returns uuid language sql as $$select 'b4000000-0000-4000-8000-000000000001'::uuid$$;
create temp table results(name text primary key,body jsonb);
grant select,insert,update on results to authenticated;
create function pg_temp.keep(n text,b jsonb) returns jsonb language plpgsql as $$begin insert into results values(n,b) on conflict(name) do update set body=excluded.body; return b; end $$;
create function pg_temp.body(n text) returns jsonb language sql as $$select body from results where name=n$$;
create function pg_temp.id(n text) returns uuid language sql as $$select (body->>'id')::uuid from results where name=n$$;
create function pg_temp.rev(n text) returns bigint language sql as $$select (body->>'revision')::bigint from results where name=n$$;
create function pg_temp.diagram(x numeric) returns jsonb language sql as $$select jsonb_build_object('markers',jsonb_build_array(jsonb_build_object(
 'id','b5000000-0000-4000-8000-000000000001','number',1,'label','','origin',jsonb_build_object('x',0.5,'y',0.5))),
 'steps',jsonb_build_array(jsonb_build_object('id','b6000000-0000-4000-8000-000000000001','duration',1,'positions',
 jsonb_build_array(jsonb_build_object('markerID','b5000000-0000-4000-8000-000000000001','point',jsonb_build_object('x',x,'y',0.2))))))$$;
insert into public.teams(id,name,owner_auth_uuid) values(pg_temp.team(),'SYNTHETIC RECOVERY TEAM','b1000000-0000-4000-8000-000000000001');
insert into public.team_memberships(team_id,user_id,status) select pg_temp.team(),('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'active' from generate_series(2,4) n;
insert into public.capability_grants(team_id,user_id,capability,issued_by) values
 (pg_temp.team(),'b1000000-0000-4000-8000-000000000002','plays.author','b1000000-0000-4000-8000-000000000001'),
 (pg_temp.team(),'b1000000-0000-4000-8000-000000000003','plays.author','b1000000-0000-4000-8000-000000000001'),
 (pg_temp.team(),'b1000000-0000-4000-8000-000000000003','plays.publish','b1000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.login(1);
select lives_ok($$select pg_temp.keep('base',public.play_open_draft(pg_temp.team(),pg_temp.play()))$$,'owner opens initial play');
select lives_ok($$select pg_temp.keep('base',public.play_save_draft(pg_temp.team(),pg_temp.id('base'),pg_temp.rev('base'),'SYNTHETIC ACCEPTED',pg_temp.diagram(0.6)))$$,'owner saves initial geometry');
select lives_ok($$select pg_temp.keep('base',public.play_transition(pg_temp.team(),pg_temp.id('base'),pg_temp.rev('base'),'publish'))$$,'owner publishes initial play');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('stale',public.play_open_draft(pg_temp.team(),pg_temp.play(),pg_temp.id('base')))$$,'author two opens successor');
select lives_ok($$select pg_temp.keep('stale',public.play_save_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale'),'SYNTHETIC AUTHOR SAVED',pg_temp.diagram(0.8)))$$,'author saves distinct geometry before concurrent publication');
select throws_ok($$select public.play_recover_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale'),pg_temp.id('base'))$$,'22023',null,'current-base draft does not need recovery');
select pg_temp.login(3);
select lives_ok($$select pg_temp.keep('latest',public.play_open_draft(pg_temp.team(),pg_temp.play(),pg_temp.id('base')))$$,'second author opens concurrent successor');
select lives_ok($$select pg_temp.keep('latest',public.play_save_draft(pg_temp.team(),pg_temp.id('latest'),pg_temp.rev('latest'),'SYNTHETIC NEW ACCEPTED',pg_temp.diagram(0.9)))$$,'second author saves different successor');
select lives_ok($$select pg_temp.keep('latest',public.play_transition(pg_temp.team(),pg_temp.id('latest'),pg_temp.rev('latest'),'publish'))$$,'second author publishes correction');
select pg_temp.login(2);
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale'),'UNSAVED',pg_temp.diagram(0.7))$$,'40001',null,'old author save correctly conflicts with new accepted base');
select is(public.play_open_draft(pg_temp.team(),pg_temp.play(),pg_temp.id('latest')),pg_temp.body('stale'),'ordinary opening never silently rebases the saved stale draft');
select throws_ok($$select public.play_recover_draft(pg_temp.team(),pg_temp.id('stale'),1,pg_temp.id('latest'))$$,'40001',null,'stale expected revision denied');
select throws_ok($$select public.play_recover_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale'),pg_temp.id('base'))$$,'40001',null,'stale expected accepted pointer denied');
select pg_temp.login(3);
select throws_ok($$select public.play_recover_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale'),pg_temp.id('latest'))$$,'42501',null,'another author cannot recover private saved geometry');
select pg_temp.login(5);
select throws_ok($$select public.play_recover_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale'),pg_temp.id('latest'))$$,'42501',null,'nonmember recovery denied');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('recovery',public.play_recover_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale'),pg_temp.id('latest')))$$,'explicit recovery atomically creates resumed draft');
select is(pg_temp.body('recovery')->'superseded'->>'status','superseded','old saved draft is explicitly superseded');
select is(pg_temp.body('recovery')->'superseded'->>'title','SYNTHETIC AUTHOR SAVED','old saved title retained');
select is(pg_temp.body('recovery')->'superseded'->'diagram',pg_temp.diagram(0.8),'old saved drawing retained unchanged');
select is(pg_temp.body('recovery')->'superseded'->>'base_published_version_id',pg_temp.id('base')::text,'old historical base retained');
select isnt(pg_temp.body('recovery')->'draft'->>'id',pg_temp.id('stale')::text,'resumed draft receives distinct identity');
select is(pg_temp.body('recovery')->'draft'->>'status','draft','resumed draft is editable but not accepted');
select is(pg_temp.body('recovery')->'draft'->>'title','SYNTHETIC AUTHOR SAVED','recovery copies author saved title rather than new accepted title');
select is(pg_temp.body('recovery')->'draft'->'diagram',pg_temp.diagram(0.8),'recovery copies author saved drawing rather than new accepted drawing');
select is(pg_temp.body('recovery')->'draft'->>'base_published_version_id',pg_temp.id('latest')::text,'resumed draft uses explicitly expected current accepted base');
select is(pg_temp.body('recovery')->'draft'->>'recovery_source_version_id',pg_temp.id('stale')::text,'resumed draft records retained saved source');
select is((select published_version_id from public.plays where id=pg_temp.play()),pg_temp.id('latest'),'recovery never changes accepted pointer');
select is((select diagram from public.play_versions where id=pg_temp.id('latest')),pg_temp.diagram(0.9),'accepted geometry remains unchanged');
select is((select count(*)::int from public.play_versions where play_id=pg_temp.play() and author_user_id='b1000000-0000-4000-8000-000000000002' and status='draft'),1,'one author working-draft invariant maintained');
select throws_ok($$select public.play_recover_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale'),pg_temp.id('latest'))$$,'42501',null,'retry of consumed stale identity cannot duplicate recovery');
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('stale'),pg_temp.rev('stale')+1,'CHANGED',pg_temp.diagram(0.7))$$,'42501',null,'superseded saved drawing remains readonly');
select lives_ok($$select pg_temp.keep('resumed',public.play_save_draft(pg_temp.team(),(pg_temp.body('recovery')->'draft'->>'id')::uuid,1,'SYNTHETIC EXPLICIT UNSAVED SAVE',pg_temp.diagram(0.7)))$$,'later explicit save can apply retained unsaved buffer against new base');
select is((select diagram from public.play_versions where id=pg_temp.id('stale')),pg_temp.diagram(0.8),'later new draft save leaves saved old geometry intact');
reset role;
select throws_ok($$update public.play_versions set title='CORRUPTED',revision=revision+1 where id=pg_temp.id('stale')$$,'42501',null,'superseded row immutable even to trusted raw update');
set local role authenticated;
select pg_temp.login(4);
select is((select count(*)::int from public.play_versions where status='superseded'),0,'ordinary viewer cannot inspect private retained saved drawing');
select pg_temp.login(1);
select ok((select count(*)=2 from public.team_audit_events where team_id=pg_temp.team() and action in ('play.draft.supersede','play.draft.recover')),'recovery and saved retention both audited');
select * from finish();
rollback;
