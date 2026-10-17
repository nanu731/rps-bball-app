"""Synthetic loopback HTTP fixtures, not Google integration evidence."""
import copy
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import threading
import time
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location('sheets_export', Path(__file__).parents[1] / 'sheets_export.py')
worker = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = worker
spec.loader.exec_module(worker)

def job(version='a7000000-0000-4000-8000-000000000001', generation=1, sheet=100, row=1):
    p = {'schema': 1, 'team_id': 'a3000000-0000-4000-8000-000000000001',
         'accepted_version_id': version, 'dataset_id': 'a6000000-0000-4000-8000-000000000001',
         'dataset_type': 'box_scores', 'revision': 4, 'publication_generation': generation,
         'game': {'id': 'a4000000-0000-4000-8000-000000000001', 'date': '2026-10-10',
                  'opponent': '=IMPORTXML("SYNTHETIC")', 'home_away': 'away', 'game_type': 'regularSeason'},
         'records': [{'playerID': 'a5000000-0000-4000-8000-000000000001', 'values': {'points': None, 'assists': 0}}],
         'roster': [{'id': 'a5000000-0000-4000-8000-000000000001', 'version': 1,
                     'display_name': '=SYNTHETIC old label', 'jersey_number': '+90'}]}
    raw = json.dumps(p, sort_keys=True, ensure_ascii=False)
    return {'job_id': 'a8000000-0000-4000-8000-000000000001', 'accepted_version_id': version,
            'payload_text': raw, 'payload_sha256': hashlib.sha256(raw.encode()).hexdigest(),
            'spreadsheet_id': 'SYNTHETIC_DESTINATION', 'sheet_id': sheet, 'ledger_sheet_id': 0,
            'ledger_row': row, 'state': 'reserved'}

class Fixture:
    def __init__(self, mode='success'):
        self.mode = mode
        self.lock = threading.Lock()
        self.sheets = {0: {'properties': {'sheetId': 0, 'title': 'TeamStats Ledger',
                         'gridProperties': {'rowCount': 100001, 'columnCount': 8}}, 'rows': {}}}
        self.sheets[1] = {'properties': {'sheetId': 1, 'title': 'TeamStats Latest'},
                          'rows': {1: {'values': [{'userEnteredValue': {'formulaValue': worker.LATEST_FORMULA}}]}}}
        self.batches = []
        self.backend_jobs = []
        self.backend_states = {}
        fixture = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def respond(self, code, value):
                data = json.dumps(value).encode()
                try:
                    self.send_response(code)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            def do_GET(self):
                if fixture.mode == 'slow_read':
                    self.send_response(200); self.send_header('Content-Length','10'); self.end_headers()
                    try:
                        for _ in range(10): self.wfile.write(b' '); self.wfile.flush(); time.sleep(.02)
                    except (BrokenPipeError,ConnectionResetError): pass
                    return
                args = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                if 'ranges' not in args:
                    with fixture.lock:
                        self.respond(200, {'sheets': [{'properties': s['properties']} for s in fixture.sheets.values()]})
                    return
                output = []
                with fixture.lock:
                    for requested in args['ranges']:
                        title = requested.split("'!")[0][1:]
                        sheet = next((s for s in fixture.sheets.values() if s['properties']['title'] == title), None)
                        if sheet is None:
                            self.respond(400, {'error': {'message': 'synthetic missing range'}})
                            return
                        row = int(requested.split('!A')[1].split(':')[0]) - 1
                        end = int(''.join(c for c in requested.split(':')[1] if c.isdigit()))
                        output.append({'properties': sheet['properties'], 'data': [{'startRow': row,
                            'rowData': [sheet['rows'].get(n, {'values': []}) for n in range(row, end)]}]})
                self.respond(200, {'sheets': output})
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                if '/rpc/' in self.path:
                    name = self.path.rsplit('/', 1)[1]
                    if name == 'stats_export_jobs':
                        self.respond(200, [{'job_id': j['job_id']} for j in fixture.backend_jobs[:body['p_limit']]])
                    elif name == 'stats_export_reserve':
                        self.respond(200, next(j for j in fixture.backend_jobs if j['job_id'] == body['p_job_id']))
                    elif name == 'stats_export_finish':
                        fixture.backend_states[body['p_job_id']] = 'delivered'
                        self.respond(200, None)
                    elif name == 'stats_export_fail':
                        fixture.backend_states[body['p_job_id']] = body['p_error_code']
                        self.respond(200, None)
                    return
                if fixture.mode == 'quota':
                    self.respond(429, {'error': {'message': 'SYNTHETIC token must not leak'}})
                    return
                if fixture.mode == 'partial':
                    self.respond(200, {'error': {'message': 'SYNTHETIC partial error'}})
                    return
                if fixture.mode == 'timeout_without_apply':
                    time.sleep(.2)
                    self.respond(504, {'error': {}})
                    return
                requests = body['requests']
                with fixture.lock:
                    properties = requests[0]['addSheet']['properties']
                    sheet_id = properties['sheetId']
                    if sheet_id in fixture.sheets:
                        self.respond(400, {'error': {'message': 'duplicate sheetId'}})
                        return
                    if len(requests) != 3 or any(r.get('updateCells', {}).get('fields') != 'userEnteredValue' for r in requests[1:]):
                        self.respond(400, {'error': {'message': 'invalid batch'}})
                        return
                    fixture.sheets[sheet_id] = {'properties': properties, 'rows': {}}
                    for request in requests[1:]:
                        update = request['updateCells']
                        start = update['start']
                        target = fixture.sheets[start['sheetId']]['rows']
                        for index, cells in enumerate(update['rows']):
                            target[start['rowIndex'] + index] = copy.deepcopy(cells)
                    fixture.batches.append(copy.deepcopy(body))
                if fixture.mode == 'timeout_applied':
                    time.sleep(.2)
                self.respond(200, {'replies': [{'addSheet': {'properties': properties}}, {}, {}]})
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.endpoint = 'http://127.0.0.1:' + str(self.server.server_port) + '/v4/spreadsheets'
    def config(self, **kwargs):
        return worker.GoogleConfig(token='SYNTHETIC_FIXTURE_TOKEN', enabled=True,
            billing_disabled_verified_at=dt.datetime.now(dt.timezone.utc).isoformat(), endpoint=self.endpoint, **kwargs)
    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture()
        self.addCleanup(self.fixture.close)
    def test_slow_continuous_read_has_a_total_deadline_without_writes(self):
        self.fixture.mode='slow_read'
        with self.assertRaisesRegex(worker.ExportError,'provider_timeout'):
            worker.GoogleSheets(self.fixture.config(timeout=.04)).deliver(job())
        self.assertEqual(self.fixture.batches,[])

    def test_google_delivery_defaults_to_disabled(self):
        with self.assertRaisesRegex(worker.ExportError, 'budget_disabled'):
            worker.GoogleSheets(worker.GoogleConfig(token='SYNTHETIC')).deliver({})
        self.assertEqual(self.fixture.batches, [])
    def test_only_literal_true_enables_google_requests(self):
        for value in ('false', 'true', 1, {'enabled': False}, False, None):
            with self.subTest(enabled=value):
                config = worker.GoogleConfig(token='SYNTHETIC', enabled=value,
                    billing_disabled_verified_at=dt.datetime.now(dt.timezone.utc).isoformat(), endpoint=self.fixture.endpoint)
                with self.assertRaisesRegex(worker.ExportError, 'budget_disabled'):
                    worker.GoogleSheets(config).deliver(job())
        self.assertEqual(len(self.fixture.batches), 0)

    def test_expired_or_naive_budget_evidence_cannot_enable_delivery(self):
        for timestamp in ('', '2020-01-01T00:00:00+00:00', '2026-01-01'):
            with self.subTest(timestamp=timestamp):
                config = worker.GoogleConfig(token='SYNTHETIC', enabled=True, billing_disabled_verified_at=timestamp,
                                             endpoint=self.fixture.endpoint)
                with self.assertRaisesRegex(worker.ExportError, 'budget_disabled'):
                    worker.GoogleSheets(config).deliver(job())
        self.assertEqual(self.fixture.batches, [])
    def test_missing_and_zero_are_distinct_human_readable_literal_cells(self):
        j = job()
        worker.GoogleSheets(self.fixture.config()).deliver(j)
        row = self.fixture.sheets[100]['rows'][5]['values']
        self.assertEqual(row[4]['userEnteredValue'], {'stringValue': 'Not entered'})
        self.assertEqual(row[7]['userEnteredValue'], {'stringValue': '0'})
        self.assertEqual(row[2]['userEnteredValue'], {'stringValue': '=SYNTHETIC old label'})
        self.assertEqual(row[3]['userEnteredValue'], {'stringValue': '+90'})
        opponent = self.fixture.sheets[100]['rows'][1]['values'][5]
        self.assertEqual(opponent['userEnteredValue'], {'stringValue': '=IMPORTXML("SYNTHETIC")'})
    def test_duplicate_delivery_reads_receipt_without_rewriting_snapshot(self):
        j = job()
        first = worker.GoogleSheets(self.fixture.config()).deliver(j)
        before = copy.deepcopy(self.fixture.sheets)
        second = worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.assertEqual(first, second)
        self.assertEqual(self.fixture.sheets, before)
        self.assertEqual(len(self.fixture.batches), 1)
    def test_full_payload_hash_is_verified_before_provider_write(self):
        j = job()
        j['payload_text'] += ' '
        with self.assertRaisesRegex(worker.ExportError, 'payload_hash_mismatch'):
            worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.assertEqual(self.fixture.batches, [])
    def test_partial_success_response_is_not_acknowledged(self):
        self.fixture.mode = 'partial'
        with self.assertRaises(worker.ExportError):
            worker.GoogleSheets(self.fixture.config()).deliver(job())
        self.assertEqual(self.fixture.batches, [])
    def test_reserved_ledger_collision_is_refused_before_new_snapshot(self):
        self.fixture.sheets[0]['rows'][1] = {'values': [{'userEnteredValue': {'stringValue': 'SYNTHETIC other job'}}]}
        with self.assertRaisesRegex(worker.ExportError, 'destination_conflict'):
            worker.GoogleSheets(self.fixture.config()).deliver(job())
        self.assertEqual(self.fixture.batches, [])
        self.assertNotIn(100, self.fixture.sheets)
    def test_existing_id_with_different_payload_is_conflict_and_never_rewritten(self):
        j = job()
        worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.fixture.sheets[100]['rows'][5]['values'][7] = {'userEnteredValue': {'stringValue': '999'}}
        before = copy.deepcopy(self.fixture.sheets)
        with self.assertRaisesRegex(worker.ExportError, 'destination_conflict'):
            worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.assertEqual(self.fixture.sheets, before)
        self.assertEqual(len(self.fixture.batches), 1)
    def test_existing_full_uuid_match_with_false_hash_is_refused(self):
        j = job()
        worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.fixture.sheets[100]['rows'][0]['values'][2] = {'userEnteredValue': {'stringValue': 'wrong'}}
        with self.assertRaisesRegex(worker.ExportError, 'destination_conflict'):
            worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.assertEqual(len(self.fixture.batches), 1)
    def test_missing_ledger_receipt_is_not_repaired_with_overwrite(self):
        j = job()
        worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.fixture.sheets[0]['rows'][1] = {'values': []}
        with self.assertRaisesRegex(worker.ExportError, 'destination_conflict'):
            worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.assertEqual(len(self.fixture.batches), 1)
    def test_timed_out_but_applied_batch_is_verified_and_not_duplicated(self):
        self.fixture.mode = 'timeout_applied'
        j = job()
        receipt = worker.GoogleSheets(self.fixture.config(timeout=.03)).deliver(j)
        self.assertEqual(receipt['accepted_version_id'], j['accepted_version_id'])
        worker.GoogleSheets(self.fixture.config()).deliver(j)
        self.assertEqual(len(self.fixture.batches), 1)
    def test_timeout_without_receipt_remains_retryable_same_job(self):
        self.fixture.mode = 'timeout_without_apply'
        j = job()
        with self.assertRaisesRegex(worker.ExportError, 'provider_timeout'):
            worker.GoogleSheets(self.fixture.config(timeout=.03)).deliver(j)
        self.fixture.mode = 'success'
        self.assertEqual(worker.GoogleSheets(self.fixture.config()).deliver(j)['sheet_id'], 100)
    def test_newer_before_older_uses_disjoint_snapshot_and_ledger_locations(self):
        older = job()
        newer = job('a7000000-0000-4000-8000-000000000002', 2, 101, 2)
        worker.GoogleSheets(self.fixture.config()).deliver(newer)
        before = copy.deepcopy(self.fixture.sheets[101])
        worker.GoogleSheets(self.fixture.config()).deliver(older)
        self.assertEqual(self.fixture.sheets[101], before)
        self.assertEqual(self.fixture.sheets[0]['rows'][2]['values'][2]['userEnteredValue'],
                         {'stringValue': '00000000000000000002'})
    def test_racing_same_version_has_one_snapshot_and_two_verified_receipts(self):
        j = job()
        receipts, errors = [], []
        def deliver():
            try:
                receipts.append(worker.GoogleSheets(self.fixture.config()).deliver(j))
            except Exception as error:
                errors.append(error)
        threads = [threading.Thread(target=deliver) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(errors, [])
        self.assertEqual(len(receipts), 2)
        self.assertEqual(len(self.fixture.batches), 1)
    def test_delivery_requires_fixed_max_generation_latest_projection(self):
        self.fixture.sheets[1] = {'properties': {'sheetId': 1, 'title': 'TeamStats Latest'},
                                 'rows': {1: {'values': [{'userEnteredValue': {'formulaValue': '=SYNTHETIC_WRONG'}}]}}}
        with self.assertRaisesRegex(worker.ExportError, 'destination_conflict'):
            worker.GoogleSheets(self.fixture.config()).deliver(job())
        self.assertEqual(self.fixture.batches, [])
    def test_provider_quota_error_does_not_expose_raw_response(self):
        self.fixture.mode = 'quota'
        with self.assertRaisesRegex(worker.ExportError, '^provider_http_429$'):
            worker.GoogleSheets(self.fixture.config()).deliver(job())
        self.assertEqual(self.fixture.batches, [])
    def test_request_budget_bounds_transport(self):
        with self.assertRaisesRegex(worker.ExportError, 'request_limit'):
            worker.GoogleSheets(self.fixture.config(request_limit=1)).deliver(job())
        self.assertEqual(self.fixture.batches, [])
    def test_worker_reports_budget_failure_through_real_backend_transport(self):
        j = job()
        self.fixture.backend_jobs = [j]
        backend = worker.Backend('http://127.0.0.1:' + str(self.fixture.server.server_port) + '/rest/v1', 'SYNTHETIC')
        outcomes = worker.run_once(backend, worker.GoogleSheets(worker.GoogleConfig()))
        self.assertEqual(outcomes, [{'job_id': j['job_id'], 'state': 'failed', 'error_code': 'budget_disabled'}])
        self.assertEqual(self.fixture.backend_states[j['job_id']], 'budget_disabled')
        self.assertEqual(self.fixture.batches, [])
    def test_worker_acknowledges_only_full_provider_receipt(self):
        j = job()
        self.fixture.backend_jobs = [j]
        backend = worker.Backend('http://127.0.0.1:' + str(self.fixture.server.server_port) + '/rest/v1', 'SYNTHETIC')
        outcomes = worker.run_once(backend, worker.GoogleSheets(self.fixture.config()))
        self.assertEqual(outcomes, [{'job_id': j['job_id'], 'state': 'delivered'}])
        self.assertEqual(self.fixture.backend_states[j['job_id']], 'delivered')

if __name__ == '__main__':
    unittest.main()
