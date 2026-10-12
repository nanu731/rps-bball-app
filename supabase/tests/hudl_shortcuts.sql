-- Isolated synthetic fixture; all users, grants, drafts and audit events roll back.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,email_confirmed_at) values
('e1000000-0000-4000-8000-000000000001','synthetic-hudl-owner@example.invalid',now()),
('e1000000-0000-4000-8000-000000000002','synthetic-hudl-contributor@example.invalid',now());
insert into auth.sessions(id,user_id,not_after) values
('e2000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001',now()+interval '1 day'),
('e2000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-000000000002',now()+interval '1 day');
create function pg_temp.hudl_login(n int) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub','e1000000-0000-4000-8000-'||lpad(n::text,12,'0'),
 'session_id','e2000000-0000-4000-8000-'||lpad(n::text,12,'0'),'exp',extract(epoch from now()+interval '1 hour'),
 'role','authenticated','is_anonymous',false)::text,true); end$$;
create function pg_temp.hudl_team() returns uuid language sql as $$select 'e3000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.hudl_game() returns uuid language sql as $$select 'e4000000-0000-4000-8000-000000000001'::uuid$$;
create function pg_temp.hudl_resource(n int) returns uuid language sql as $$select ('e5000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create temp table hudl_results(name text primary key,body jsonb);
grant select,insert,update on hudl_results to authenticated;
create function pg_temp.hudl_keep(n text,b jsonb) returns jsonb language plpgsql as $$begin insert into hudl_results values(n,b) on conflict(name) do update set body=excluded.body; return b; end$$;
create function pg_temp.hudl_id(n text) returns uuid language sql as $$select (body->>'id')::uuid from hudl_results where name=n$$;
create function pg_temp.hudl_rev(n text) returns bigint language sql as $$select (body->>'revision')::bigint from hudl_results where name=n$$;
insert into public.teams(id,name,owner_auth_uuid) values(pg_temp.hudl_team(),'SYNTHETIC HUDL TEAM','e1000000-0000-4000-8000-000000000001');
insert into public.team_memberships(team_id,user_id,status) values(pg_temp.hudl_team(),'e1000000-0000-4000-8000-000000000002','active');
insert into public.capability_grants(team_id,user_id,capability,issued_by) values
(pg_temp.hudl_team(),'e1000000-0000-4000-8000-000000000002','film.upload','e1000000-0000-4000-8000-000000000001');
insert into public.games(id,team_id,date,opponent,home_away,game_type,created_by)
values(pg_temp.hudl_game(),pg_temp.hudl_team(),'2026-10-12','SYNTHETIC HUDL OPPONENT','home','regularSeason','e1000000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.hudl_login(2);
select pg_temp.hudl_keep('draft',public.media_open_draft(pg_temp.hudl_team(),pg_temp.hudl_resource(1),'film',pg_temp.hudl_game()));
select throws_ok($$select public.media_save_draft(pg_temp.hudl_team(),pg_temp.hudl_id('draft'),pg_temp.hudl_rev('draft'),'SYNTHETIC FILM','https://film.example.invalid/watch','')$$,'22023',null,'film drafts reject non-Hudl destinations through the command');

select lives_ok($$select pg_temp.hudl_keep('draft',public.media_save_draft(pg_temp.hudl_team(),pg_temp.hudl_id('draft'),pg_temp.hudl_rev('draft'),'','', ''))$$,'missing shortcut remains an incomplete draft');
select throws_ok($$select public.media_transition(pg_temp.hudl_team(),pg_temp.hudl_id('draft'),pg_temp.hudl_rev('draft'),'submit')$$,'22023',null,'blank draft cannot be submitted');
select throws_ok(format('select public.media_save_draft(pg_temp.hudl_team(),pg_temp.hudl_id(''draft''),pg_temp.hudl_rev(''draft''),''SYNTHETIC FILM'',%L,'''')',url),'22023',null,'unsafe or unsupported Hudl destination is rejected: '||label)
from (values
 ('https://hudl.com.evil.invalid/watch','lookalike suffix'),
 ('https://evilhudl.com/watch','lookalike prefix'),
 ('https://hudl.com./watch','trailing dot'),
 ('https://unverified.hudl.com/watch','unsupported subdomain'),
 ('https://user@hudl.com/watch','userinfo'),
 ('https://hudl.com:8443/watch','nonstandard port'),
 ('https://%68udl.com/watch','encoded authority'),
 ('https://hudl.com/watch#private','fragment'),
 ('https://hudl.com/watch?access_token=synthetic','credential query'),
 ('http://hudl.com/watch','insecure scheme')) as unsupported(url,label);
select lives_ok($$select pg_temp.hudl_keep('draft',public.media_save_draft(pg_temp.hudl_team(),pg_temp.hudl_id('draft'),pg_temp.hudl_rev('draft'),'SYNTHETIC HUDL SHORTCUT','https://www.hudl.com/video/synthetic-never-opened',''))$$,'eligible author saves a supported shortcut');
select lives_ok($$select pg_temp.hudl_keep('draft',public.media_transition(pg_temp.hudl_team(),pg_temp.hudl_id('draft'),pg_temp.hudl_rev('draft'),'submit'))$$,'supported shortcut enters owner review');
select pg_temp.hudl_login(1);
select lives_ok($$select pg_temp.hudl_keep('published',public.media_transition(pg_temp.hudl_team(),pg_temp.hudl_id('draft'),pg_temp.hudl_rev('draft'),'approve'))$$,'only the owner approves the reviewed Hudl shortcut');
select is((select published_version_id from public.media_resources where id=pg_temp.hudl_resource(1)),pg_temp.hudl_id('published'),'accepted identity remains game-linked');
reset role;
-- Trusted fixture models records saved before this rule; direct client inserts remain revoked.
insert into public.media_resources(id,team_id,kind,game_id)
values(pg_temp.hudl_resource(2),pg_temp.hudl_team(),'film',pg_temp.hudl_game());
insert into public.media_resource_versions(id,team_id,resource_id,author_user_id,status,title,link_url)
values('e6000000-0000-4000-8000-000000000001',pg_temp.hudl_team(),pg_temp.hudl_resource(2),'e1000000-0000-4000-8000-000000000002','submitted','SYNTHETIC EARLIER LINK','https://film.example.invalid/earlier');
set local role authenticated;
select pg_temp.hudl_login(1);
select throws_ok($$select public.media_transition(pg_temp.hudl_team(),'e6000000-0000-4000-8000-000000000001',1,'approve')$$,'22023',null,'historical pending non-Hudl link cannot be newly published');
select lives_ok($$select public.media_transition(pg_temp.hudl_team(),'e6000000-0000-4000-8000-000000000001',1,'reject','Use a supported Hudl shortcut')$$,'owner can reject historical pending links without changing saved link text');
select is((select link_url from public.media_resource_versions where id='e6000000-0000-4000-8000-000000000001'),'https://film.example.invalid/earlier','saved earlier link is preserved');
select pg_temp.hudl_login(2);
select lives_ok($$select pg_temp.hudl_keep('successor',public.media_open_draft(pg_temp.hudl_team(),pg_temp.hudl_resource(2),'film',pg_temp.hudl_game(),'e6000000-0000-4000-8000-000000000001'))$$,'earlier rejected metadata can seed a retained successor');
select throws_ok($$select public.media_save_draft(pg_temp.hudl_team(),pg_temp.hudl_id('successor'),pg_temp.hudl_rev('successor'),'SYNTHETIC EARLIER LINK','https://film.example.invalid/earlier','new notes')$$,'22023',null,'new saves require replacing unsupported historical destination explicitly');
select lives_ok($$select public.media_save_draft(pg_temp.hudl_team(),pg_temp.hudl_id('successor'),pg_temp.hudl_rev('successor'),'SYNTHETIC REVISED SHORTCUT','https://HUDL.COM:443/video/synthetic-never-opened','')$$,'supported case-insensitive Hudl host and explicit standard port save');
select throws_ok($$select team_private.hudl_link_valid('https://hudl.com/')$$,'42501',null,'private validator is not a public command');
select * from finish();
rollback;
