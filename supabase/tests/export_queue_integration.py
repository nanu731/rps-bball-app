"""Real queue RPCs only in a new clone of the isolated synthetic recovery fixture."""
import argparse
import datetime as dt
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import sys
import uuid
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from recovery_drill import IsolatedPostgres


def verify(pg, output):
    receipt = json.loads((output / 'receipt.json').read_text())
    source = receipt['restored']
    if receipt.get('hostedRecovery') is not False or not re.fullmatch(r'teamstats_recovery_restored_[a-f0-9]{32}',source):
        raise ValueError('Synthetic recovery receipt required')
    if pg.sql(source,"select count(*)=1 and bool_and(name='TEST ONLY recovery team') from public.teams") != 't':
        raise ValueError('Synthetic team required')
    target='teamstats_export_'+uuid.uuid4().hex
    pg.run('createdb',['--template',source,target])
    def sql(text): return pg.sql(target,text)
    def rpc(name,args=''):
        raw=sql('begin; set local role service_role; select public.'+name+'('+args+'); commit;')
        return json.loads(raw) if raw and raw != 'null' else None
    # Upgrade an OLD synthetic schema separately; no existing application database is migrated.
    upgrade='teamstats_export_upgrade_'+uuid.uuid4().hex
    pg.run('createdb',['--template','template0',upgrade])
    root=Path(__file__).resolve().parents[2]
    pg.sql(upgrade,(root/'supabase/tests/recovery_platform.sql').read_text())
    migration=root/'supabase/migrations/202610170001_export_scheduling.sql'
    for path in sorted((root/'supabase/migrations').glob('*.sql')):
        if path!=migration:pg.sql(upgrade,path.read_text())
    pg.sql(upgrade,(root/'supabase/tests/recovery_records.sql').read_text())
    pg.sql(upgrade,"begin;set local role service_role;select public.stats_export_configure('f3000000-0000-4000-8000-000000000001','SYNTHETIC_UPGRADE',0,100,1000,1000);select public.stats_export_reserve('f8000000-0000-4000-8000-000000000001');select public.stats_export_fail('f8000000-0000-4000-8000-000000000001','destination_conflict');commit;")
    old_rows=json.loads(pg.sql(upgrade,'select jsonb_agg(to_jsonb(d)) from public.stat_export_deliveries d'))
    pg.sql(upgrade,migration.read_text())
    new_rows=json.loads(pg.sql(upgrade,'select jsonb_agg(to_jsonb(d)) from public.stat_export_deliveries d'))
    assert new_rows[0]['queue_state']=='manual_review','Old permanent failures became automatically retryable'
    for key in ['job_id','team_id','spreadsheet_id','sheet_id','ledger_row','attempts','state','error_code']:
        assert old_rows[0][key]==new_rows[0][key],'Upgrade changed historical delivery identity/evidence'
    before=pg.snapshot(source)
    team='f3000000-0000-4000-8000-000000000001'
    def quote(value): return "'"+str(value).replace("'","''")+"'"
    def value(v):
        if v is None:return 'null'
        if isinstance(v,dict):return quote(json.dumps(v))+'::jsonb'
        return str(v) if isinstance(v,int) else quote(v)
    def call(name,**args):return rpc(name,','.join(k+'=>'+value(v) for k,v in args.items()))
    def args(c):return dict(p_job_id=c['job_id'],p_claim_token=c['claim_token'])
    def refused(name,arguments,code='PT409',role='service_role'):
        expression='public.'+name+'('+','.join(k+'=>'+value(v) for k,v in arguments.items())+')'
        sql("begin; set local role "+role+"; do $$begin perform "+expression+"; raise exception 'Expected refusal'; exception when sqlstate '"+code+"' then null; end$$; commit;")
    claims=json.dumps(dict(sub='f1000000-0000-4000-8000-000000000001',session_id='f2000000-0000-4000-8000-000000000001',exp=4102444800))
    def status():
        return json.loads(sql("begin;set local role authenticated;set local request.jwt.claims="+quote(claims)+";select public.stats_export_status('"+team+"');commit;"))
    now=[dt.datetime.fromisoformat(sql('select clock_timestamp()'))+dt.timedelta(seconds=1)]
    def advance(seconds=0):
        now[0]+=dt.timedelta(seconds=seconds)
        sql("create or replace function team_private.export_now() returns timestamptz language sql volatile set search_path=pg_catalog as $$select "+quote(now[0].isoformat())+"::timestamptz$$;")
    advance()
    sql('create or replace function team_private.export_jitter() returns double precision language sql volatile set search_path=pg_catalog as $$select 0::double precision$$;')
    refused('stats_export_claim',{},'42501','authenticated')
    refused('stats_export_claim',{},'42501','anon')
    rpc('stats_export_configure',"'%s','SYNTHETIC_EXPORT',0,100,1000,1000"%team)
    claim=rpc('stats_export_claim');assert claim is not None
    reservation=call('stats_export_claimed_reserve',**args(claim))
    assert json.loads(reservation['payload_text'])['records'][0]['values']['points']==0
    call('stats_export_record_failure',**args(claim),p_error_code='provider_timeout',p_retry_after=120)
    assert rpc('stats_export_claim') is None, 'Retry before persisted deadline'
    # A new psql process/connection on every call is restart-independent.
    state=status()[0];assert state['queue_state']=='ready' and state['retry_attempts']==1
    advance(119);assert rpc('stats_export_claim') is None
    advance(1);second=rpc('stats_export_claim');assert second['job_id']==claim['job_id']
    refused('stats_export_claimed_reserve',args(claim))
    again=call('stats_export_claimed_reserve',**args(second));assert again['sheet_id']==reservation['sheet_id']
    call('stats_export_record_failure',**args(second),p_error_code='destination_conflict')
    assert status()[0]['queue_state']=='manual_review'
    assert rpc('stats_export_claim') is None
    refused('stats_export_resume',dict(p_job_id=claim['job_id']),'42501','authenticated')
    call('stats_export_resume',p_job_id=claim['job_id'])
    fresh=rpc('stats_export_claim');assert fresh['claim_token']!=second['claim_token']
    call('stats_export_record_failure',**args(fresh),p_error_code='provider_http_429',p_retry_after=86401)
    assert status()[0]['queue_state']=='manual_review'
    refused('stats_export_resume',dict(p_job_id=claim['job_id']))
    call('stats_export_resume',p_job_id=claim['job_id'],p_provider_pause_resolved=True)
    advance(86401)
    for attempt in range(5):
        c=rpc('stats_export_claim');assert c is not None
        call('stats_export_record_failure',**args(c),p_error_code='provider_transport',p_retry_after=None)
        if attempt<4:
            assert rpc('stats_export_claim') is None
            advance(15*(2**attempt))
    state=status()[0]
    assert state['queue_state']=='manual_review' and state['last_review_reason']=='retry_exhausted'
    assert state['retry_attempts']==5 and state['claim_total']==8 and state['review_cycles']==2
    call('stats_export_resume',p_job_id=claim['job_id'])
    expired=rpc('stats_export_claim');advance(301)
    assert rpc('stats_export_claim') is None, 'Expired claim skipped backoff'
    refused('stats_export_record_failure',dict(args(expired),p_error_code='provider_timeout'))
    advance(15);current=rpc('stats_export_claim');assert current is not None
    refused('stats_export_acknowledge',dict(args(expired),p_receipt={}))
    call('stats_export_record_failure',**args(current),p_error_code='configuration_invalid')
    # New accepted snapshots pass the actual publication commands; drafts stay out.
    def accepted():
        game=str(uuid.uuid4())
        payload=json.dumps([dict(gameID=game,playerID='f4000000-0000-4000-8000-000000000001',values=dict(points=None,assists=0))])
        sql("begin;set local role authenticated;set local request.jwt.claims="+quote(claims)+";do $$declare v jsonb;begin perform public.stats_create_game('"+team+"','"+game+"','2037-01-01','TEST ONLY queue','home','regularSeason');v:=public.stats_open_draft('"+team+"','"+game+"','box_scores');v:=public.stats_save_draft('"+team+"',(v->>'id')::uuid,(v->>'revision')::bigint,"+quote(payload)+"::jsonb,'[{\"id\":\"f4000000-0000-4000-8000-000000000001\",\"version\":1}]'::jsonb);v:=public.stats_complete('"+team+"',(v->>'id')::uuid,(v->>'revision')::bigint,true);perform public.stats_publish('"+team+"',(v->>'id')::uuid,(v->>'revision')::bigint);end$$;commit;")
        return next(x for x in status() if x['game_id']==game)['job_id']
    other=accepted()
    with ThreadPoolExecutor(max_workers=8) as pool: replies=list(pool.map(lambda _:rpc('stats_export_claim'),range(8)))
    granted=[x for x in replies if x is not None];assert len(granted)==1 and granted[0]['job_id']==other
    call('stats_export_record_failure',**args(granted[0]),p_error_code='provider_timeout',p_retry_after=120)
    unrelated=accepted();next_job=rpc('stats_export_claim');assert next_job['job_id']==unrelated,'Delayed failure starved unrelated work'
    call('stats_export_record_failure',**args(next_job),p_error_code='destination_capacity')
    # Expired whole retry window is never claimed again automatically.
    advance(8*86400);assert rpc('stats_export_claim') is None
    assert all(x['queue_state']=='manual_review' for x in status())
    call('stats_export_resume',p_job_id=claim['job_id'])
    advance(7*86400-1);boundary=rpc('stats_export_claim');assert boundary is not None
    advance(2);refused('stats_export_claimed_reserve',args(boundary))
    assert rpc('stats_export_claim') is None
    throttled=accepted()
    sql("update public.stat_export_deliveries set cycle_started_at=team_private.export_now(),next_attempt_at=team_private.export_now() where job_id="+quote(throttled))
    throttled_claim=rpc('stats_export_claim')
    call('stats_export_record_failure',**args(throttled_claim),p_error_code='provider_http_429',p_retry_after=120)
    pending=accepted()
    sql("update public.stat_export_deliveries set cycle_started_at=team_private.export_now(),next_attempt_at=team_private.export_now() where job_id="+quote(pending))
    assert rpc('stats_export_claim') is None,'A restarted worker bypassed provider cooldown via another job'
    advance(120)
    for _ in range(2):
        c=rpc('stats_export_claim');assert c is not None
        call('stats_export_record_failure',**args(c),p_error_code='destination_conflict')
    # Actual Python worker + actual queue RPCs; Google remains a loopback protocol fixture.
    import sheets_export as worker
    from test_sheets_export import Fixture
    class SQLBackend:
        def rpc(self,name,arguments):
            result=call(name,**arguments)
            if name=='stats_export_acknowledge': raise worker.ExportError('backend_transport')
            return result
    final=accepted()
    # Newly created delivery uses real DB time by default; align only this synthetic fixture.
    sql("update public.stat_export_deliveries set cycle_started_at=team_private.export_now(),next_attempt_at=team_private.export_now() where job_id="+quote(final))
    fixture=Fixture('timeout_applied')
    try:
        result=worker.run_once(SQLBackend(),worker.GoogleSheets(fixture.config(timeout=.03)))
        assert result==[dict(job_id=final,state='delivered')]
        assert len(fixture.batches)==1
    finally:fixture.server.shutdown();fixture.server.server_close()
    final_status=next(x for x in status() if x['job_id']==final)
    assert final_status['state']=='delivered' and final_status['queue_state']=='settled'
    refused('stats_export_reserve',dict(p_job_id=final),'42501')
    refused('stats_export_finish',dict(p_job_id=final,p_receipt={}),'42501')
    refused('stats_export_fail',dict(p_job_id=final,p_error_code='provider_timeout'),'42501')
    assert pg.snapshot(source)==before,'Original synthetic source changed'
    print('PASS: durable due/restart; RetryAfter; caps/manualresume; expired/stale claims; concurrent1of8; starvation; real SQL/worker timeout-applied readback; legacy denial; source preserved')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    tools=parser.add_mutually_exclusive_group(required=True)
    tools.add_argument('--pg-bin',type=Path);tools.add_argument('--container')
    parser.add_argument('--recovery-output',type=Path,required=True)
    args=parser.parse_args()
    verify(IsolatedPostgres(args.recovery_output,args.pg_bin,args.container),args.recovery_output)
