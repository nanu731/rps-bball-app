"""Synthetic creator-default ACL rehearsal; never connects to hosted data."""
import argparse
import json
from pathlib import Path
import re
import sys
import uuid
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from recovery_drill import IsolatedPostgres

READABLE={
    'team_player_accounts':{'team_id','player_id','user_id'},
    'web_seasons':{'id','team_id','name','created_by','created_at'},
    'web_season_games':{'team_id','game_id','season_id','assigned_by','assigned_at'},
    'web_practice_plan_versions':{'id','team_id','practice_id','revision','kind','builder','pdf_version_id','shared_at'},
    'web_join_requests':{'id','team_id','user_id','first_name','last_name','requested_role','status','confirmed_role','revision','created_at'},
}

def run(pg):
    root=Path(__file__).resolve().parents[2]
    sources=sorted((root/'supabase/migrations').glob('*.sql'))
    baseline=sources[:13]+[p for p in sources if p.name.startswith('202611110001')]
    prepared=[p for p in sources if re.match(r'20261117000[1-5]_',p.name)]
    assert len(baseline)==14 and len(prepared)==5
    for privileges in ['TRUNCATE, REFERENCES, TRIGGER, MAINTAIN','ALL']:
        database='teamstats_acl_fixture_'+uuid.uuid4().hex
        pg.run('createdb',['--template','template0',database])
        sql=lambda text:pg.sql(database,text)
        sql((root/'supabase/tests/recovery_platform.sql').read_text())
        for path in baseline:sql(path.read_text())
        sql((root/'supabase/tests/recovery_records.sql').read_text())
        sql("""insert into public.file_resources(id,team_id,kind,game_id) values
          ('fa000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','scouting','f5000000-0000-4000-8000-000000000001');
          insert into public.web_sessions(id,team_id,kind,author_user_id,title,session_date,recorder_user_id,clock_user_id) values
          ('fb000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','practice','f1000000-0000-4000-8000-000000000001','TEST ONLY pre-upgrade practice','2037-01-01','f1000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000001');""")
        before=pg.snapshot(database)['rows']
        # Match observed editor defaults, then the provider-admin broad variant.
        sql('alter default privileges in schema public grant '+privileges+' on tables to anon,authenticated,service_role;')
        for path in prepared:sql(path.read_text())
        for table,readable in READABLE.items():
            actual=json.loads(sql(f"select jsonb_agg(jsonb_build_object('name',a.attname,'read',has_column_privilege('authenticated',c.oid,a.attnum,'SELECT')) order by a.attnum) from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid where n.nspname='public' and c.relname='{table}' and a.attnum>0 and not a.attisdropped;"))
            assert {c['name'] for c in actual if c['read']}==readable,table+': authenticated column projection broadened'
            unsafe=sql(f"select has_table_privilege('anon','public.{table}','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') or has_table_privilege('authenticated','public.{table}','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN');")
            assert unsafe=='f',table+': creator defaults leaked client privileges'
            assert sql(f"select relrowsecurity from pg_class where oid='public.{table}'::regclass;")=='t'
        assert sql("select has_schema_privilege('authenticated','team_private','USAGE');")=='t'
        after=pg.snapshot(database)['rows']
        for table,rows in before.items():
            # New nullable columns may be added, but existing values must survive exactly.
            columns=set(rows[0]) if rows else set()
            projected=[{k:v for k,v in row.items() if k in columns} for row in after[table]]
            assert sorted(map(lambda r:json.dumps(r,sort_keys=True),rows))==sorted(map(lambda r:json.dumps(r,sort_keys=True),projected)),table+': existing data changed'
        print('PASS new web table ACLs/RLS with creator defaults '+privileges,flush=True)
        print('PASS populated baseline upgrade preserves identities, history, missing/zero and file/session metadata',flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--pg-bin',type=Path);group.add_argument('--container')
    parser.add_argument('--recovery-output',type=Path,required=True)
    args=parser.parse_args();proof=json.loads((args.recovery_output/'receipt.json').read_text());source=proof['restored']
    assert proof.get('hostedRecovery') is False and proof.get('restoredRowsAndPoliciesEqual')
    assert re.fullmatch(r'teamstats_recovery_restored_[a-f0-9]{32}',source)
    pg=IsolatedPostgres(args.recovery_output,args.pg_bin,args.container);before=pg.snapshot(source)
    authority="select jsonb_build_object('roles',(select jsonb_agg(to_jsonb(r) order by rolname) from pg_roles r),'memberships',(select jsonb_agg(to_jsonb(m) order by roleid,member) from pg_auth_members m))::text;"
    roles=pg.sql('postgres',authority)
    try:run(pg)
    finally:
        assert pg.snapshot(source)==before,'Original synthetic recovery records changed'
        assert pg.sql('postgres',authority)==roles,'Existing cluster authority changed'
