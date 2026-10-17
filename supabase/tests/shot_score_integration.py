"""Independent score references only in a new guarded synthetic recovery clone."""
import argparse,json,re,sys,uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from recovery_drill import IsolatedPostgres

TEAM='f3000000-0000-4000-8000-000000000001';GAME='f5000000-0000-4000-8000-000000000001'
def verify(pg,recovery_output,apply_migration=False):
    proof=json.loads((recovery_output/'receipt.json').read_text());source=proof['restored']
    assert proof.get('hostedRecovery') is False and proof.get('restoredRowsAndPoliciesEqual') and re.fullmatch(r'teamstats_recovery_restored_[a-f0-9]{32}',source)
    assert pg.sql(source,"select count(*)=1 and bool_and(name='TEST ONLY recovery team') from public.teams")=='t'
    before=pg.snapshot(source);target='teamstats_score_'+uuid.uuid4().hex;pg.run('createdb',['--template',source,target])
    if apply_migration:pg.sql(target,(Path(__file__).parents[1]/'migrations/202610170005_shot_score_reference.sql').read_text())
    literal=lambda v:'null' if v is None else str(v) if isinstance(v,int) else "'"+str(v).replace("'","''")+"'"
    def invoke(actor,name,*values,denied=None):
        claims=json.dumps(dict(sub=f'f1000000-0000-4000-8000-{actor:012}',session_id=f'f2000000-0000-4000-8000-{actor:012}',exp=4102444800))
        call='public.'+name+'('+','.join(map(literal,values))+')';prefix=f"begin;set local role authenticated;set local request.jwt.claims='{claims}';"
        if denied:
            pg.sql(target,prefix+f"do $$begin begin perform {call};raise exception 'Expected denial';exception when sqlstate '{denied}' then null;end;end$$;rollback;")
        else:return json.loads(pg.sql(target,prefix+f"select coalesce(({call})::text,'null');commit;"))
    initial=invoke(1,'shots_score_read',TEAM,GAME);assert initial['revision']==0 and initial['our_points'] is None and initial['opponent_points'] is None
    invoke(3,'shots_score_read',TEAM,GAME,denied='42501')
    batch=str(uuid.uuid4());args=(TEAM,GAME,0,batch,0,None,'TEST ONLY independent scorebook')
    saved=invoke(2,'shots_score_confirm',*args);assert saved['score_revision']==1
    assert invoke(2,'shots_score_confirm',*args)==saved
    assert invoke(2,'shots_score_receipt',TEAM,GAME,batch)==saved
    assert invoke(1,'shots_score_receipt',TEAM,GAME,batch) is None
    invoke(2,'shots_score_confirm',TEAM,GAME,0,batch,1,7,args[-1],denied='PT409')
    invoke(2,'shots_score_confirm',TEAM,GAME,0,str(uuid.uuid4()),0,7,args[-1],denied='PT409')
    reference=invoke(1,'shots_score_read',TEAM,GAME);assert reference['our_points']==0 and reference['opponent_points'] is None
    for our,opponent,note in [(None,None,'TEST ONLY'),(-1,7,'TEST ONLY'),(0,7,'')]:
        invoke(2,'shots_score_confirm',TEAM,GAME,1,str(uuid.uuid4()),our,opponent,note,denied='22023')
    invoke(1,'shots_score_confirm',TEAM,GAME,1,str(uuid.uuid4()),2,7,'TEST ONLY corrected reference')
    assert pg.sql(target,'select count(*) from team_private.shot_score_references')=='2'
    # Recording alone cannot confirm official data; revoked review cannot replay or read receipts.
    pg.sql(target,"update public.capability_grants set revoked_at=now() where capability='stats.review';insert into public.capability_grants(team_id,user_id,capability,issued_by) values('"+TEAM+"','f1000000-0000-4000-8000-000000000002','shots.record','f1000000-0000-4000-8000-000000000001');")
    invoke(2,'shots_score_confirm',*args,denied='42501');invoke(2,'shots_score_receipt',TEAM,GAME,batch,denied='42501')
    assert invoke(2,'shots_score_read',TEAM,GAME)['can_confirm'] is False
    assert pg.sql(target,"select relrowsecurity and not has_table_privilege('authenticated','team_private.shot_score_references','SELECT') from pg_class where oid='team_private.shot_score_references'::regclass")=='t'
    assert pg.snapshot(source)==before
    print('Independent score missing/zero, review-only authority, exact replay, stale/conflict, correction history, revocation and source-preservation checks passed')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);group=parser.add_mutually_exclusive_group(required=True);group.add_argument('--pg-bin',type=Path);group.add_argument('--container');parser.add_argument('--recovery-output',type=Path,required=True)
    args=parser.parse_args();verify(IsolatedPostgres(args.recovery_output,args.pg_bin,args.container),args.recovery_output)
