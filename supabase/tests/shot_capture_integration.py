"""Shot commands ONLY in a new clone of a guarded synthetic recovery fixture."""
import copy
import json
from pathlib import Path
import re
import uuid

TEAM='f3000000-0000-4000-8000-000000000001'
GAME='f5000000-0000-4000-8000-000000000001'

def verify(pg, recovery_output, apply_migration=False):
    receipt=json.loads((recovery_output/'receipt.json').read_text());source=receipt['restored']
    if receipt.get('hostedRecovery') is not False or not receipt.get('restoredRowsAndPoliciesEqual') or not re.fullmatch(r'teamstats_recovery_restored_[a-f0-9]{32}',source):
        raise ValueError('Expected the completed synthetic recovery receipt')
    assert pg.sql(source,"select count(*)=1 and bool_and(name='TEST ONLY recovery team') from public.teams")=='t'
    target='teamstats_shots_'+uuid.uuid4().hex
    pg.run('createdb',['--template',source,target])
    (pg.output/'shot-plan.local.json').write_text(json.dumps({'source':source,'destination':target,'syntheticOnly':True}))
    if apply_migration: pg.sql(target,(Path(__file__).parents[1]/'migrations/202610170004_shot_capture.sql').read_text())
    def command(actor, expression):
        claims=json.dumps({'sub':f'f1000000-0000-4000-8000-{actor:012}','session_id':f'f2000000-0000-4000-8000-{actor:012}','exp':4102444800})
        return json.loads(pg.sql(target,f"begin;set local role authenticated;set local request.jwt.claims='{claims}';select coalesce(({expression})::text,'null');commit;"))
    state=command(1,f"public.shots_state('{TEAM}','{GAME}')")
    assert state['status']=='not_started' and state['document'] is None and state['state_revision']==0
    def literal(value):
        if value is None: return 'null'
        if isinstance(value,bool): return 'true' if value else 'false'
        if isinstance(value,(int,float)): return str(value)
        return "'"+str(value).replace("'","''")+"'"
    def call(actor,name,*values): return command(actor,'public.'+name+'('+','.join(literal(v) for v in values)+')')
    def denied(actor,name,*values,code='42501'):
        claims=json.dumps({'sub':f'f1000000-0000-4000-8000-{actor:012}','session_id':f'f2000000-0000-4000-8000-{actor:012}','exp':4102444800})
        expression='public.'+name+'('+','.join(literal(v) for v in values)+')'
        pg.sql(target,f"begin;set local role authenticated;set local request.jwt.claims='{claims}';do $check$ begin begin perform {expression};raise exception 'Expected denial';exception when sqlstate '{code}' then null;end;end $check$;rollback;")
    uid=lambda n:f'f1000000-0000-4000-8000-{n:012}'
    batch=str(uuid.uuid4())
    denied(1,'shots_assign',TEAM,GAME,uid(2),0,0,batch,'TEST ONLY designation')
    pg.sql(target,f"insert into public.capability_grants(team_id,user_id,capability,issued_by) values('{TEAM}','{uid(2)}','shots.record','{uid(1)}')")
    first=call(1,'shots_assign',TEAM,GAME,uid(2),0,0,batch,'TEST ONLY designation')
    assert first['assignment_revision']==1 and first['state_revision']==1
    assert call(1,'shots_assign',TEAM,GAME,uid(2),0,0,batch,'TEST ONLY designation')==first
    denied(1,'shots_assign',TEAM,GAME,uid(1),0,0,batch,'TEST ONLY designation',code='PT409')
    denied(3,'shots_state',TEAM,GAME)
    denied(2,'shots_assign',TEAM,GAME,uid(2),1,1,str(uuid.uuid4()),'TEST ONLY unauthorized self designation')
    state=call(2,'shots_state',TEAM,GAME)
    assert state['can_record'] and not state['can_review'] and state['document'] is None
    second=call(1,'shots_assign',TEAM,GAME,uid(1),1,1,str(uuid.uuid4()),'TEST ONLY explicit handoff')
    assert second['assignment_revision']==2 and second['state_revision']==2
    assert not call(2,'shots_state',TEAM,GAME)['can_record']
    denied(1,'shots_assign',TEAM,GAME,uid(2),1,1,str(uuid.uuid4()),'TEST ONLY stale handoff',code='PT409')
    assert pg.sql(target,'select count(*) from team_private.shot_assignments')=='2'
    capture=str(uuid.uuid4())
    document={'schemaVersion':1,'id':capture,'context':{'gameID':GAME,'teamID':TEAM,'actorID':uid(1),'assignmentRevision':2},
              'players':[{'id':'f4000000-0000-4000-8000-000000000001','name':'TEST ONLY recovery player','number':'0','temporary':False}], 'journal':[]}
    payload=lambda doc:json.dumps(doc,sort_keys=True,separators=(',',':'))
    batch=str(uuid.uuid4())
    registered=call(1,'shots_save',TEAM,GAME,2,2,batch,payload(document),'unknown')
    assert registered['document_revision']==0 and registered['state_revision']==3 and registered['session_id']==capture
    assert call(1,'shots_save',TEAM,GAME,2,2,batch,payload(document),'unknown')==registered
    state=call(1,'shots_state',TEAM,GAME)
    assert state['document']==document and state['status']=='draft'
    assert call(2,'shots_state',TEAM,GAME)['document'] is None
    event={'id':str(uuid.uuid4()),'kind':'freeThrows','team':'opponent','freeThrowAttempts':2,'answers':[]}
    document['journal'].append({'id':str(uuid.uuid4()),'revision':1,'recordedAt':'2037-01-01T00:00:00Z','eventID':event['id'],'after':copy.deepcopy(event)})
    saved=call(1,'shots_save',TEAM,GAME,2,3,str(uuid.uuid4()),payload(document),'partial')
    assert saved['state_revision']==4 and saved['document_revision']==1
    submitted=call(1,'shots_decide',TEAM,GAME,2,4,str(uuid.uuid4()),saved['snapshot_id'],'submit','',None)
    assert submitted['state_revision']==5 and call(1,'shots_state',TEAM,GAME)['status']=='submitted'
    denied(1,'shots_decide',TEAM,GAME,2,5,str(uuid.uuid4()),saved['snapshot_id'],'approve','',None,code='22023')
    assert call(2,'shots_state',TEAM,GAME)['document'] is None
    legacy=pg.sql(target,"select jsonb_agg(to_jsonb(v) order by id) from public.stat_versions v")
    handoff=call(1,'shots_assign',TEAM,GAME,uid(2),2,5,str(uuid.uuid4()),'TEST ONLY manager handoff')
    denied(1,'shots_receipt',TEAM,GAME,registered['batch_id'],code='PT409')
    denied(1,'shots_save',TEAM,GAME,2,2,registered['batch_id'],payload({'schemaVersion':1,'id':capture,'context':{'gameID':GAME,'teamID':TEAM,'actorID':uid(1),'assignmentRevision':2},'players':document['players'],'journal':[]}),'unknown',code='PT409')
    assert handoff['assignment_revision']==3 and handoff['state_revision']==6
    before=copy.deepcopy(event);event['answers']=[{'index':1,'outcome':'made'},{'index':2,'outcome':'missed'}]
    document['journal'].append({'id':str(uuid.uuid4()),'revision':2,'recordedAt':'2037-01-01T00:00:01Z','eventID':event['id'],'before':before,'after':copy.deepcopy(event)})
    batch=str(uuid.uuid4());frozen=payload(document)
    saved=call(2,'shots_save',TEAM,GAME,3,6,batch,frozen,'partial')
    assert saved['state_revision']==7 and saved['document_revision']==2
    assert call(2,'shots_receipt',TEAM,GAME,batch)==saved
    assert call(2,'shots_save',TEAM,GAME,3,6,batch,frozen,'partial')==saved
    denied(2,'shots_save',TEAM,GAME,3,6,batch,frozen+' ','partial',code='PT409')
    denied(1,'shots_save',TEAM,GAME,3,7,str(uuid.uuid4()),frozen,'partial')
    assert call(1,'shots_receipt',TEAM,GAME,batch) is None
    assert pg.sql(target,f"select count(*) from team_private.shot_receipts where batch_id='{batch}'")=='1'
    submitted=call(2,'shots_decide',TEAM,GAME,3,7,str(uuid.uuid4()),saved['snapshot_id'],'submit','',None)
    assert submitted['state_revision']==8
    denied(2,'shots_decide',TEAM,GAME,3,8,str(uuid.uuid4()),saved['snapshot_id'],'approve','',None)
    denied(2,'shots_decide',TEAM,GAME,3,8,str(uuid.uuid4()),saved['snapshot_id'],'publish','',None)
    pg.sql(target,f"""insert into auth.users(id,email,email_confirmed_at) values('{uid(4)}','shot-reviewer@example.invalid',now()),('{uid(5)}','shot-viewer@example.invalid',now());
      insert into auth.sessions(id,user_id,not_after) values('f2000000-0000-4000-8000-000000000004','{uid(4)}',now()+interval '1 day'),('f2000000-0000-4000-8000-000000000005','{uid(5)}',now()+interval '1 day');
      insert into public.team_memberships(team_id,user_id,status) values('{TEAM}','{uid(4)}','active'),('{TEAM}','{uid(5)}','active');
      insert into public.capability_grants(team_id,user_id,capability,issued_by) values('{TEAM}','{uid(4)}','shots.review','{uid(1)}'),('{TEAM}','{uid(2)}','shots.review','{uid(1)}');""")
    denied(2,'shots_decide',TEAM,GAME,3,8,str(uuid.uuid4()),saved['snapshot_id'],'approve','',None)
    reviewed=call(4,'shots_decide',TEAM,GAME,3,8,str(uuid.uuid4()),saved['snapshot_id'],'approve','TEST ONLY independent review',None)
    assert reviewed['state_revision']==9
    assert call(5,'shots_state',TEAM,GAME)['document']==document
    accepted=copy.deepcopy(document)
    field_goal={'id':str(uuid.uuid4()),'kind':'fieldGoal','team':'opponent','location':{'x':0.7,'y':0.2},'basket':'top','answers':[]}
    document['journal'].append({'id':str(uuid.uuid4()),'revision':3,'recordedAt':'2037-01-01T00:00:02Z','eventID':field_goal['id'],'after':copy.deepcopy(field_goal)})
    saved=call(2,'shots_save',TEAM,GAME,3,9,str(uuid.uuid4()),payload(document),'unknown')
    assert saved['state_revision']==10 and call(5,'shots_state',TEAM,GAME)['document']==accepted
    assert call(4,'shots_state',TEAM,GAME)['document']==document
    for mutate in [lambda d:d.pop('schemaVersion'),lambda d:d['journal'][0].update(revision=2),
                   lambda d:d['journal'][0]['after'].update(freeThrowAttempts=-1),
                   lambda d:d['players'][0].update(temporary=True),lambda d:d['journal'][0]['after'].update(location={'x':0,'y':0})]:
        invalid=copy.deepcopy(document);mutate(invalid)
        denied(2,'shots_save',TEAM,GAME,3,10,str(uuid.uuid4()),payload(invalid),'unknown',code='22023')
    # A former branch is preserved as a proposal; only explicit pinned adoption changes the head.
    branch=copy.deepcopy(accepted)
    old=copy.deepcopy(branch['journal'][-1]['after']);new=copy.deepcopy(old);new['answers'][1]['outcome']='made'
    branch['journal'].append({'id':str(uuid.uuid4()),'revision':3,'recordedAt':'2037-01-01T00:00:03Z','eventID':old['id'],'before':old,'after':new})
    denied(1,'shots_save',TEAM,GAME,3,10,str(uuid.uuid4()),payload(branch),'unknown')
    denied(5,'shots_recovery',TEAM,GAME,3,10,str(uuid.uuid4()),payload(branch))
    recovery=call(4,'shots_recovery',TEAM,GAME,3,10,str(uuid.uuid4()),payload(branch))
    assert recovery['state_revision']==11 and call(4,'shots_state',TEAM,GAME)['document']==document
    proposals=call(4,'shots_recoveries',TEAM,GAME);assert len(proposals)==1 and proposals[0]['local_revision']==3 and call(4,'shots_recovery_document',TEAM,GAME,proposals[0]['snapshot_id'])==branch
    denied(4,'shots_decide',TEAM,GAME,3,11,str(uuid.uuid4()),recovery['snapshot_id'],'adopt','TEST ONLY compare overlaps',registered['snapshot_id'],code='PT409')
    adopted=call(4,'shots_decide',TEAM,GAME,3,11,str(uuid.uuid4()),recovery['snapshot_id'],'adopt','TEST ONLY reviewed both branches',saved['snapshot_id'])
    assert adopted['state_revision']==12 and call(4,'shots_state',TEAM,GAME)['document']==branch
    assert call(5,'shots_state',TEAM,GAME)['document']==accepted and call(4,'shots_recoveries',TEAM,GAME)==[]
    # Discovery is metadata-only and traverses a bounded page, not fifty large documents.
    for index in range(51):
        call(1,'shots_recovery',TEAM,GAME,3,12+index,str(uuid.uuid4()),payload(branch))
    page=call(1,'shots_recoveries',TEAM,GAME);assert len(page)==50 and all('document' not in row for row in page)
    tail=call(1,'shots_recoveries',TEAM,GAME,page[-1]['snapshot_id']);assert len(tail)==1 and tail[0]['snapshot_id'] not in [row['snapshot_id'] for row in page]
    # Known revocation denies metadata/receipt as well as writes, without altering retained history.
    pg.sql(target,f"update public.team_memberships set status='removed' where team_id='{TEAM}' and user_id='{uid(2)}'")
    denied(2,'shots_state',TEAM,GAME);denied(2,'shots_receipt',TEAM,GAME,batch)
    pg.sql(target,f"update auth.sessions set not_after=now()-interval '1 second' where user_id='{uid(4)}'")
    denied(4,'shots_state',TEAM,GAME)
    assert pg.sql(target,"select jsonb_agg(to_jsonb(v) order by id) from public.stat_versions v")==legacy
    assert pg.sql(target,"select bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','team_private') and c.relkind='r' and (n.nspname='public' or c.relname like 'shot_%')")=='t'
    print('Shot mixed FT/handoff/receipt/review/accepted-source/validation assertions passed in isolated synthetic clone')


if __name__=='__main__':
    import argparse
    import sys
    sys.path.insert(0,str(Path(__file__).parents[1]))
    from recovery_drill import IsolatedPostgres
    parser=argparse.ArgumentParser(description=__doc__)
    tools=parser.add_mutually_exclusive_group(required=True)
    tools.add_argument('--pg-bin',type=Path);tools.add_argument('--container')
    parser.add_argument('--recovery-output',type=Path,required=True)
    args=parser.parse_args()
    verify(IsolatedPostgres(args.recovery_output,args.pg_bin,args.container),args.recovery_output)
