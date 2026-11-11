"""Synthetic SQL contract checks in an explicitly isolated recovery database.
Auth tables/JWT settings are stand-ins here; signed Auth/browser evidence is separate.
"""
import argparse,json,os,sys,uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]))
from recovery_drill import IsolatedPostgres

def run(pg,database):
    def sql(text):return pg.sql(database,"\\set VERBOSITY verbose\n"+text)
    def uid():return str(uuid.uuid4())
    owner,recorder,reviewer,viewer,outsider=[uid() for _ in range(5)]
    sessions={a:uid() for a in [owner,recorder,reviewer,viewer,outsider]};team,practice=uid(),uid()
    def literal(v):return "'"+json.dumps(v,separators=(',',':')).replace("'","''")+"'::jsonb"
    for actor in sessions:
        sql(f"insert into auth.users(id,email,email_confirmed_at) values('{actor}','test-only-{actor}@example.invalid',now());insert into auth.sessions(id,user_id) values('{sessions[actor]}','{actor}');")
    sql(f"insert into public.teams(id,name,owner_auth_uuid) values('{team}','TEST ONLY web contract','{owner}');")
    for a in [recorder,reviewer,viewer]:sql(f"insert into public.team_memberships(team_id,user_id,status) values('{team}','{a}','active');")
    checks=[]
    def query(actor,expression):
        claims={'sub':actor,'session_id':sessions[actor],'exp':4102444800,'role':'authenticated'}
        return sql('begin;set local role authenticated;set local request.jwt.claims='+literal(claims).removesuffix('::jsonb')+';select '+expression+';rollback;').splitlines()[-1]
    def rpc(actor,name,args):
        expr='public.'+name+'('+','.join(k+'=>'+('null' if v is None else literal(v) if isinstance(v,(dict,list)) else ('true' if v else 'false') if isinstance(v,bool) else str(v) if isinstance(v,(int,float)) else "'"+str(v).replace("'","''")+"'") for k,v in args.items())+')'
        claims={'sub':actor,'session_id':sessions[actor],'exp':4102444800,'role':'authenticated'}
        lines=sql('begin;set local role authenticated;set local request.jwt.claims='+literal(claims).removesuffix('::jsonb')+';select '+expr+';commit;').splitlines()
        result=lines[-1] if lines else ''
        if not result:return None
        try:return json.loads(result)
        except json.JSONDecodeError:return result
    def check(name,ok):
        assert ok,name;checks.append(name);print('PASS '+name,flush=True)
    def unchanged_state():
        return sql("select md5(jsonb_build_array((select jsonb_agg(to_jsonb(x) order by id) from public.web_sessions x),(select jsonb_agg(to_jsonb(x) order by id) from public.web_session_snapshots x),(select jsonb_agg(to_jsonb(x) order by snapshot_id) from public.web_session_publications x),(select jsonb_agg(to_jsonb(x) order by operation_id) from public.web_session_receipts x))::text)")
    def denied(name,fn,code=None):
        before=unchanged_state()
        try:fn()
        except RuntimeError:
            diagnostic=(pg.output/'diagnostics.local.log').read_text();last=[line for line in diagnostic.splitlines() if line.startswith('ERROR:')][-1];assert any(expected in last for expected in ([code] if code else ['42501','22023','PT409'])), 'Unexpected internal SQL failure, not a valid denial';assert unchanged_state()==before, 'Denied command changed retained state';checks.append(name);print('PASS '+name,flush=True);return
        raise AssertionError('Expected denial: '+name)
    def grant(actor,cap,enabled=True):
        access=rpc(owner,'team_access',{'p_team_id':team})
        rpc(owner,'team_set_capability',{'p_team_id':team,'p_user_id':actor,'p_capability':cap,'p_enabled':enabled,'p_expected_access_revision':access['access_revision']})
    def command(actor,action,revision,document=None,arg=None,operation=None):
        access=rpc(actor,'team_access',{'p_team_id':team})
        return rpc(actor,'web_session_command',{'p_team_id':team,'p_operation_id':operation or uid(),'p_action':action,'p_session_id':practice,'p_expected_revision':revision,'p_expected_access_revision':access['access_revision'],'p_document':document,'p_argument':arg or {}})
    for cap in ['sessions.record']:grant(recorder,cap)
    for cap in ['sessions.review','sessions.reopen']:grant(reviewer,cap)
    access=rpc(owner,'team_access',{'p_team_id':team})
    roster=rpc(owner,'team_save_roster',{'p_team_id':team,'p_display_name':'TEST ONLY web player','p_jersey_number':'0','p_expected_access_revision':access['access_revision']})
    player={'id':roster,'name':'TEST ONLY web player','number':'0','version':1}
    doc={'schema':1,'session':{'id':practice,'kind':'practice','title':'TEST ONLY web practice','date':'2037-01-01','venue':'home','season':'regularSeason','players':[player],'spots':['Spot '+str(i) for i in range(1,10)],'protocol':'TEST ONLY observed attempts','plan':[],'shooting':{},'ft':{},'observations':[],'changes':[],'savedAt':'2037-01-01T12:00:00Z'}}
    denied('viewer cannot create via video or baseline membership',lambda:command(viewer,'create',0,doc))
    operation=uid();created=command(owner,'create',0,doc,operation=operation)
    check('create stores one permitted draft',created['session']['revision']==1 and created['session']['status']=='draft')
    duplicate=command(owner,'create',0,doc,operation=operation);check('identical command returns immutable receipt',duplicate==created)
    changed=json.loads(json.dumps(doc));changed['session']['title']='TEST ONLY changed';denied('changed operation reuse conflicts',lambda:command(owner,'create',0,changed,operation=operation))
    check('ordinary member cannot read pending snapshot',query(viewer,f"count(*) from public.web_session_snapshots where session_id='{practice}'")=='0')
    denied('member cannot grant self a capability',lambda:rpc(recorder,'team_set_capability',{'p_team_id':team,'p_user_id':recorder,'p_capability':'sessions.publish','p_enabled':True,'p_expected_access_revision':rpc(recorder,'team_access',{'p_team_id':team})['access_revision']}))
    assigned=command(owner,'assign',1,arg={'recorder_user_id':recorder,'clock_user_id':owner,'assignment_revision':1});check('assignment fences prior recorder',assigned['session']['assignment_revision']==2)
    updated=json.loads(json.dumps(doc));updated['session']['shooting']={roster:{'0':{'made':'0','attempts':'0'},'1':{'made':'','attempts':''}}}
    definitions=json.loads(json.dumps(updated));definitions['session']['protocol']='TEST ONLY unauthorized plan change'
    denied('record-only actor cannot change plan alongside first results',lambda:command(recorder,'save',1,definitions,{'assignment_revision':2}),'42501')
    for null in [False,True]:
        malformed=json.loads(json.dumps(doc));item={'id':uid(),'name':'TEST ONLY plan','minutes':'','instructions':''}
        if null:item['id']=None
        else:item.pop('id')
        malformed['session']['plan']=[item]
        denied('plan identity '+('null' if null else 'missing'),lambda:command(owner,'save',1,malformed,{'assignment_revision':2}),'22023')
    saved=command(recorder,'save',1,updated,{'assignment_revision':2});check('zero and missing remain independent',saved['document']['session']['shooting'][roster]['0']['made']=='0' and saved['document']['session']['shooting'][roster]['1']['made']=='')
    denied('stale snapshot revision conflicts',lambda:command(recorder,'save',1,updated,{'assignment_revision':2}))
    invalid=json.loads(json.dumps(updated));invalid['session']['shooting'][roster]['0']={'made':'2','attempts':'1'}
    denied('invalid makes/attempts rejected atomically',lambda:command(recorder,'save',2,invalid,{'assignment_revision':2}))
    invalid=json.loads(json.dumps(updated));invalid['session']['injected_role']='owner';denied('unknown authority fields rejected',lambda:command(recorder,'save',2,invalid,{'assignment_revision':2}))
    denied('stale assignment rejects record save',lambda:command(recorder,'save',2,updated,{'assignment_revision':1}))
    event={'id':uid(),'kind':'shot','team':'ours','playerID':roster,'x':.5,'y':.5,'value':2,'made':True,'label':'','note':'','at':'2037-01-01T12:00:00Z','period':'P1','clock':60}
    def with_changes(changes):
        result=json.loads(json.dumps(updated));result['session']['changes']=changes;return result
    def change(event,before=None,undo=None):return dict(id=uid(),eventID=event['id'],before=before,after=event,at='2037-01-01T12:00:00Z',**({'undoOf':undo} if undo else {}))
    for field in ['id','kind','team','playerID','x','y','value','made','label','note','at','period','clock']:
        for null in [False,True]:
            bad=dict(event)
            if null:bad[field]=None
            else:bad.pop(field)
            c1=change(event);c1['after']=bad
            denied('required event '+field+(' null' if null else ' omitted'),lambda:command(recorder,'save',2,with_changes([c1]),{'assignment_revision':2}))
    valid_journal=with_changes([change(event)])
    sql("select team_private.web_document('"+team+"','"+practice+"','practice',"+literal(valid_journal)+","+literal(updated)+")")
    check('valid captured journal positive control',True)
    first=change(event);removed={'id':uid(),'eventID':event['id'],'before':event,'after':None,'at':'2037-01-01T12:00:01Z'}
    denied('ordinary removal cannot erase event',lambda:command(recorder,'save',2,with_changes([first,removed]),{'assignment_revision':2}))
    removed['undoOf']=first['id'];resurrected=change(dict(event,period='P2',clock=30,at='2037-01-01T13:00:00Z'))
    denied('reusing an undone event identity cannot retime it',lambda:command(recorder,'save',2,with_changes([first,removed,resurrected]),{'assignment_revision':2}))
    manager=viewer;grant(manager,'sessions.manage')
    new_practice=uid();populated=json.loads(json.dumps(updated));populated['session']['id']=new_practice
    denied('plan-only manager cannot create collected results',lambda:rpc(manager,'web_session_command',{'p_team_id':team,'p_operation_id':uid(),'p_action':'create','p_session_id':new_practice,'p_expected_revision':0,'p_expected_access_revision':rpc(manager,'team_access',{'p_team_id':team})['access_revision'],'p_document':populated,'p_argument':{}}))
    check('legacy scouting and shot capabilities retained',sql("select array['scouting.upload','scouting.read','shots.record','shots.review','shots.publish'] <@ team_private.capabilities()")=='t')
    c=command(owner,'clock_set',assigned['session']['clock_revision'],arg={'assignment_revision':2,'period':'TEST ONLY period','seconds':60});check('clock separate from document revision',c['session']['clock_revision']==assigned['session']['clock_revision']+1 and c['session']['revision']==2)
    started=command(owner,'clock_start',c['session']['clock_revision'],arg={'assignment_revision':2});sql('select pg_sleep(0.03)');stopped=command(owner,'clock_stop',started['session']['clock_revision'],arg={'assignment_revision':2});check('clock stop preserves fractional elapsed time',0<float(stopped['session']['clock_seconds'])<60)
    denied('unassigned recorder cannot control clock',lambda:command(recorder,'clock_set',3,arg={'assignment_revision':2,'period':'P1','seconds':10}))
    submit=command(recorder,'submit',2);check('submission freezes exact draft',submit['session']['status']=='submitted' and submit['session']['revision']==3)
    denied('frozen draft cannot be overwritten',lambda:command(recorder,'save',3,updated,{'assignment_revision':2}))
    denied('review requires explicit approve answer',lambda:command(reviewer,'review',3),'22023')
    accepted=command(reviewer,'review',3,arg={'approve':True});accepted_id=accepted['session']['accepted_snapshot_id'];check('independent review preserves accepted pointer',accepted['session']['status']=='published' and bool(accepted_id))
    check('ordinary member can read accepted snapshot only',query(viewer,f"count(*) from public.web_session_snapshots where session_id='{practice}'")=='1')
    requested=command(recorder,'request_edit',4);reopened=command(reviewer,'reopen',5);check('approved correction preserves publication',reopened['session']['status']=='draft' and reopened['session']['base_accepted_snapshot_id']==accepted_id and reopened['session']['accepted_snapshot_id']==accepted_id)
    op=uid();saved_again=command(recorder,'save',6,updated,{'assignment_revision':3},operation=op);check('receipt lookup recovers committed reply',rpc(recorder,'web_session_receipt',{'p_team_id':team,'p_operation_id':op})==saved_again)
    rejected_submission=command(recorder,'submit',7);command(reviewer,'review',8,arg={'approve':False});grant(viewer,'sessions.record');command(viewer,'request_edit',9);command(reviewer,'reopen',10)
    check('old unpublished snapshot concealed after proposal reassignment',query(recorder,f"count(*) from public.web_session_snapshots where id='{saved_again['session']['current_snapshot_id']}'")=='0')
    hidden_receipt=rpc(recorder,'web_session_receipt',{'p_team_id':team,'p_operation_id':op});check('receipt lookup strips currently denied document',hidden_receipt['document'] is None and hidden_receipt['visibility']=='metadata_only')
    replay=command(recorder,'save',6,updated,{'assignment_revision':3},operation=op);check('same-ID replay also strips denied document',replay['document'] is None)
    denied('raw receipt table cannot bypass document visibility',lambda:query(recorder,"count(*) from public.web_session_receipts"))
    grant(recorder,'sessions.record',False);denied('revoked capability cannot recover old receipt',lambda:rpc(recorder,'web_session_receipt',{'p_team_id':team,'p_operation_id':op}))
    denied('outsider cannot call team commands',lambda:command(outsider,'clock_set',3,arg={'assignment_revision':3,'period':'P1','seconds':0}))
    check('no direct client table writes',query(viewer,"has_table_privilege(current_user,'public.web_sessions','INSERT')")=='f')
    check('all new tables protected by RLS',sql("select bool_and(relrowsecurity) from pg_class where oid in ('public.web_sessions'::regclass,'public.web_session_snapshots'::regclass,'public.web_session_publications'::regclass,'public.web_session_receipts'::regclass)")=='t')
    return {'checks':checks,'count':len(checks),'evidence':'isolated SQL with Auth platform stand-ins; not signed Auth or hosted acceptance','syntheticOnly':True}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--pg-bin',type=Path,required=True);p.add_argument('--database',required=True);p.add_argument('--evidence',type=Path,required=True);a=p.parse_args();a.evidence.parent.mkdir(parents=True,exist_ok=True)
    result=run(IsolatedPostgres(a.evidence.parent,a.pg_bin,None),a.database);a.evidence.write_text(json.dumps(result,indent=2)+'\n');a.evidence.chmod(0o600);print('Web SQL contract checks:',result['count'])
