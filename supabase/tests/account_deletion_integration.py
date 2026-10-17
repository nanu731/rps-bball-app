"""Request intake checks ONLY in a new clone of a completed synthetic recovery drill.

No account deletion, provider access, hosted migration or existing-database writes.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from recovery_drill import IsolatedPostgres



def verify_session_races(pg, source):
    """Observe command-transaction/revocation ordering in two new synthetic clones."""
    for table, assignment in [('auth.sessions', "not_after=now()-interval '1 second'"),
                              ('auth.users', "banned_until=now()+interval '1 day'")]:
        target = 'teamstats_deletion_race_' + uuid.uuid4().hex
        pg.run('createdb', ['--template', source, target])
        tag = 'deletion_race_' + uuid.uuid4().hex
        claims = json.dumps({'sub': 'f1000000-0000-4000-8000-000000000002',
                             'session_id': 'f2000000-0000-4000-8000-000000000002', 'exp': 4102444800})
        holding = f"""begin; set local application_name='{tag}'; set local role authenticated;
          set local request.jwt.claims='{claims}'; select public.account_request_deletion();
          select pg_sleep(3); commit;"""
        key = 'user_id' if table == 'auth.sessions' else 'id'
        revoking = f"update {table} set {assignment} where {key}='f1000000-0000-4000-8000-000000000002'"
        with ThreadPoolExecutor(max_workers=2) as pool:
            pending = pool.submit(pg.sql, target, holding)
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                if pg.sql(target, f"select exists(select 1 from pg_stat_activity where application_name='{tag}' and wait_event='PgSleep')") == 't':
                    break
                time.sleep(0.01)
            else:
                raise AssertionError('Synthetic command barrier was not reached')
            revoked = pool.submit(pg.sql, target, revoking)
            # Confirm revocation is blocked while the authorized receipt transaction
            # remains open, rather than asserting ordering from elapsed time alone.
            deadline = time.monotonic() + 2
            blocked = False
            while time.monotonic() < deadline and not revoked.done():
                blocked = pg.sql(target, f"select exists(select 1 from pg_stat_activity where datname='{target}' and query like 'update {table}%' and wait_event_type='Lock')") == 't'
                if blocked: break
                time.sleep(0.01)
            pending.result(timeout=10); revoked.result(timeout=10)
        assert blocked, f'Concurrent {table} revocation committed before the request transaction'
        pg.sql(target, f"""begin; set local role authenticated; set local request.jwt.claims='{claims}';
          do $check$ begin begin perform public.account_deletion_receipt(); raise exception 'Expected denial';
            exception when insufficient_privilege then null; end; end $check$; rollback;""")


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
    target = 'teamstats_deletion_' + uuid.uuid4().hex
    with (pg.output / 'deletion-plan.json').open('x') as stream:
        json.dump({'syntheticSource': source, 'isolatedDestination': target}, stream)
    pg.run('createdb', ['--template', source, target])
    verify_session_races(pg, source)
    before = pg.snapshot(target)

    def claims(actor, **overrides):
        values = {'sub': f'f1000000-0000-4000-8000-{actor:012}',
                  'session_id': f'f2000000-0000-4000-8000-{actor:012}', 'exp': 4102444800}
        values.update(overrides)
        return json.dumps(values)

    def command(actor, name):
        return json.loads(pg.sql(target, f"begin; set local role authenticated; set local request.jwt.claims='{claims(actor)}'; select coalesce(public.{name}()::text,'null'); commit;"))

    def denied(statement, role='authenticated', identity=None, state='42501'):
        identity = identity or claims(2)
        pg.sql(target, f"""begin; set local role {role}; set local request.jwt.claims='{identity}';
          do $check$ begin
            begin {statement}; raise exception 'Expected denial';
            exception when sqlstate '{state}' then null; end;
          end $check$; rollback;""")

    assert command(1, 'account_deletion_receipt') is None
    with ThreadPoolExecutor(max_workers=8) as pool:
        replies = list(pool.map(lambda _: command(1, 'account_request_deletion'), range(8)))
    first = replies[0]
    assert all(reply == first for reply in replies), 'Concurrent request changed the immutable receipt'
    assert first['user_id'] == 'f1000000-0000-4000-8000-000000000001'
    assert uuid.UUID(first['id']).int and first['requested_at']
    assert command(1, 'account_deletion_receipt') == first, 'New connection failed receipt readback'
    assert command(1, 'account_request_deletion') == first, 'Explicit repeat changed receipt/time'
    assert command(2, 'account_deletion_receipt') is None, 'Another account saw the owner receipt'
    outsider = command(3, 'account_request_deletion')
    assert outsider['user_id'].endswith('000000000003'), 'Membership incorrectly required'
    # Removed members remain eligible; the entire synthetic change is rolled back.
    removed = pg.sql(target, f"""begin;
      update public.team_memberships set status='removed' where user_id='f1000000-0000-4000-8000-000000000002';
      set local role authenticated; set local request.jwt.claims='{claims(2)}';
      select public.account_request_deletion(); rollback;""")
    assert json.loads(removed)['user_id'].endswith('000000000002')
    assert command(2, 'account_deletion_receipt') is None
    for role in ('anon', 'authenticated', 'service_role'):
        for statement in ('perform * from team_private.account_deletion_requests',
                          "insert into team_private.account_deletion_requests(user_id) values('f1000000-0000-4000-8000-000000000002')",
                          "update team_private.account_deletion_requests set requested_at=now()",
                          'delete from team_private.account_deletion_requests'):
            denied(statement, role=role)
    for name in ('account_deletion_receipt', 'account_request_deletion'):
        denied(f'perform public.{name}()', role='anon')
        for identity in (claims(2, exp=1), claims(2, session_id='f2000000-0000-4000-8000-000000000099'),
                         claims(2, is_anonymous=True)):
            denied(f'perform public.{name}()', identity=identity)
        denied(f"perform public.{name}('f1000000-0000-4000-8000-000000000001'::uuid)", state='42883')
        # Server-side disabled accounts cannot use a still-present session.
        for column, value in (('banned_until', "now()+interval '1 day'"), ('deleted_at', 'now()')):
            pg.sql(target, f"""begin; update auth.users set {column}={value}
              where id='f1000000-0000-4000-8000-000000000002';
              set local role authenticated; set local request.jwt.claims='{claims(2)}';
              do $check$ begin begin perform public.{name}(); raise exception 'Expected denial';
                exception when insufficient_privilege then null; end; end $check$; rollback;""")
    assert pg.sql(target, "select relrowsecurity from pg_class where oid='team_private.account_deletion_requests'::regclass") == 't'
    after = pg.snapshot(target)
    assert before['rows'].pop('team_private.account_deletion_requests') == []
    recorded = after['rows'].pop('team_private.account_deletion_requests')
    assert len(recorded) == 2
    assert before == after, 'Intake changed Auth, owner, records, grants, history or permissions'
    result = {'concurrentRequests': 8, 'immutableReceipt': True, 'selfOnly': True,
              'nonmemberAndRemovedEligible': True, 'directMutationDenied': True, 'concurrentSessionAndAccountRevocationSerialized': True,
              'expiredMissingAnonymousDisabledAccountsDenied': True,
              'unrelatedRowsAndPermissionsUnchanged': True, 'hosted': False, 'deletionExecuted': False}
    with (pg.output / 'deletion-receipt.json').open('x') as stream:
        json.dump(result, stream, indent=2)
    print('PASS: synthetic request concurrency/readback/isolation/denial; unrelated rows and permissions unchanged; no deletion')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    tools = parser.add_mutually_exclusive_group(required=True)
    tools.add_argument('--pg-bin', type=Path); tools.add_argument('--container')
    parser.add_argument('--recovery-output', type=Path, required=True)
    args = parser.parse_args()
    verify(IsolatedPostgres(args.recovery_output, args.pg_bin, args.container), args.recovery_output)
