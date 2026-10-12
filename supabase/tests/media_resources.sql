-- Synthetic fixture identities; every fixture and audit event rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
select has_function('public','media_open_draft',array['uuid','uuid','text','uuid','uuid'],
 'active practice contributors open a private reviewed link draft');
insert into auth.users(id,email,email_confirmed_at)
select ('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'synthetic-media-'||n||'@example.invalid',now() from generate_series(1,9)n;
insert into auth.sessions(id,user_id,not_after)
select ('b2000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now()+interval '1 day' from generate_series(1,9)n;
create function pg_temp.login(n int) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub','b1000000-0000-4000-8000-'||lpad(n::text,12,'0'),
 'session_id','b2000000-0000-4000-8000-'||lpad(n::text,12,'0'),'exp',extract(epoch from now()+interval '1 hour'),
 'role','authenticated','is_anonymous',false)::text,true); end$$;
create function pg_temp.team() returns uuid language sql as $$select 'b3000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.play() returns uuid language sql as $$select 'b4000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.game() returns uuid language sql as $$select 'b5000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.resource(n int) returns uuid language sql as $$select ('b6000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create temp table results(name text primary key,body jsonb);
grant select,insert,update on results to authenticated;
create function pg_temp.keep(n text,b jsonb) returns jsonb language plpgsql as $$begin insert into results values(n,b) on conflict(name) do update set body=excluded.body; return b; end$$;
create function pg_temp.body(n text) returns jsonb language sql as $$select body from results where name=n$$;
create function pg_temp.id(n text) returns uuid language sql as $$select (body->>'id')::uuid from results where name=n$$;
create function pg_temp.rev(n text) returns bigint language sql as $$select (body->>'revision')::bigint from results where name=n$$;
insert into public.teams(id,name,owner_auth_uuid) values(pg_temp.team(),'SYNTHETIC MEDIA TEAM','b1000000-0000-4000-8000-000000000001');
insert into public.team_memberships(team_id,user_id,status) select pg_temp.team(),('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case when n=8 then 'removed' else 'active' end from generate_series(2,9)n where n<>7;
insert into public.capability_grants(team_id,user_id,capability,issued_by) values
(pg_temp.team(),'b1000000-0000-4000-8000-000000000003','practice.review','b1000000-0000-4000-8000-000000000001'),
(pg_temp.team(),'b1000000-0000-4000-8000-000000000003','film.review','b1000000-0000-4000-8000-000000000001'),
(pg_temp.team(),'b1000000-0000-4000-8000-000000000004','practice.publish','b1000000-0000-4000-8000-000000000001'),
(pg_temp.team(),'b1000000-0000-4000-8000-000000000004','film.publish','b1000000-0000-4000-8000-000000000001'),
(pg_temp.team(),'b1000000-0000-4000-8000-000000000005','film.upload','b1000000-0000-4000-8000-000000000001'),
(pg_temp.team(),'b1000000-0000-4000-8000-000000000006','film.upload','b1000000-0000-4000-8000-000000000001'),
(pg_temp.team(),'b1000000-0000-4000-8000-000000000006','film.publish','b1000000-0000-4000-8000-000000000001');
-- Trusted synthetic published play setup; no actual user content or existing records touched.
insert into public.plays(id,team_id,created_by) values(pg_temp.play(),pg_temp.team(),'b1000000-0000-4000-8000-000000000001');
insert into public.play_versions(id,team_id,play_id,author_user_id,status,title)
values('b7000000-0000-4000-8000-000000000001',pg_temp.team(),pg_temp.play(),'b1000000-0000-4000-8000-000000000001','published','SYNTHETIC LINK TARGET');
update public.plays set published_version_id='b7000000-0000-4000-8000-000000000001' where id=pg_temp.play();
insert into public.plays(id,team_id,created_by) values('b4000000-0000-4000-8000-000000000002',pg_temp.team(),'b1000000-0000-4000-8000-000000000001');
insert into public.games(id,team_id,date,opponent,home_away,game_type,created_by)
values(pg_temp.game(),pg_temp.team(),'2026-10-11','SYNTHETIC MEDIA OPPONENT','home','regularSeason','b1000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('practice',public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'practice',pg_temp.play()))$$,'ordinary active member contributes practice without upload grant');
select is(public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'practice',pg_temp.play()),pg_temp.body('practice'),'opening retry retains stable private draft identity');
select is(pg_temp.body('practice')->>'link_url','','empty draft does not invent provider link');
select throws_ok($$select public.media_open_draft(pg_temp.team(),pg_temp.resource(2),'practice','b4000000-0000-4000-8000-000000000002')$$,'22023',null,'unpublished play cannot receive ordinary contribution');
select throws_ok($$select public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'film',pg_temp.game())$$,'42501',null,'ordinary member lacks film eligibility');
select throws_ok($$insert into public.media_resource_versions(team_id,resource_id,author_user_id,status) values(pg_temp.team(),pg_temp.resource(1),'b1000000-0000-4000-8000-000000000002','published')$$,'42501',null,'direct metadata publication denied');
select lives_ok($$select pg_temp.keep('practice',public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'','',''))$$,'incomplete draft can be saved without invented values');
select throws_ok($$select public.media_transition(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'submit')$$,'22023',null,'incomplete draft cannot be submitted');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),1,'STALE','https://video.example.invalid/watch','')$$,'40001',null,'stale draft save rejected');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'BAD','http://video.example.invalid/watch','')$$,'22023',null,'non-HTTPS link rejected');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'BAD','https://user:secret@video.example.invalid/watch','')$$,'22023',null,'URL user credentials rejected');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'BAD','https://video.example.invalid/#token=synthetic','')$$,'22023',null,'token-bearing fragments rejected');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'BAD','https://video.example.invalid/?access_token=synthetic','')$$,'22023',null,'credential query keys rejected');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'BAD','https://video.example.invalid/?%74oken=synthetic','')$$,'22023',null,'encoded credential key rejected');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'BAD','https://video.example.invalid/%zz','')$$,'22023',null,'invalid percent escape rejected');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),repeat('x',121),'https://video.example.invalid/watch','')$$,'22023',null,'oversized title rejected');
select lives_ok($$select pg_temp.keep('practice',public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'SYNTHETIC PRACTICE LINK','https://video.example.invalid/watch?v=synthetic','SYNTHETIC NOTES'))$$,'valid user-authored link saved');
select pg_temp.login(3);
select is((select count(*)::int from public.media_resource_versions),0,'inspection grant cannot view unfinished author draft');
select pg_temp.login(9);
select is((select count(*)::int from public.media_resources),0,'ordinary viewer cannot discover private draft parent');
select pg_temp.login(2);
select throws_ok($$select public.media_transition(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'publish')$$,'42501',null,'ordinary contributor lacks bypass');
select lives_ok($$select pg_temp.keep('practice',public.media_transition(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'submit'))$$,'ordinary practice link submitted for owner review');
select throws_ok($$select public.media_save_draft(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'CHANGED','https://video.example.invalid/changed','')$$,'42501',null,'submitted link is frozen');
select pg_temp.login(9);
select is((select count(*)::int from public.media_resource_versions),0,'pending resource hidden from ordinary viewers');
select pg_temp.login(3);
select is((select count(*)::int from public.media_resource_versions),1,'legacy review capability inspects pending link');
select throws_ok($$select public.media_transition(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'approve')$$,'42501',null,'legacy inspector cannot approve practice link');
select throws_ok($$select public.media_transition(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'reject')$$,'42501',null,'legacy inspector cannot reject owner pending queue');
select pg_temp.login(1);
select lives_ok($$select pg_temp.keep('accepted',public.media_transition(pg_temp.team(),pg_temp.id('practice'),pg_temp.rev('practice'),'approve','Synthetic owner approval'))$$,'owner approves submitted practice link');
select is((select published_version_id from public.media_resources where id=pg_temp.resource(1)),pg_temp.id('accepted'),'accepted pointer changes atomically');
select pg_temp.login(9);
select is((select count(*)::int from public.media_resource_versions),1,'active member reads published link');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('correction',public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'practice',pg_temp.play(),pg_temp.id('accepted')))$$,'ordinary contributor proposes successor');
select isnt(pg_temp.id('correction'),pg_temp.id('accepted'),'successor has fresh immutable version identity');
select is(pg_temp.body('correction')->>'link_url',pg_temp.body('accepted')->>'link_url','successor preserves saved link');
select is((select published_version_id from public.media_resources where id=pg_temp.resource(1)),pg_temp.id('accepted'),'accepted link stays visible during correction');
select pg_temp.login(4);
select lives_ok($$select pg_temp.keep('bypass',public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'practice',pg_temp.play(),pg_temp.id('accepted')))$$,'practice publication bypass needs no redundant upload grant');
select lives_ok($$select pg_temp.keep('bypass',public.media_transition(pg_temp.team(),pg_temp.id('bypass'),pg_temp.rev('bypass'),'publish'))$$,'authorized author publishes own practice successor');
select throws_ok($$select public.media_open_draft(pg_temp.team(),pg_temp.resource(3),'film',pg_temp.game())$$,'42501',null,'film publication grant alone is not film eligibility');
select pg_temp.login(2);
select throws_ok($$select public.media_transition(pg_temp.team(),pg_temp.id('correction'),pg_temp.rev('correction'),'publish')$$,'42501',null,'ordinary successor cannot bypass review');
select pg_temp.keep('correction',public.media_transition(pg_temp.team(),pg_temp.id('correction'),pg_temp.rev('correction'),'submit'));
select pg_temp.login(1);
select throws_ok($$select public.media_transition(pg_temp.team(),pg_temp.id('correction'),pg_temp.rev('correction'),'approve')$$,'40001',null,'stale submitted successor cannot overwrite newer accepted link');
select lives_ok($$select pg_temp.keep('correction',public.media_transition(pg_temp.team(),pg_temp.id('correction'),pg_temp.rev('correction'),'reject','Newer accepted link exists'))$$,'owner can reject stale proposal');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('revised',public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'practice',pg_temp.play(),pg_temp.id('correction')))$$,'rejected author opens fresh reviewed successor');
select is(pg_temp.body('revised')->>'base_published_version_id',pg_temp.id('bypass')::text,'successor captures current accepted base');
select pg_temp.login(5);
select lives_ok($$select pg_temp.keep('film',public.media_open_draft(pg_temp.team(),pg_temp.resource(4),'film',pg_temp.game()))$$,'eligible film contributor opens game-linked draft');
select pg_temp.keep('film',public.media_save_draft(pg_temp.team(),pg_temp.id('film'),pg_temp.rev('film'),'SYNTHETIC FILM LINK','https://film.example.invalid/watch',''));
select lives_ok($$select pg_temp.keep('film',public.media_transition(pg_temp.team(),pg_temp.id('film'),pg_temp.rev('film'),'submit'))$$,'eligible film submits pending owner review');
select pg_temp.login(3);
select is((select count(*)::int from public.media_resource_versions where id=pg_temp.id('film')),1,'film inspector reads pending metadata');
select throws_ok($$select public.media_transition(pg_temp.team(),pg_temp.id('film'),pg_temp.rev('film'),'approve')$$,'42501',null,'film inspector cannot approve pending video');
select pg_temp.login(1);
select lives_ok($$select pg_temp.keep('film',public.media_transition(pg_temp.team(),pg_temp.id('film'),pg_temp.rev('film'),'approve'))$$,'owner approves game-film link');
select pg_temp.login(6);
select pg_temp.keep('film-bypass',public.media_open_draft(pg_temp.team(),pg_temp.resource(5),'film',pg_temp.game()));
select pg_temp.keep('film-bypass',public.media_save_draft(pg_temp.team(),pg_temp.id('film-bypass'),pg_temp.rev('film-bypass'),'SYNTHETIC BYPASS FILM','https://film.example.invalid/other',''));
select lives_ok($$select pg_temp.keep('film-bypass',public.media_transition(pg_temp.team(),pg_temp.id('film-bypass'),pg_temp.rev('film-bypass'),'publish'))$$,'eligible film author with bypass publishes own link');
select pg_temp.login(7);
select is((select count(*)::int from public.media_resource_versions),0,'nonmember cannot read accepted links');
select throws_ok($$select public.media_open_draft(pg_temp.team(),pg_temp.resource(6),'practice',pg_temp.play())$$,'42501',null,'nonmember contribution rejected');
select pg_temp.login(8);
select is((select count(*)::int from public.media_resource_versions),0,'removed member cannot read links');
reset role;
select throws_ok($$update public.media_resource_versions set link_url='https://example.invalid/changed',revision=revision+1 where id=pg_temp.id('accepted')$$,'42501',null,'accepted history immutable under trusted direct update');
select throws_ok($$delete from public.media_resources where id=pg_temp.resource(1)$$,'42501',null,'record deletion control unavailable even through trusted SQL');
update public.capability_grants set revoked_at=now() where user_id='b1000000-0000-4000-8000-000000000006' and capability='film.upload';
set local role authenticated;
select pg_temp.login(6);
select throws_ok($$select public.media_open_draft(pg_temp.team(),pg_temp.resource(7),'film',pg_temp.game())$$,'42501',null,'revoked film eligibility blocks new drafts despite bypass');
reset role;
update auth.sessions set not_after=now()-interval '1 hour' where user_id='b1000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.login(3);
select is((select count(*)::int from public.media_resource_versions),0,'expired session cannot inspect pending or published');
select throws_ok($$select public.media_open_draft(pg_temp.team(),pg_temp.resource(8),'practice',pg_temp.play())$$,'42501',null,'expired session cannot contribute');
select pg_temp.login(1);
select ok((select count(*)>0 from public.team_audit_events where team_id=pg_temp.team() and action like 'media.%'),'media commands append protected audit events');
select throws_ok($$select team_private.media_eligible(pg_temp.team(),'b1000000-0000-4000-8000-000000000002','film')$$,'42501',null,'private eligibility helper not public command');
select has_function('public','media_resume_draft',array['uuid','uuid','bigint','uuid'],
 'author explicitly preserves stale draft and resumes against current accepted pointer');
-- Explicit recovery preserves the author's saved proposal instead of silently rebasing.
select pg_temp.login(4);
select pg_temp.keep('newer',public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'practice',pg_temp.play(),pg_temp.id('bypass')));
select pg_temp.keep('newer',public.media_transition(pg_temp.team(),pg_temp.id('newer'),pg_temp.rev('newer'),'publish'));
select pg_temp.login(2);
select pg_temp.keep('revised',public.media_save_draft(pg_temp.team(),pg_temp.id('revised'),pg_temp.rev('revised'),'MY SYNTHETIC SAVED PROPOSAL','https://video.example.invalid/my-proposal','Saved author notes'));
select is(public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'practice',pg_temp.play(),pg_temp.id('newer')),pg_temp.body('revised'),'opening newer source does not silently rebase existing draft');
select throws_ok($$select public.media_resume_draft(pg_temp.team(),pg_temp.id('revised'),1,pg_temp.id('newer'))$$,'40001',null,'resume rejects stale expected draft revision');
select throws_ok($$select public.media_resume_draft(pg_temp.team(),pg_temp.id('revised'),pg_temp.rev('revised'),pg_temp.id('bypass'))$$,'40001',null,'resume rejects stale expected accepted pointer');
select pg_temp.login(9);
select throws_ok($$select public.media_resume_draft(pg_temp.team(),pg_temp.id('revised'),pg_temp.rev('revised'),pg_temp.id('newer'))$$,'42501',null,'another active member cannot resume private saved proposal');
select pg_temp.login(2);
select lives_ok($$select pg_temp.keep('resume',public.media_resume_draft(pg_temp.team(),pg_temp.id('revised'),pg_temp.rev('revised'),pg_temp.id('newer')))$$,'author explicitly preserves saved proposal and resumes current draft');
select is(pg_temp.body('resume')->'previous'->>'status','superseded','earlier saved proposal is honestly read-only superseded');
select is(pg_temp.body('resume')->'draft'->>'title','MY SYNTHETIC SAVED PROPOSAL','fresh draft copies author proposal not newer publisher content');
select is(pg_temp.body('resume')->'draft'->>'notes','Saved author notes','saved author notes survive resume');
select is(pg_temp.body('resume')->'draft'->>'base_published_version_id',pg_temp.id('newer')::text,'resumed draft identifies checked current accepted base');
select is((select published_version_id from public.media_resources where id=pg_temp.resource(1)),pg_temp.id('newer'),'resume leaves current accepted pointer unchanged');
select is((select count(*)::int from public.media_resource_versions where resource_id=pg_temp.resource(1) and status='draft' and author_user_id='b1000000-0000-4000-8000-000000000002'),1,'resume retains exactly one editable author draft');
select throws_ok($$select public.media_resume_draft(pg_temp.team(),pg_temp.id('revised'),pg_temp.rev('revised')+1,pg_temp.id('newer'))$$,'42501',null,'retry cannot supersede same earlier proposal twice');
select is(public.media_open_draft(pg_temp.team(),pg_temp.resource(1),'practice',pg_temp.play(),pg_temp.id('newer')),pg_temp.body('resume')->'draft','opening now returns the resumed draft');
reset role;
select throws_ok($$update public.media_resource_versions set notes='CHANGED',revision=revision+1 where id=pg_temp.id('revised')$$,'42501',null,'saved superseded proposal immutable even through trusted SQL');
select * from finish();
rollback;
