"""Concurrent admissions ONLY in a new clone of the synthetic recovery fixture.

Uses the existing pinned PostgreSQL adapter; never accepts a hosted URL or exports
an existing database. Keeps the new test database/evidence after success/failure.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from recovery_drill import IsolatedPostgres


def verify(pg, recovery_output):
    receipt = json.loads((recovery_output / 'receipt.json').read_text())
    source = receipt['restored']
    if (receipt.get('hostedRecovery') is not False or not receipt.get('restoredRowsAndPoliciesEqual')
            or not re.fullmatch(r'teamstats_recovery_restored_[a-f0-9]{32}', source)):
        raise ValueError('Expected the completed synthetic recovery receipt')
    if pg.sql(source, "select count(*)=1 and bool_and(name='TEST ONLY recovery team') from public.teams") != 't':
        raise ValueError('Expected only the known synthetic team')
    if pg.sql(source, "select count(*)=3 and bool_and(email like 'recovery-%@example.invalid') from auth.users") != 't':
        raise ValueError('Expected only the known synthetic accounts')
    target = 'teamstats_admission_' + uuid.uuid4().hex
    plan = recovery_output / 'admission-plan.json'
    with plan.open('x') as stream:
        json.dump({'syntheticSource': source, 'isolatedDestination': target}, stream)
    pg.run('createdb', ['--template', source, target])
    before = pg.snapshot(target)
    def admission(actor):
        claims = json.dumps({'sub':f'f1000000-0000-4000-8000-{actor:012}',
            'session_id':f'f2000000-0000-4000-8000-{actor:012}', 'exp':4102444800})
        sql = f"begin; set local role authenticated; set local request.jwt.claims='{claims}'; select public.file_request_admission(); commit;"
        return json.loads(pg.sql(target, sql))
    with ThreadPoolExecutor(max_workers=8) as pool:
        replies = list(pool.map(admission, [1]*40))
    assert sum(reply['allowed'] for reply in replies) == 30, 'Concurrent allowance oversubscribed or reset'
    assert all(reply['retry_after'] in range(1,61) for reply in replies if not reply['allowed'])
    assert admission(2) == {'allowed':True,'retry_after':0}, 'Actor isolation failed'
    assert not admission(1)['allowed'], 'New connection/replay refunded allowance'
    after = pg.snapshot(target)
    before['rows'].pop('team_private.file_request_windows')
    counters = after['rows'].pop('team_private.file_request_windows')
    assert before == after, 'Admission changed unrelated records/permissions'
    assert len(counters)==2 and sorted(row['requests'] for row in counters)==[1,31]
    result={'concurrentRequests':40,'allowed':30,'denied':10,'otherActorAllowed':True,
            'newConnectionStillDenied':True,'unrelatedRowsAndPermissionsUnchanged':True,'hosted':False}
    with (recovery_output/'admission-receipt.json').open('x') as stream: json.dump(result,stream,indent=2)
    print('PASS: concurrent synthetic admissions30/40; actor isolation; persisted denial; unrelated records unchanged')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    tools=parser.add_mutually_exclusive_group(required=True)
    tools.add_argument('--pg-bin',type=Path); tools.add_argument('--container')
    parser.add_argument('--recovery-output',type=Path,required=True)
    args=parser.parse_args()
    verify(IsolatedPostgres(args.recovery_output,args.pg_bin,args.container),args.recovery_output)
