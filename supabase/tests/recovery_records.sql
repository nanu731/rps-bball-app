-- Synthetic state exists BEFORE pg_dump, never reconstructed after pg_restore.
insert into auth.users(id,email,email_confirmed_at) values
 ('f1000000-0000-4000-8000-000000000001','recovery-owner@example.invalid',now()),
 ('f1000000-0000-4000-8000-000000000002','recovery-member@example.invalid',now()),
 ('f1000000-0000-4000-8000-000000000003','recovery-outsider@example.invalid',now());
insert into auth.sessions(id,user_id,not_after)
 select ('f2000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 ('f1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,now()+interval '1 day'
 from generate_series(1,3) n;
insert into public.teams(id,name,owner_auth_uuid) values
 ('f3000000-0000-4000-8000-000000000001','TEST ONLY recovery team','f1000000-0000-4000-8000-000000000001');
insert into public.team_memberships(team_id,user_id,status) values
 ('f3000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000002','active');
insert into public.capability_grants(team_id,user_id,capability,issued_by) values
 ('f3000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000002','stats.review','f1000000-0000-4000-8000-000000000001');
insert into public.roster_entries(id,team_id,display_name,jersey_number) values
 ('f4000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','TEST ONLY recovery player','0');
insert into public.games(id,team_id,date,opponent,home_away,game_type,created_by) values
 ('f5000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','2037-01-01','TEST ONLY recovery opponent','home','regularSeason','f1000000-0000-4000-8000-000000000001');
insert into public.stat_datasets(id,team_id,game_id,dataset_type) values
 ('f6000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','f5000000-0000-4000-8000-000000000001','box_scores');
insert into public.stat_versions(id,team_id,game_id,dataset_id,dataset_type,author_user_id,status,records,covered_roster) values
 ('f7000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','f5000000-0000-4000-8000-000000000001','f6000000-0000-4000-8000-000000000001','box_scores','f1000000-0000-4000-8000-000000000001','published',
 '[{"gameID":"f5000000-0000-4000-8000-000000000001","playerID":"f4000000-0000-4000-8000-000000000001","values":{"points":0}}]',
 '[{"id":"f4000000-0000-4000-8000-000000000001","version":1}]'),
 ('f7000000-0000-4000-8000-000000000002','f3000000-0000-4000-8000-000000000001','f5000000-0000-4000-8000-000000000001','f6000000-0000-4000-8000-000000000001','box_scores','f1000000-0000-4000-8000-000000000001','draft',
 '[{"gameID":"f5000000-0000-4000-8000-000000000001","playerID":"f4000000-0000-4000-8000-000000000001","values":{"points":4,"threesMade":7}}]',
 '[{"id":"f4000000-0000-4000-8000-000000000001","version":1}]');
update public.stat_datasets set published_version_id='f7000000-0000-4000-8000-000000000001';
insert into public.stat_export_outbox(id,team_id,game_id,accepted_version_id,publication_generation) values
 ('f8000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','f5000000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000001',1);
-- Metadata is backed up with SQL; the corresponding bytes are a SEPARATE artifact.
insert into storage.objects(id,bucket_id,name) values
 ('f9000000-0000-4000-8000-000000000001','teamstats-private','synthetic-team/synthetic-version');
