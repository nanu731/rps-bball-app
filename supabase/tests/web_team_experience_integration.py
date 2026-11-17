"""Synthetic public RPC/RLS checks; Auth stand-ins, not signed-user evidence."""
import json
import uuid


def run(sql):
    uid = lambda: str(uuid.uuid4())
    owner, coach, manager, player, outsider = [uid() for _ in range(5)]
    team = uid()
    sessions = {a: uid() for a in [owner, coach, manager, player, outsider]}
    for actor, session in sessions.items():
        sql(f"insert into auth.users(id,email,email_confirmed_at) values('{actor}','test-only-{actor}@example.invalid',now());insert into auth.sessions(id,user_id) values('{session}','{actor}');")
    sql(f"insert into public.teams(id,name,owner_auth_uuid) values('{team}','TEST ONLY finished experience','{owner}');")
    for actor in [coach, manager, player]:
        sql(f"insert into public.team_memberships(team_id,user_id,status) values('{team}','{actor}','active');")
    def value(v):
        if v is None: return 'null'
        if isinstance(v, bool): return str(v).lower()
        if isinstance(v, (int, float)): return str(v)
        if isinstance(v, (dict, list)): return "'"+json.dumps(v).replace("'","''")+"'::jsonb"
        return "'"+str(v).replace("'","''")+"'"
    def rpc(actor, name, **args):
        claims = json.dumps({'sub':actor,'session_id':sessions[actor],'exp':4102444800,'role':'authenticated'})
        text = sql("begin;set local role authenticated;set local request.jwt.claims='"+claims+"';select public."+name+'('+','.join(k+'=>'+value(v) for k,v in args.items())+');commit;')
        lines=text.splitlines()
        try: return json.loads(lines[-1]) if lines else None
        except json.JSONDecodeError: return lines[-1]
    def denied(name, fn):
        try: fn()
        except RuntimeError as error:
            assert '42501' in str(error), 'Expected authorization denial, not another SQL failure'
            print('PASS '+name, flush=True)
            return
        raise AssertionError('Expected denial: '+name)
    game_args=dict(p_team_id=team,p_game_id=uid(),p_date='2037-01-01',p_opponent='TEST ONLY opponent',p_home_away='home',p_game_type='regularSeason')
    denied('active player cannot create a game by direct RPC', lambda: rpc(player,'stats_create_game',**game_args))
    def access(actor): return rpc(actor,'team_access',p_team_id=team)
    def preset(actor, role):
        return rpc(owner,'team_apply_staff_preset',p_team_id=team,p_user_id=actor,p_role=role,p_expected_access_revision=access(owner)['access_revision'])
    preset(coach,'coach');preset(manager,'manager')
    assert access(coach)['capabilities']==access(manager)['capabilities']
    assert access(coach)['can_propose_stats'] and not access(player)['can_propose_stats']
    print('PASS coach and manager presets have identical plan/stat capabilities, player is read-only',flush=True)
    denied('player cannot grant a staff preset',lambda:rpc(player,'team_apply_staff_preset',p_team_id=team,p_user_id=player,p_role='coach',p_expected_access_revision=access(owner)['access_revision']))
    game=rpc(coach,'stats_create_game',**game_args)
    denied('outsider cannot open a team draft',lambda:rpc(outsider,'stats_open_draft',p_team_id=team,p_game_id=game['id'],p_dataset_type='box_scores'))
    denied('player cannot open a draft',lambda:rpc(player,'stats_open_draft',p_team_id=team,p_game_id=game['id'],p_dataset_type='box_scores'))
    roster=rpc(owner,'team_save_roster',p_team_id=team,p_display_name='TEST ONLY player',p_jersey_number='0',p_expected_access_revision=access(owner)['access_revision'])
    version=rpc(coach,'stats_open_draft',p_team_id=team,p_game_id=game['id'],p_dataset_type='box_scores')
    records=[dict(gameID=game['id'],playerID=roster,values={'points':0,'assists':None})]
    version=rpc(coach,'stats_save_draft',p_team_id=team,p_version_id=version['id'],p_expected_revision=version['revision'],p_records=records,p_covered_roster=[dict(id=roster,version=1)])
    for name,args in [('stats_save_draft',dict(p_records=records,p_covered_roster=[dict(id=roster,version=1)])),('stats_complete',dict(p_confirm_roster=True)),('stats_submit',{})]:
        denied('player denied '+name,lambda name=name,args=args:rpc(player,name,p_team_id=team,p_version_id=version['id'],p_expected_revision=version['revision'],**args))
    version=rpc(coach,'stats_complete',p_team_id=team,p_version_id=version['id'],p_expected_revision=version['revision'],p_confirm_roster=True)
    version=rpc(coach,'stats_submit',p_team_id=team,p_version_id=version['id'],p_expected_revision=version['revision'])
    denied('player cannot verify stats',lambda:rpc(player,'stats_review',p_team_id=team,p_version_id=version['id'],p_expected_revision=version['revision'],p_approve=True))
    accepted=rpc(coach,'stats_review',p_team_id=team,p_version_id=version['id'],p_expected_revision=version['revision'],p_approve=True)
    assert accepted['review_actor_user_id']==coach==accepted['author_user_id'] and accepted['records'][0]['values']['points']==0 and accepted['records'][0]['values']['assists'] is None
    print('PASS authorized self-review retains author/verifier and missing versus zero',flush=True)
    denied('player cannot request corrections',lambda:rpc(player,'stats_request_edit',p_team_id=team,p_source_version_id=accepted['id'],p_expected_revision=accepted['revision'],p_reason='TEST ONLY denied'))
    req=rpc(coach,'stats_request_edit',p_team_id=team,p_source_version_id=accepted['id'],p_expected_revision=accepted['revision'],p_reason='TEST ONLY correction')
    correction=rpc(manager,'stats_review_edit',p_team_id=team,p_request_id=req['id'],p_expected_revision=req['revision'],p_approve=True)['version']
    assert correction['base_published_version_id']==accepted['id']
    correction=rpc(coach,'stats_complete',p_team_id=team,p_version_id=correction['id'],p_expected_revision=correction['revision'],p_confirm_roster=True)
    correction=rpc(coach,'stats_publish',p_team_id=team,p_version_id=correction['id'],p_expected_revision=correction['revision'])
    assert correction['review_actor_user_id']==coach
    print('PASS direct author publication also records verifier; correction retains lineage',flush=True)
    rpc(owner,'team_link_player_account',p_team_id=team,p_user_id=player,p_player_id=roster,p_expected_access_revision=access(owner)['access_revision'])
    claims=json.dumps({'sub':player,'session_id':sessions[player],'exp':4102444800,'role':'authenticated'})
    own=sql("begin;set local role authenticated;set local request.jwt.claims='"+claims+"';select player_id from public.team_player_accounts where team_id='"+team+"';commit;")
    assert roster in own
    print('PASS player account link RLS is usable without exposing private actor helper',flush=True)
    denied('player cannot link accounts',lambda:rpc(player,'team_link_player_account',p_team_id=team,p_user_id=manager,p_player_id=roster,p_expected_access_revision=access(owner)['access_revision']))
    season=uid()
    denied('manager cannot change owner season setup',lambda:rpc(manager,'team_save_season',p_team_id=team,p_season_id=season,p_name='TEST ONLY denied',p_expected_access_revision=access(manager)['access_revision']))
    rpc(owner,'team_save_season',p_team_id=team,p_season_id=season,p_name='TEST ONLY explicit season',p_expected_access_revision=access(owner)['access_revision'])
    assert rpc(player,'web_results',p_team_id=team,p_season_id=season)['games']==[]
    rpc(owner,'team_assign_season_game',p_team_id=team,p_season_id=season,p_game_id=game['id'],p_expected_season_id=None,p_expected_access_revision=access(owner)['access_revision'])
    results=rpc(player,'web_results',p_team_id=team,p_season_id=season)
    assert len(results['games'])==1 and len(results['versions'])==1 and results['versions'][0]['id']==correction['id']
    assert results['versions'][0]['records'][0]['values']=={'points':0,'assists':None} and 'author_user_id' not in results['versions'][0]
    denied('outsider cannot read season results',lambda:rpc(outsider,'web_results',p_team_id=team,p_season_id=season))
    # Same UUID belonging to another team cannot be renamed through this team.
    other_team,other_season=uid(),uid()
    sql(f"insert into public.teams(id,name,owner_auth_uuid) values('{other_team}','TEST ONLY other season team','{owner}');")
    rpc(owner,'team_save_season',p_team_id=other_team,p_season_id=other_season,p_name='TEST ONLY retained other season',p_expected_access_revision=rpc(owner,'team_access',p_team_id=other_team)['access_revision'])
    denied('cross-team season UUID cannot be overwritten',lambda:rpc(owner,'team_save_season',p_team_id=team,p_season_id=other_season,p_name='TEST ONLY denied overwrite',p_expected_access_revision=access(owner)['access_revision']))
    print('PASS explicit season results use current accepted pointers once and preserve missing values',flush=True)
    practice=uid()
    document={'schema':1,'session':{'id':practice,'kind':'practice','title':'TEST ONLY independently shared plan','date':'2037-01-01','venue':'home','season':'regularSeason','players':[],'spots':['TEST ONLY spot '+str(n) for n in range(1,10)],'protocol':'TEST ONLY protocol','plan':[{'id':uid(),'name':'TEST ONLY drill','minutes':'','instructions':'TEST ONLY instructions'}],'shooting':{},'ft':{},'observations':[],'changes':[],'savedAt':'2037-01-01T00:00:00.000Z'}}
    def command(actor,action,revision,doc=None,arg=None):
        return rpc(actor,'web_session_command',p_team_id=team,p_operation_id=uid(),p_action=action,p_session_id=practice,p_expected_revision=revision,p_expected_access_revision=access(actor)['access_revision'],p_document=doc,p_argument=arg or {})
    state=command(manager,'create',0,document)
    op=uid();args=dict(p_team_id=team,p_practice_id=practice,p_operation_id=op,p_expected_revision=state['session']['revision'])
    denied('player cannot share a builder plan',lambda:rpc(player,'web_plan_share',**args))
    shared=rpc(manager,'web_plan_share',**args)
    assert rpc(manager,'web_plan_share',**args)==shared
    listing=rpc(player,'web_plan_list',p_team_id=team,p_practice_id=practice)
    assert len(listing)==1 and listing[0]['is_current'] and listing[0]['operation_id'] is None
    assert set(listing[0]['builder'])=={'title','date','plan','protocol','spots'}
    assert state['session']['accepted_snapshot_id'] is None
    assert rpc(manager,'web_plan_list',p_team_id=team,p_practice_id=practice)[0]['operation_id']==op
    denied('outsider cannot read early shared plan',lambda:rpc(outsider,'web_plan_list',p_team_id=team,p_practice_id=practice))
    denied('player cannot reserve practice PDF bytes',lambda:rpc(player,'file_reserve',p_team_id=team,p_resource_id=uid(),p_kind='practice_plan',p_target_id=practice,p_operation_id=uid(),p_declared_bytes=100,p_title='TEST ONLY denied PDF'))
    document['session']['plan'][0]['instructions']='TEST ONLY revised instructions'
    state=command(manager,'save',state['session']['revision'],document,{'assignment_revision':state['session']['assignment_revision']})
    rpc(manager,'web_plan_share',p_team_id=team,p_practice_id=practice,p_operation_id=uid(),p_expected_revision=state['session']['revision'])
    listing=rpc(player,'web_plan_list',p_team_id=team,p_practice_id=practice)
    assert len(listing)==2 and listing[0]['is_current'] and not listing[1]['is_current'] and listing[1]['builder']['plan'][0]['instructions']=='TEST ONLY instructions'
    print('PASS builder sharing is idempotent, versioned, team-only and independent of statistical publication',flush=True)
    rpc(owner,'team_set_capability',p_team_id=team,p_user_id=manager,p_capability='members.manage',p_enabled=True,p_expected_access_revision=access(owner)['access_revision'])
    denied('player preset rejects remaining administration authority',lambda:preset(manager,'player'))
    rpc(owner,'team_set_capability',p_team_id=team,p_user_id=manager,p_capability='members.manage',p_enabled=False,p_expected_access_revision=access(owner)['access_revision'])
    preset(manager,'player')
    assert not access(manager)['can_propose_stats']
    denied('demoted manager cannot write a new game',lambda:rpc(manager,'stats_create_game',**dict(game_args,p_game_id=uid())))
    sql(f"update public.team_memberships set status='removed' where team_id='{team}' and user_id='{coach}';")
    denied('removed staff member denied current access',lambda:access(coach))

if __name__ == '__main__':
    import argparse, re, sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from recovery_drill import IsolatedPostgres
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--pg-bin',type=Path);group.add_argument('--container')
    parser.add_argument('--recovery-output',type=Path,required=True)
    args=parser.parse_args()
    proof=json.loads((args.recovery_output/'receipt.json').read_text());source=proof['restored']
    assert proof.get('hostedRecovery') is False and proof.get('restoredRowsAndPoliciesEqual')
    assert re.fullmatch(r'teamstats_recovery_restored_[a-f0-9]{32}',source)
    pg=IsolatedPostgres(args.recovery_output,args.pg_bin,args.container)
    before=pg.snapshot(source);target='teamstats_web_permissions_'+uuid.uuid4().hex
    pg.run('createdb',['--template',source,target])
    def sql(text):
        try:return pg.sql(target,'\\set VERBOSITY verbose\n'+text)
        except RuntimeError:
            diagnostic=(args.recovery_output/'diagnostics.local.log').read_text()
            codes=re.findall(r'ERROR:  ([0-9A-Z]{5}):',diagnostic)
            raise RuntimeError('SQLSTATE '+(codes[-1] if codes else 'unknown')) from None
    run(sql)
    assert pg.snapshot(source)==before
    print('Synthetic web permission contracts passed; original recovery fixture preserved.')
