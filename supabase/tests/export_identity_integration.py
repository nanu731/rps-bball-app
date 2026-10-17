"""Worker authority only in a fresh isolated synthetic cluster; no signed JWT ingress."""
import argparse
import json
from pathlib import Path
import re
import sys
import uuid
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from recovery_drill import IsolatedPostgres


def verify(pg, output):
    receipt=json.loads((output/'receipt.json').read_text());source=receipt['restored']
    if receipt.get('hostedRecovery') is not False or not re.fullmatch(r'teamstats_recovery_restored_[a-f0-9]{32}',source):
        raise ValueError('Synthetic recovery receipt required')
    assert pg.sql(source,"select exists(select 1 from pg_roles where rolname='teamstats_export_worker')")=='t','Dedicated worker role is absent'

    target='teamstats_export_identity_'+uuid.uuid4().hex
    if pg.sql(source,"select count(*)=1 and bool_and(name='TEST ONLY recovery team') from public.teams")!='t':
        raise ValueError('Known synthetic team required')
    pg.run('createdb',['--template',source,target]);before=pg.snapshot(source)
    def sql(text):return pg.sql(target,text)
    def quote(v):return "'"+str(v).replace("'","''")+"'"
    def value(v):return 'null' if v is None else quote(json.dumps(v))+'::jsonb' if isinstance(v,dict) else str(v) if type(v) is int else quote(v)
    now=int(sql('select extract(epoch from clock_timestamp())::bigint'))
    claims=dict(role='teamstats_export_worker',aud='authenticated',iat=now-1,exp=now+600)
    def call(name,args=None,role='teamstats_export_worker',context=None):
        text='begin;set local role '+role+';set local request.jwt.claims='+quote(json.dumps(claims if context is None else context))+';'
        text+='select public.'+name+'('+','.join(k+'=>'+value(v) for k,v in (args or {}).items())+');commit;'
        raw=sql(text);return json.loads(raw) if raw and raw!='null' else None
    def refused(statement,role='teamstats_export_worker',context=None):
        sql('begin;set local role '+role+';set local request.jwt.claims='+quote(json.dumps(claims if context is None else context))+''';
          do $test$ begin begin '''+statement+'''; raise exception 'Expected denial';
          exception when insufficient_privilege then null; end; end $test$;rollback;''')
    assert sql("select not (rolcanlogin or rolinherit or rolbypassrls or rolsuper or rolcreatedb or rolcreaterole or rolreplication) from pg_roles where rolname='teamstats_export_worker'")=='t'
    assert sql("select count(*)=0 from pg_auth_members where member='teamstats_export_worker'::regrole")=='t'
    assert sql("select not admin_option and not inherit_option and set_option from pg_auth_members where roleid='teamstats_export_worker'::regrole and member='authenticator'::regrole")=='t'
    assert sql("select not pg_has_role('authenticator','teamstats_export_worker','USAGE') and pg_has_role('authenticator','teamstats_export_worker','SET')")=='t'
    assert sql("begin;set session authorization authenticator;set role teamstats_export_worker;select current_setting('role');rollback;")=='teamstats_export_worker'
    sql("begin;set session authorization authenticated;do $$begin begin execute 'set role teamstats_export_worker';raise exception 'Expected role denial';exception when insufficient_privilege then null;end;end$$;rollback;")
    allowed=json.loads(sql("select jsonb_agg(p.proname order by p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('teamstats_export_worker',p.oid,'EXECUTE')"))
    assert allowed==['stats_export_acknowledge','stats_export_claim','stats_export_claimed_reserve','stats_export_record_failure']
    for role in ('anon','authenticated','service_role'):
        assert sql("select not pg_has_role('"+role+"','teamstats_export_worker','MEMBER')")=='t'
    for table in ('public.stat_export_deliveries','public.teams','auth.users','team_private.account_deletion_requests'):
        for command in (f'perform * from {table}',f'insert into {table} default values',f'update {table} set '+('name=name' if table=='public.teams' else 'id=id' if table=='auth.users' else 'user_id=user_id' if 'deletion' in table else 'job_id=job_id'),f'delete from {table}'):
            refused(command)
    refused('create table public.synthetic_forbidden (id int)')
    team='f3000000-0000-4000-8000-000000000001';job_id='f8000000-0000-4000-8000-000000000001'
    for statement in [f"perform public.team_access('{team}')",'perform public.stats_export_jobs()',
        f"perform public.stats_export_configure('{team}','SYNTHETIC_OTHER',0,100,1000,1000)",
        f"perform public.stats_export_resume('{job_id}')",f"perform public.stats_export_reserve('{job_id}')",
        f"perform public.stats_export_finish('{job_id}','{{}}')",f"perform public.stats_export_fail('{job_id}','provider_timeout')"]:
        refused(statement)
    bad=[{},dict(claims,role='service_role'),dict(claims,aud=['authenticated']),dict(claims,iat=None),dict(claims,iat=str(now)),
        dict(claims,iat=now+.5),dict(claims,iat=now+60),dict(claims,exp=now-1),dict(claims,exp=now+1000),dict(claims,exp='Infinity'),dict(claims,exp=10**25)]
    for invalid in bad:refused('perform public.stats_export_claim()',context=invalid)
    call('stats_export_configure',dict(p_team_id=team,p_spreadsheet_id='SYNTHETIC_IDENTITY',p_ledger_sheet_id=0,p_snapshot_min=100,p_snapshot_max=1000,p_ledger_rows=1000),role='service_role')
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=8) as pool:replies=list(pool.map(lambda _:call('stats_export_claim'),range(8)))
    granted=[r for r in replies if r is not None];assert len(granted)==1
    first=granted[0];args=dict(p_job_id=first['job_id'],p_claim_token=first['claim_token'])
    reservation=call('stats_export_claimed_reserve',args)
    call('stats_export_record_failure',dict(args,p_error_code='destination_conflict'))
    assert call('stats_export_claim') is None
    refused(f"perform public.stats_export_resume('{job_id}')")
    call('stats_export_resume',dict(p_job_id=job_id),role='service_role')
    refused('perform public.stats_export_claim()',context=dict(claims,exp=now-1))
    import sheets_export as worker
    from test_sheets_export import Fixture
    class SQLBackend:
        def __init__(self,expire=False):self.expire=expire;self.commands=[]
        def rpc(self,name,arguments):
            self.commands.append(name)
            if self.expire and name=='stats_export_acknowledge':
                refused('perform public.stats_export_acknowledge('+','.join(value(v) for v in arguments.values())+')',context=dict(claims,exp=now-1))
                raise worker.ExportError('backend_denied')
            return call(name,arguments)
    fixture=Fixture('timeout_applied')
    try:
        backend=SQLBackend(expire=True)
        try:worker.run_once(backend,worker.GoogleSheets(fixture.config(timeout=.03)))
        except worker.ExportError as error:assert str(error)=='backend_denied'
        else:raise AssertionError('Expired acknowledgement was reported successful')
        assert backend.commands==['stats_export_claim','stats_export_claimed_reserve','stats_export_acknowledge']
        assert len(fixture.batches)==1
        state=json.loads(sql('select to_jsonb(d) from public.stat_export_deliveries d'))
        assert state['queue_state']=='claimed' and state['state']!='delivered'
        # Synthetic queue clock only: expire the abandoned lease, then honor its backoff.
        sql("create or replace function team_private.export_now() returns timestamptz language sql volatile set search_path=pg_catalog as $$select clock_timestamp()+interval '301 seconds'$$;")
        assert call('stats_export_claim') is None
        sql("create or replace function team_private.export_now() returns timestamptz language sql volatile set search_path=pg_catalog as $$select clock_timestamp()+interval '400 seconds'$$;")
        fixture.mode='success'
        result=worker.run_once(SQLBackend(),worker.GoogleSheets(fixture.config()))
        assert result==[dict(job_id=job_id,state='delivered')]
        assert len(fixture.batches)==1,'Credential renewal caused another provider write'
    finally:fixture.close()
    final=json.loads(sql('select to_jsonb(d) from public.stat_export_deliveries d'))
    assert final['state']=='delivered' and final['queue_state']=='settled'
    assert (final['spreadsheet_id'],final['sheet_id'],final['ledger_row'])==(reservation['spreadsheet_id'],reservation['sheet_id'],reservation['ledger_row'])
    sql('begin;set local role teamstats_export_worker;set local request.jwt.claims='+quote(json.dumps(claims))+";do $$begin begin perform public.stats_export_claimed_reserve('"+job_id+"','"+first['claim_token']+"');raise exception 'Expected stale claim';exception when sqlstate 'PT409' then null;end;end$$;rollback;")
    # Re-run the migration with a unique synthetic role name, then roll back.
    # This exercises the real migration boundary without colliding with its
    # already-created cluster role or retaining additional roles/memberships.
    migration=(Path(__file__).parents[1]/'migrations/202610170003_export_worker_identity.sql').read_text()
    candidate='synthetic_export_'+uuid.uuid4().hex
    rollback=migration.replace('teamstats_export_worker',candidate).rsplit('commit;',1)[0]+'rollback;'
    sql(rollback)  # Clean-control execution proves the candidate is otherwise valid.
    sql('grant select(name) on public.teams to public;')
    column_acl=sql("select attacl::text from pg_attribute where attrelid='public.teams'::regclass and attname='name'")
    assert sql("select not has_table_privilege('anon','public.teams','SELECT') and has_any_column_privilege('anon','public.teams','SELECT')")=='t'
    try:sql(rollback)
    except RuntimeError:pass
    else:raise AssertionError('PUBLIC column-only access bypassed the migration guard')
    assert sql("select not exists(select 1 from pg_roles where rolname="+quote(candidate)+")")=='t'
    assert sql("select attacl::text from pg_attribute where attrelid='public.teams'::regclass and attname='name'")==column_acl
    sql('revoke select(name) on public.teams from public;')  # Only this fixture's injected grant.
    # The exact source migration must refuse a role-name collision atomically.
    snapshot=pg.snapshot(target)
    try:sql((Path(__file__).parents[1]/'migrations/202610170003_export_worker_identity.sql').read_text())
    except RuntimeError:pass
    else:raise AssertionError('Existing role collision was adopted')
    assert pg.snapshot(target)==snapshot and pg.snapshot(source)==before
    print('PASS: exact4 RPC ACL; no broader effective authority; malformed/expired claims; concurrent1of8; service compatibility; denial-after-applied-write; lease/backoff/renewal readback1write; stale/collision denial; source preserved. Signed ingress and hosted activation unverified.')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);g=p.add_mutually_exclusive_group(required=True)
    g.add_argument('--pg-bin',type=Path);g.add_argument('--container');p.add_argument('--recovery-output',type=Path,required=True)
    a=p.parse_args();verify(IsolatedPostgres(a.recovery_output,a.pg_bin,a.container),a.recovery_output)
