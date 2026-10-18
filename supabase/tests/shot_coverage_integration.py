"""Version-bound shot coverage only in a new guarded synthetic recovery clone."""
import argparse, copy, json, re, sys, uuid
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from recovery_drill import IsolatedPostgres

TEAM = 'f3000000-0000-4000-8000-000000000001'
GAME = 'f5000000-0000-4000-8000-000000000001'

def verify(pg, recovery_output, apply_migration=False):
    proof = json.loads((recovery_output / 'receipt.json').read_text())
    source = proof['restored']
    assert proof.get('hostedRecovery') is False and proof.get('restoredRowsAndPoliciesEqual')
    assert re.fullmatch(r'teamstats_recovery_restored_[a-f0-9]{32}', source)
    assert pg.sql(source, "select count(*)=1 and bool_and(name='TEST ONLY recovery team') from public.teams") == 't'
    before = pg.snapshot(source)
    target = 'teamstats_coverage_' + uuid.uuid4().hex
    pg.run('createdb', ['--template', source, target])
    if apply_migration:
        pg.sql(target, (Path(__file__).parents[1] / 'migrations/202610170006_shot_coverage.sql').read_text())
    uid = lambda n: f'f1000000-0000-4000-8000-{n:012}'
    literal = lambda v: 'null' if v is None else str(v) if isinstance(v, int) else "'" + str(v).replace("'", "''") + "'"
    def call(actor, name, *values, denied=None):
        claims = json.dumps(dict(sub=uid(actor), session_id=f'f2000000-0000-4000-8000-{actor:012}', exp=4102444800))
        expression = 'public.' + name + '(' + ','.join(map(literal, values)) + ')'
        prefix = f"begin;set local role authenticated;set local request.jwt.claims='{claims}';"
        if denied:
            pg.sql(target, prefix + f"do $$begin begin perform {expression};raise exception 'Expected denial';exception when sqlstate '{denied}' then null;end;end$$;rollback;")
        else:
            return json.loads(pg.sql(target, prefix + f"select coalesce(({expression})::text,'null');commit;"))
    pg.sql(target, f"update public.capability_grants set revoked_at=now() where capability='stats.review';insert into public.capability_grants(team_id,user_id,capability,issued_by) values('{TEAM}','{uid(2)}','shots.record','{uid(1)}');")
    call(1, 'shots_assign', TEAM, GAME, uid(2), 0, 0, str(uuid.uuid4()), 'TEST ONLY coverage recorder')
    document = dict(schemaVersion=1, id=str(uuid.uuid4()), context=dict(gameID=GAME, teamID=TEAM, actorID=uid(2), assignmentRevision=1),
        players=[dict(id='f4000000-0000-4000-8000-000000000001', name='TEST ONLY recovery player', number='0', temporary=False)], journal=[])
    saved = call(2, 'shots_save', TEAM, GAME, 1, 1, str(uuid.uuid4()), json.dumps(document, separators=(',', ':')), 'unknown')
    state = call(2, 'shots_state', TEAM, GAME)
    assert state['coverage']['status'] == 'not_confirmed'
    assert state['coverage']['snapshot_id'] == saved['snapshot_id']
    assert state['coverage']['can_confirm'] is True and state['coverage']['can_approve'] is False
    snapshot = saved['snapshot_id']
    first_batch = str(uuid.uuid4())
    args = (TEAM, GAME, 1, 2, first_batch, snapshot, 'confirm', None)
    confirmed = call(2, 'shots_coverage_decide', *args)
    assert confirmed['state_revision'] == 3 and confirmed['confirmation_id'] == first_batch
    assert call(2, 'shots_coverage_decide', *args) == confirmed
    assert call(2, 'shots_coverage_receipt', TEAM, GAME, first_batch) == confirmed
    coverage = call(1, 'shots_state', TEAM, GAME)['coverage']
    assert coverage['status'] == 'awaiting_review' and coverage['can_approve'] is True
    call(2, 'shots_coverage_decide', TEAM, GAME, 1, 3, str(uuid.uuid4()), snapshot, 'approve', first_batch, denied='42501')
    call(1, 'shots_coverage_decide', TEAM, GAME, 1, 3, str(uuid.uuid4()), snapshot, 'confirm', None, denied='42501')
    call(1, 'shots_coverage_decide', TEAM, GAME, 1, 2, str(uuid.uuid4()), snapshot, 'approve', first_batch, denied='PT409')
    approved_batch = str(uuid.uuid4())
    approval_args = (TEAM, GAME, 1, 3, approved_batch, snapshot, 'approve', first_batch)
    approved = call(1, 'shots_coverage_decide', *approval_args)
    assert approved['state_revision'] == 4
    assert call(1, 'shots_coverage_receipt', TEAM, GAME, approved_batch) == approved
    assert call(1, 'shots_coverage_decide', *approval_args) == approved
    state = call(1, 'shots_state', TEAM, GAME)
    assert state['coverage']['status'] == 'approved' and state['status'] == 'draft'
    # A later saved observation invalidates current coverage, retaining original attestations.
    event = dict(id=str(uuid.uuid4()), kind='freeThrows', team='opponent', freeThrowAttempts=2, answers=[])
    document['journal'].append(dict(id=str(uuid.uuid4()), revision=1, recordedAt='2037-01-01T00:00:00Z', eventID=event['id'], after=copy.deepcopy(event)))
    changed = call(2, 'shots_save', TEAM, GAME, 1, 4, str(uuid.uuid4()), json.dumps(document, separators=(',', ':')), 'manager_declared_full_game')
    state = call(2, 'shots_state', TEAM, GAME)
    assert state['coverage']['status'] == 'not_confirmed'  # Legacy declaration is not approval.
    assert state['coverage']['confirmation_id'] is None and state['document']['journal'][0]['after']['answers'] == []
    call(1, 'shots_coverage_decide', TEAM, GAME, 1, 5, str(uuid.uuid4()), snapshot, 'approve', first_batch, denied='PT409')
    call(3, 'shots_state', TEAM, GAME, denied='42501')
    pg.sql(target, f"insert into public.team_memberships(team_id,user_id,status) values('{TEAM}','{uid(3)}','active');insert into public.capability_grants(team_id,user_id,capability,issued_by) values('{TEAM}','{uid(3)}','stats.review','{uid(1)}');")
    review_state = call(3, 'shots_state', TEAM, GAME)
    assert review_state['document'] == document and not review_state['can_review'] and not review_state['can_publish']
    second_batch = str(uuid.uuid4())
    call(2, 'shots_coverage_decide', TEAM, GAME, 1, 5, second_batch, changed['snapshot_id'], 'confirm', None)
    assert call(3, 'shots_state', TEAM, GAME)['coverage']['can_approve'] is True
    reviewer_batch = str(uuid.uuid4())
    reviewer_args = (TEAM, GAME, 1, 6, reviewer_batch, changed['snapshot_id'], 'approve', second_batch)
    call(3, 'shots_coverage_decide', *reviewer_args)
    assert call(3, 'shots_state', TEAM, GAME)['coverage']['status'] == 'approved'
    assert pg.sql(target, 'select count(*) from team_private.shot_coverage_attestations') == '4'
    # Swift Codable re-encodes UUID-typed fields, while player IDs remain exact strings.
    # This input shape matches the independently observed native rendered failure.
    document = copy.deepcopy(document)
    document['id'] = document['id'].upper()
    for key in ['gameID', 'teamID', 'actorID']: document['context'][key] = document['context'][key].upper()
    for change in document['journal']:
        for key in ['id', 'eventID', 'undoOf']:
            if key in change: change[key] = change[key].upper()
        for image in ['before', 'after']:
            if isinstance(change.get(image), dict): change[image]['id'] = change[image]['id'].upper()
    event = copy.deepcopy(document['journal'][-1]['after'])
    original = copy.deepcopy(event)
    event['answers'] = [dict(index=1, outcome='made')]
    document['journal'].append(dict(id=str(uuid.uuid4()), revision=2, recordedAt='2037-01-01T00:00:01Z', eventID=event['id'], before=original, after=copy.deepcopy(event)))
    preserved = pg.sql(target, "select document::text||document_digest from team_private.shot_snapshots where id='" + changed['snapshot_id'] + "'")
    invalid = []
    candidate = copy.deepcopy(document); candidate['players'][0]['name'] = candidate['players'][0]['name'].lower(); invalid.append((candidate, 'PT409'))
    candidate = copy.deepcopy(document); candidate['players'][0]['id'] = candidate['players'][0]['id'].upper(); invalid.append((candidate, 'PT409'))
    candidate = copy.deepcopy(document); candidate['journal'][0]['recordedAt'] = '2037-01-01T00:00:00+00:00'; invalid.append((candidate, 'PT409'))
    candidate = copy.deepcopy(document); candidate['journal'][0]['id'] = str(uuid.uuid4()); invalid.append((candidate, 'PT409'))
    candidate = copy.deepcopy(document); candidate['journal'][0]['before'] = None; invalid.append((candidate, 'PT409'))
    candidate = copy.deepcopy(document); candidate['id'] = candidate['id'].replace('-', ''); invalid.append((candidate, 'PT409'))
    candidate = copy.deepcopy(document); candidate['journal'].reverse(); invalid.append((candidate, '22023'))
    candidate = copy.deepcopy(document); candidate['journal'][0]['after']['freeThrowAttempts'] = 4; invalid.append((candidate, '22023'))
    for candidate, code in invalid:
        call(2, 'shots_save', TEAM, GAME, 1, 7, str(uuid.uuid4()), json.dumps(candidate, separators=(',', ':')), 'unknown', denied=code)
    frozen = json.dumps(document, separators=(',', ':')); correction_batch = str(uuid.uuid4())
    correction_args = (TEAM, GAME, 1, 7, correction_batch, frozen, 'unknown')
    corrected = call(2, 'shots_save', *correction_args)
    assert call(2, 'shots_save', *correction_args) == corrected
    altered_bytes = copy.deepcopy(document); altered_bytes['id'] = altered_bytes['id'].lower()
    call(2, 'shots_save', TEAM, GAME, 1, 7, correction_batch, json.dumps(altered_bytes, separators=(',', ':')), 'unknown', denied='PT409')
    assert pg.sql(target, "select document::text||document_digest from team_private.shot_snapshots where id='" + changed['snapshot_id'] + "'") == preserved
    stored = json.loads(pg.sql(target, "select document from team_private.shot_snapshots where id='" + corrected['snapshot_id'] + "'"))
    assert stored == document  # The accepted successor retains submitted UUID spellings.
    document['journal'].append(dict(id=str(uuid.uuid4()).upper(), revision=3, recordedAt='2037-01-01T00:00:02Z', eventID=event['id'],
        before=copy.deepcopy(event), after=original, undoOf=document['journal'][-1]['id']))
    undone = call(2, 'shots_save', TEAM, GAME, 1, 8, str(uuid.uuid4()), json.dumps(document, separators=(',', ':')), 'unknown')
    assert call(2, 'shots_receipt', TEAM, GAME, correction_batch) == corrected
    assert call(2, 'shots_save', *correction_args) == corrected
    assert call(1, 'shots_state', TEAM, GAME)['snapshot_id'] == undone['snapshot_id']
    # Case-equivalent registered identity is also eligible for explicit recovery review.
    branch = copy.deepcopy(document); branch['id'] = branch['id'].lower()
    for key in ['gameID', 'teamID', 'actorID']: branch['context'][key] = branch['context'][key].lower()
    recovery = call(2, 'shots_recovery', TEAM, GAME, 1, 9, str(uuid.uuid4()), json.dumps(branch, separators=(',', ':')))
    call(1, 'shots_decide', TEAM, GAME, 1, 10, str(uuid.uuid4()), recovery['snapshot_id'], 'adopt', 'TEST ONLY inspected recovery', undone['snapshot_id'])
    assert call(1, 'shots_state', TEAM, GAME)['coverage']['status'] == 'not_confirmed'
    branch['id'] = branch['id'].upper()
    for key in ['gameID', 'teamID', 'actorID']: branch['context'][key] = branch['context'][key].upper()
    next_event = dict(id=str(uuid.uuid4()).upper(), kind='fieldGoal', team='opponent', location=dict(x=0.2, y=0.7), basket='bottom', answers=[])
    branch['journal'].append(dict(id=str(uuid.uuid4()).upper(), revision=4, recordedAt='2037-01-01T00:00:03Z', eventID=next_event['id'], after=next_event))
    call(2, 'shots_save', TEAM, GAME, 1, 11, str(uuid.uuid4()), json.dumps(branch, separators=(',', ':')), 'unknown')
    assert call(1, 'shots_state', TEAM, GAME)['coverage']['status'] == 'not_confirmed'
    assert call(3, 'shots_coverage_receipt', TEAM, GAME, reviewer_batch)['snapshot_id'] == changed['snapshot_id']
    assert pg.sql(target, 'select count(*) from team_private.shot_coverage_attestations') == '4'
    pg.sql(target, f"update public.capability_grants set revoked_at=now() where user_id='{uid(3)}' and capability='stats.review'")
    call(3, 'shots_coverage_decide', *reviewer_args, denied='42501')
    call(3, 'shots_coverage_receipt', TEAM, GAME, reviewer_batch, denied='42501')
    assert call(3, 'shots_state', TEAM, GAME)['document'] is None
    assert pg.sql(target, "select relrowsecurity and not has_table_privilege('authenticated','team_private.shot_coverage_attestations','SELECT') from pg_class where oid='team_private.shot_coverage_attestations'::regclass") == 't'
    assert pg.sql(target, 'select count(*) from public.stat_versions') == '2'
    assert pg.snapshot(source) == before
    print('Version-bound coverage/current authority, correction/Undo/recovery, UUID interoperability, raw replay and protected-history checks passed; synthetic source preserved')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--pg-bin', type=Path); group.add_argument('--container')
    parser.add_argument('--recovery-output', type=Path, required=True)
    args = parser.parse_args()
    verify(IsolatedPostgres(args.recovery_output, args.pg_bin, args.container), args.recovery_output)
