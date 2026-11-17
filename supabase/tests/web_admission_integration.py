"""Synthetic admission RPC/RLS checks. Platform stand-ins, not hosted evidence."""
import json
import uuid

def run(sql):
    uid=lambda:str(uuid.uuid4())
    owner,applicant,second,unverified,member,legacy,declined,banned,revoked=[uid() for _ in range(9)];team=uid();sessions={a:uid() for a in [owner,applicant,second,unverified,member,legacy,declined,banned,revoked]}
    for actor,session in sessions.items():
        confirmed='null' if actor==unverified else 'now()'
        sql(f"insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values('{actor}','test-only-{actor}@example.invalid',{confirmed},'{{\"role\":\"owner\",\"is_owner\":true}}');insert into auth.sessions(id,user_id) values('{session}','{actor}');")
    sql(f"insert into public.teams(id,name,owner_auth_uuid) values('{team}','TEST ONLY admission team','{owner}');insert into public.team_memberships(team_id,user_id,status) values('{team}','{member}','active');")
    def value(v):
        if v is None:return 'null'
        if isinstance(v,bool):return str(v).lower()
        if isinstance(v,int):return str(v)
        return "'"+str(v).replace("'","''")+"'"
    def rpc(actor,name,read_only=False,**args):
        claims=json.dumps({'sub':actor,'session_id':sessions[actor],'exp':4102444800,'role':'authenticated'})
        output=sql("begin;"+("set transaction read only;" if read_only else "")+"set local role authenticated;set local request.jwt.claims='"+claims+"';select to_jsonb(public."+name+'('+','.join(k+'=>'+value(v) for k,v in args.items())+'));commit;')
        rows=output.splitlines();return json.loads(rows[-1]) if rows else None
    def refuse(label,call,code='42501'):
        try:call()
        except RuntimeError as e:
            assert code in str(e),label+': wrong failure category';print('PASS '+label,flush=True);return
        raise AssertionError(label+': expected refusal')
    sql("update team_private.web_signup_settings set enabled=false,team_id=null where id;")
    status=rpc(applicant,'web_signup_status')
    assert status=={'has_access':False,'configured':False,'request':None}
    refuse('unconfigured signup creates no request',lambda:rpc(applicant,'web_request_access',p_first_name='TEST ONLY',p_last_name='Applicant',p_requested_role='manager'),'PT503')
    sql(f"update team_private.web_signup_settings set team_id='{team}',enabled=true where id;")
    refuse('unverified email cannot submit access request',lambda:rpc(unverified,'web_request_access',p_first_name='TEST ONLY',p_last_name='Unverified',p_requested_role='manager'))
    refuse('requested owner role is not permitted',lambda:rpc(applicant,'web_request_access',p_first_name='TEST ONLY',p_last_name='Applicant',p_requested_role='owner'),'22023')
    first=rpc(applicant,'web_request_access',p_first_name='TEST ONLY',p_last_name='Applicant',p_requested_role='manager')
    again=rpc(applicant,'web_request_access',p_first_name='TEST ONLY',p_last_name='Applicant',p_requested_role='manager')
    assert not first['has_access'] and first['request']==again['request'] and first['request']['status']=='pending'
    assert sql("select count(*) from team_private.web_join_notifications where request_id='"+first['request']['id']+"';").splitlines()[-1]=='1'
    assert sql("select count(*) from public.web_join_requests where user_id='"+applicant+"';").splitlines()[-1]=='1'
    print('PASS verified request is stable/idempotent with one notification and no role grant',flush=True)
    claims=json.dumps({'sub':applicant,'session_id':sessions[applicant],'exp':4102444800,'role':'authenticated'})
    own=sql("begin;set local role authenticated;set local request.jwt.claims='"+claims+"';select count(*) from public.web_join_requests;commit;")
    assert own.splitlines()[-1]=='1'
    print('PASS pending request RLS exposes only the applicant own row',flush=True)
    assert len(rpc(owner,'web_list_join_requests',read_only=True,p_team_id=team))==1
    print('PASS owner applicant list works in a read-only Data API transaction',flush=True)

    owner_revision=rpc(owner,'team_access',p_team_id=team)['access_revision']
    rpc(owner,'team_set_capability',p_team_id=team,p_user_id=member,p_capability='members.manage',p_enabled=True,p_expected_access_revision=owner_revision)
    owner_revision=rpc(owner,'team_access',p_team_id=team)['access_revision']
    refuse('legacy admission cannot bypass verified-request role review',lambda:rpc(owner,'team_set_membership',p_team_id=team,p_user_id=applicant,p_status='active',p_expected_access_revision=owner_revision))
    refuse('delegated administrator cannot bypass owner signup review',lambda:rpc(member,'team_set_membership',p_team_id=team,p_user_id=applicant,p_status='active',p_expected_access_revision=owner_revision))
    rpc(legacy,'team_request_membership',p_team_id=team)
    owner_revision=rpc(owner,'team_access',p_team_id=team)['access_revision']
    refuse('legacy request without web role review cannot be admitted',lambda:rpc(member,'team_set_membership',p_team_id=team,p_user_id=legacy,p_status='active',p_expected_access_revision=owner_revision))
    refuse('pending applicant cannot grant staff permissions',lambda:rpc(applicant,'team_apply_staff_preset',p_team_id=team,p_user_id=applicant,p_role='coach',p_expected_access_revision=1))
    refuse('pending applicant cannot read team authority',lambda:rpc(applicant,'team_access',p_team_id=team))
    refuse('ordinary member cannot inspect applicants',lambda:rpc(member,'web_list_join_requests',p_team_id=team))
    access=lambda:rpc(owner,'team_access',p_team_id=team)['access_revision']
    declined_request=rpc(declined,'web_request_access',p_first_name='TEST ONLY',p_last_name='Declined',p_requested_role='coach')['request']
    rpc(owner,'web_review_join_request',p_team_id=team,p_request_id=declined_request['id'],p_expected_revision=1,p_expected_access_revision=access(),p_role='player',p_confirm_identity=False,p_approve=False)
    refuse('declined applicant cannot bypass owner decision through legacy activation',lambda:rpc(member,'team_set_membership',p_team_id=team,p_user_id=declined,p_status='active',p_expected_access_revision=access()))
    request=first['request']
    args=dict(p_team_id=team,p_request_id=request['id'],p_expected_revision=request['revision'],p_expected_access_revision=access(),p_role='player')
    refuse('owner must explicitly verify applicant identity and role',lambda:rpc(owner,'web_review_join_request',**args,p_confirm_identity=False),'22023')
    sql(f"update auth.users set banned_until=now()+interval '1 hour' where id='{owner}';")
    try:
        refuse('retained session does not let banned owner approve access',lambda:rpc(owner,'web_review_join_request',**args,p_confirm_identity=True))
        refuse('banned owner cannot read applicant contacts',lambda:rpc(owner,'web_list_join_requests',p_team_id=team))
        owner_claims=json.dumps({'sub':owner,'session_id':sessions[owner],'exp':4102444800,'role':'authenticated'})
        visible=sql("begin;set local role authenticated;set local request.jwt.claims='"+owner_claims+"';select count(*) from public.web_join_requests;commit;")
        assert visible.splitlines()[-1]=='0','Banned owner must not see applicant rows through RLS'
        print('PASS direct applicant RLS also conceals requests from banned owner',flush=True)
    finally:sql(f"update auth.users set banned_until=null where id='{owner}';")
    approved=rpc(owner,'web_review_join_request',**args,p_confirm_identity=True)
    assert approved['status']=='approved' and approved['confirmed_role']=='player'
    assert rpc(applicant,'web_signup_status')['has_access']
    assert rpc(applicant,'team_access',p_team_id=team)['can_propose_stats'] is False
    print('PASS owner corrects requested manager to read-only player atomically',flush=True)
    # A later untrusted role claim does not replace an existing approved role.
    rpc(applicant,'web_request_access',p_first_name='TEST ONLY',p_last_name='Changed',p_requested_role='coach')
    assert rpc(applicant,'team_access',p_team_id=team)['capabilities']==[]
    before=sql(f"select count(*) from public.capability_grants where team_id='{team}';")
    rpc(owner,'web_review_join_request',**dict(args,p_expected_access_revision=access()),p_confirm_identity=True)
    assert sql(f"select count(*) from public.capability_grants where team_id='{team}';")==before
    print('PASS repeated approval/request never escalates or resets approved account permissions',flush=True)
    second_request=rpc(second,'web_request_access',p_first_name='TEST ONLY',p_last_name='Second',p_requested_role='player')['request']
    rpc(owner,'web_review_join_request',p_team_id=team,p_request_id=second_request['id'],p_expected_revision=second_request['revision'],p_expected_access_revision=access(),p_role='coach',p_confirm_identity=True)
    assert set(rpc(second,'team_access',p_team_id=team)['capabilities'])=={'stats.record','stats.review','stats.publish','datasets.reopen','sessions.manage','sessions.record','sessions.review','sessions.publish','sessions.reopen','sessions.clock','plans.manage'}
    assert rpc(owner,'web_signup_status')['has_access'] and rpc(member,'web_signup_status')['has_access']
    print('PASS owner-confirmed staff role receives exact equal coach/manager preset; existing users remain active',flush=True)
    banned_request=rpc(banned,'web_request_access',p_first_name='TEST ONLY',p_last_name='Banned',p_requested_role='player')['request']
    sql(f"update auth.users set banned_until=now()+interval '1 hour' where id='{banned}';")
    decision=rpc(owner,'web_review_join_request',p_team_id=team,p_request_id=banned_request['id'],p_expected_revision=1,p_expected_access_revision=access(),p_role='player',p_confirm_identity=False,p_approve=False)
    assert decision['status']=='declined'
    print('PASS owner can decline a now-ineligible applicant without claiming identity verification',flush=True)
    revoked_request=rpc(revoked,'web_request_access',p_first_name='TEST ONLY',p_last_name='Unconfirmed',p_requested_role='player')['request']
    sql(f"update auth.users set email_confirmed_at=null where id='{revoked}';")
    decision=rpc(owner,'web_review_join_request',p_team_id=team,p_request_id=revoked_request['id'],p_expected_revision=1,p_expected_access_revision=access(),p_role='player',p_confirm_identity=False,p_approve=False)
    assert decision['status']=='declined'
    print('PASS decline can remove access after applicant email verification is revoked',flush=True)
    # The approval must hold applicant eligibility until its transaction commits.
    from concurrent.futures import ThreadPoolExecutor
    import time
    locked_request=rpc(legacy,'web_request_access',p_first_name='TEST ONLY',p_last_name='Concurrent',p_requested_role='player')['request']
    tag='test_only_admission_'+uuid.uuid4().hex
    claims=json.dumps({'sub':owner,'session_id':sessions[owner],'exp':4102444800,'role':'authenticated'})
    review=f"begin;set local application_name='{tag}';set local role authenticated;set local request.jwt.claims='{claims}';select public.web_review_join_request('{team}','{locked_request['id']}',1,{access()},true,'player',true);select pg_sleep(1);commit;"
    with ThreadPoolExecutor(max_workers=1) as executor:
        pending=executor.submit(sql,review)
        deadline=time.monotonic()+5
        while sql(f"select count(*) from pg_stat_activity where application_name='{tag}' and wait_event='PgSleep';")!='1':
            if pending.done():pending.result();raise AssertionError('Approval did not reach retained transaction')
            assert time.monotonic()<deadline,'Approval lock check timed out'
            time.sleep(.02)
        refuse('concurrent ban waits for admission transaction to finish',lambda:sql(f"begin;set local lock_timeout='150ms';update auth.users set banned_until=now()+interval '1 hour' where id='{legacy}';commit;"),'55P03')
        pending.result()
    # Removing access remains authoritative; request metadata cannot restore it.
    rpc(owner,'team_set_membership',p_team_id=team,p_user_id=applicant,p_status='removed',p_expected_access_revision=access())
    assert rpc(applicant,'web_signup_status')['has_access'] is False
    rpc(applicant,'web_request_access',p_first_name='TEST ONLY',p_last_name='Applicant',p_requested_role='coach')
    assert rpc(applicant,'web_signup_status')['has_access'] is False
    refuse('old approved request cannot silently restore removed access',lambda:rpc(applicant,'team_access',p_team_id=team))

if __name__ == '__main__':
    import argparse,re,sys
    from pathlib import Path
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
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
    before=pg.snapshot(source);target='teamstats_web_admission_'+uuid.uuid4().hex
    pg.run('createdb',['--template',source,target])
    def sql(text):
        try:return pg.sql(target,'\\set VERBOSITY verbose\n'+text)
        except RuntimeError:
            diagnostic=(args.recovery_output/'diagnostics.local.log').read_text()
            codes=re.findall(r'ERROR:  ([0-9A-Z]{5}):',diagnostic)
            raise RuntimeError('SQLSTATE '+(codes[-1] if codes else 'unknown')) from None
    run(sql)
    assert pg.snapshot(source)==before
    print('Synthetic admission contracts passed; original recovery fixture preserved.')
