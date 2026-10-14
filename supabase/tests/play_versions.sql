-- Synthetic fixtures only; changes roll back, leaving other runtime records intact.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,email_confirmed_at) select ('a1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 'synthetic-play-'||n||'@example.invalid',now() from generate_series(1,7) n;
insert into auth.sessions(id,user_id,not_after) select ('a2000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 ('a1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now()+interval '1 day' from generate_series(1,7) n;
create function pg_temp.login(n int) returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub','a1000000-0000-4000-8000-'||lpad(n::text,12,'0'),
 'session_id','a2000000-0000-4000-8000-'||lpad(n::text,12,'0'),'exp',extract(epoch from now()+interval '1 hour'),
 'role','authenticated','is_anonymous',false)::text,true); end $$;
create function pg_temp.team() returns uuid language sql as $$select 'a3000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.play() returns uuid language sql as $$select 'a4000000-0000-4000-8000-000000000001'::uuid$$;
create temp table results(name text primary key,body jsonb);
grant select,insert,update on results to authenticated;
create function pg_temp.keep(n text,b jsonb) returns jsonb language plpgsql as $$begin insert into results values(n,b) on conflict(name) do update set body=excluded.body; return b; end $$;
create function pg_temp.body(n text) returns jsonb language sql as $$select body from results where name=n$$;
create function pg_temp.id(n text) returns uuid language sql as $$select (body->>'id')::uuid from results where name=n$$;
create function pg_temp.rev(n text) returns bigint language sql as $$select (body->>'revision')::bigint from results where name=n$$;
create function pg_temp.diagram() returns jsonb language sql as $$select '{"markers":[{"id":"a5000000-0000-4000-8000-000000000001","number":1,"label":"","origin":{"x":0.5,"y":0.5}}],"steps":[{"id":"a6000000-0000-4000-8000-000000000001","duration":1,"positions":[{"markerID":"a5000000-0000-4000-8000-000000000001","point":{"x":0.8,"y":0.2}}]}]}'::jsonb$$;
insert into public.teams(id,name,owner_auth_uuid) values(pg_temp.team(),'SYNTHETIC PLAY TEAM','a1000000-0000-4000-8000-000000000001');
insert into public.team_memberships(team_id,user_id,status) select pg_temp.team(),('a1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case when n=7 then 'removed' else 'active' end from generate_series(2,7) n where n<>6;
insert into public.capability_grants(team_id,user_id,capability,issued_by) values
 (pg_temp.team(),'a1000000-0000-4000-8000-000000000002','plays.author','a1000000-0000-4000-8000-000000000001'),
 (pg_temp.team(),'a1000000-0000-4000-8000-000000000002','plays.review','a1000000-0000-4000-8000-000000000001'),
 (pg_temp.team(),'a1000000-0000-4000-8000-000000000003','plays.review','a1000000-0000-4000-8000-000000000001'),
 (pg_temp.team(),'a1000000-0000-4000-8000-000000000004','plays.author','a1000000-0000-4000-8000-000000000001'),
 (pg_temp.team(),'a1000000-0000-4000-8000-000000000004','plays.publish','a1000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.login(5);
select throws_ok($$select public.play_open_draft(pg_temp.team(),pg_temp.play())$$,'42501',null,'ordinary member cannot author without grant');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('draft',public.play_open_draft(pg_temp.team(),pg_temp.play()))$$,'authorized author opens empty stable play draft');
select is(public.play_open_draft(pg_temp.team(),pg_temp.play()),pg_temp.body('draft'),'draft opening retry preserves identity');
select is(pg_temp.body('draft')->'diagram','{"markers":[],"steps":[]}'::jsonb,'no invented play or roster content');
select throws_ok($$insert into public.play_versions(team_id,play_id,author_user_id) values(pg_temp.team(),pg_temp.play(),'a1000000-0000-4000-8000-000000000002')$$,'42501',null,'direct protected write denied');
select throws_ok($$select public.play_transition(pg_temp.team(),pg_temp.id('draft'),1,'submit')$$,'22023',null,'empty draft cannot be submitted');
select lives_ok($$select pg_temp.keep('draft',public.play_save_draft(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'SYNTHETIC PLAY',pg_temp.diagram()))$$,'valid geometry saved');
select is(pg_temp.body('draft')->'diagram',pg_temp.diagram(),'stored diagram preserves stable markers and authored steps');
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('draft'),1,'STALE',pg_temp.diagram())$$,'PT409',null,'stale revision rejected');
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'BAD',jsonb_set(pg_temp.diagram(),'{markers,0,origin,x}','1.1'))$$,'22023',null,'out-of-court geometry rejected');
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'BAD',jsonb_set(pg_temp.diagram(),'{steps,0,duration}','0'))$$,'22023',null,'invalid duration rejected');
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'BAD',jsonb_set(pg_temp.diagram(),'{steps,0,positions}','[]'))$$,'22023',null,'step missing a marker position rejected');
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'BAD',pg_temp.diagram()||'{"approved":true}')$$,'22023',null,'client approval metadata rejected');
select pg_temp.login(3);
select is((select count(*)::int from public.play_versions),0,'reviewer cannot see unfinished author drawing');
select pg_temp.login(5);
select is((select count(*)::int from public.plays),0,'ordinary viewer cannot discover unpublished play');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('draft',public.play_transition(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'submit'))$$,'author submits frozen proposal');
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'CHANGED',pg_temp.diagram())$$,'42501',null,'submitted geometry cannot be edited');
select throws_ok($$select public.play_transition(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'approve')$$,'42501',null,'author cannot self-review despite reviewer capability');
select throws_ok($$select public.play_transition(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'publish')$$,'42501',null,'author cannot publish without bypass');
select pg_temp.login(3);
select is((select count(*)::int from public.play_versions),1,'independent reviewer sees submitted revision');
select lives_ok($$select pg_temp.keep('accepted',public.play_transition(pg_temp.team(),pg_temp.id('draft'),pg_temp.rev('draft'),'approve','Synthetic review'))$$,'independent reviewer publishes');
select is((select published_version_id from public.plays where id=pg_temp.play()),pg_temp.id('accepted'),'current pointer resolves accepted immutable version');
select pg_temp.login(5);
select is((select count(*)::int from public.play_versions),1,'active member views accepted play');
select pg_temp.login(6);
select is((select count(*)::int from public.play_versions),0,'nonmember cannot read published play');
select throws_ok($$select public.play_open_draft(pg_temp.team(),pg_temp.play(),pg_temp.id('accepted'))$$,'42501',null,'nonmember command denied');
select pg_temp.login(7);
select is((select count(*)::int from public.play_versions),0,'removed member loses visibility');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('successor',public.play_open_draft(pg_temp.team(),pg_temp.play(),pg_temp.id('accepted')))$$,'author creates successor without changing publication');
select isnt(pg_temp.id('successor'),pg_temp.id('accepted'),'successor receives fresh revision identity');
select is(pg_temp.body('successor')->'diagram',pg_temp.body('accepted')->'diagram','successor preserves stable diagram identities');
select is((select published_version_id from public.plays where id=pg_temp.play()),pg_temp.id('accepted'),'old accepted play remains visible during correction');
select pg_temp.login(4);
select lives_ok($$select pg_temp.keep('bypass',public.play_open_draft(pg_temp.team(),pg_temp.play(),pg_temp.id('accepted')))$$,'second author opens concurrent successor');
select lives_ok($$select pg_temp.keep('bypass',public.play_transition(pg_temp.team(),pg_temp.id('bypass'),pg_temp.rev('bypass'),'publish'))$$,'authorized publisher accepts own successor without individual review');
select pg_temp.login(2);
select throws_ok($$select public.play_save_draft(pg_temp.team(),pg_temp.id('successor'),pg_temp.rev('successor'),'STALE BASE',pg_temp.diagram())$$,'PT409',null,'published-base conflict prevents overwriting newer acceptance');
select is((select count(*)::int from public.play_versions where status='published'),2,'immutable published history remains readable');
reset role;
select throws_ok($$update public.play_versions set diagram='{"markers":[],"steps":[]}',revision=revision+1 where id=pg_temp.id('accepted')$$,'42501',null,'accepted geometry immutable even through trusted SQL');
update public.capability_grants set revoked_at=now() where team_id=pg_temp.team() and user_id='a1000000-0000-4000-8000-000000000004' and capability='plays.author';
set local role authenticated;
select pg_temp.login(4);
select throws_ok($$select public.play_open_draft(pg_temp.team(),'a4000000-0000-4000-8000-000000000002')$$,'42501',null,'revoked author capability immediately blocks opening');
reset role;
update auth.sessions set not_after=now()-interval '1 hour' where user_id='a1000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.login(3);
select is((select count(*)::int from public.play_versions),0,'expired live session cannot view team plays');
select throws_ok($$select public.play_transition(pg_temp.team(),pg_temp.id('accepted'),pg_temp.rev('accepted'),'approve')$$,'42501',null,'expired live session command denied');
select pg_temp.login(1);
select ok((select count(*)>0 from public.team_audit_events where team_id=pg_temp.team() and action like 'play.%'),'play mutations create protected audit events');
select lives_ok($$select pg_temp.keep('owner',public.play_open_draft(pg_temp.team(),'a4000000-0000-4000-8000-000000000002'))$$,'owner authors without operational grant');
select lives_ok($$select pg_temp.keep('owner',public.play_save_draft(pg_temp.team(),pg_temp.id('owner'),pg_temp.rev('owner'),'SYNTHETIC OWNER PLAY',pg_temp.diagram()))$$,'owner saves authored movement');
select lives_ok($$select pg_temp.keep('owner',public.play_transition(pg_temp.team(),pg_temp.id('owner'),pg_temp.rev('owner'),'submit'))$$,'owner may choose submitted workflow');
select lives_ok($$select pg_temp.keep('owner',public.play_transition(pg_temp.team(),pg_temp.id('owner'),pg_temp.rev('owner'),'approve'))$$,'explicit owner self-review exception allowed');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('rejected',public.play_open_draft(pg_temp.team(),'a4000000-0000-4000-8000-000000000003'))$$,'author opens another distinct play');
select lives_ok($$select pg_temp.keep('rejected',public.play_save_draft(pg_temp.team(),pg_temp.id('rejected'),pg_temp.rev('rejected'),'SYNTHETIC REJECTED PLAY',pg_temp.diagram()))$$,'rejection fixture saves geometry');
select lives_ok($$select pg_temp.keep('rejected',public.play_transition(pg_temp.team(),pg_temp.id('rejected'),pg_temp.rev('rejected'),'submit'))$$,'rejection fixture submitted');
select pg_temp.login(1);
select lives_ok($$select pg_temp.keep('rejected',public.play_transition(pg_temp.team(),pg_temp.id('rejected'),pg_temp.rev('rejected'),'reject','Synthetic revision requested'))$$,'owner rejects without exposing proposal to viewers');
select pg_temp.login(5);
select is((select count(*)::int from public.play_versions where play_id='a4000000-0000-4000-8000-000000000003'),0,'ordinary viewer cannot read rejected geometry');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('rejected-successor',public.play_open_draft(pg_temp.team(),'a4000000-0000-4000-8000-000000000003',pg_temp.id('rejected')))$$,'author clones rejected proposal into editable successor');
select isnt(pg_temp.id('rejected-successor'),pg_temp.id('rejected'),'rejected successor has new revision identity');
select is(pg_temp.body('rejected-successor')->'diagram',pg_temp.body('rejected')->'diagram','rejection successor retains authored geometry');
select throws_ok($$select team_private.validate_play('SYNTHETIC',pg_temp.diagram(),true)$$,'42501',null,'private validator not callable by authenticated clients');
select lives_ok($$select pg_temp.keep('rejected-successor',public.play_transition(pg_temp.team(),pg_temp.id('rejected-successor'),pg_temp.rev('rejected-successor'),'submit'))$$,'cloned successor submitted');
reset role;
insert into public.capability_grants(team_id,user_id,capability,issued_by,revoked_at) values(pg_temp.team(),'a1000000-0000-4000-8000-000000000004','plays.review','a1000000-0000-4000-8000-000000000001',now());
set local role authenticated;
select pg_temp.login(4);
select throws_ok($$select public.play_transition(pg_temp.team(),pg_temp.id('rejected-successor'),pg_temp.rev('rejected-successor'),'approve')$$,'42501',null,'revoked reviewer cannot accept a current submission');
select * from finish();
rollback;
