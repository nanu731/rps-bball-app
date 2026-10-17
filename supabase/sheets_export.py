"""Trusted accepted-version export worker; no Google calls by default.

Python 3.11+ standard library only. Configuration and credentials belong to a
trusted runtime, never to the mobile client. See exports.md for activation gates.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import socket
import math
import uuid
from email.utils import parsedate_to_datetime
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

# Installed once by the trusted operator, never changed by delivery jobs. Sorting
# padded literal generations avoids rounding bigint generations through VALUE().
LATEST_FORMULA = """=IFERROR(LET(entries,FILTER('TeamStats Ledger'!A2:H100001,'TeamStats Ledger'!A2:A100001<>""),ordered,SORT(entries,1,TRUE,2,TRUE,3,FALSE),keys,ARRAYFORMULA(INDEX(ordered,0,1)&"|"&INDEX(ordered,0,2)),FILTER(ordered,ARRAYFORMULA(MATCH(keys,keys,0))=SEQUENCE(ROWS(ordered)))),"")"""

from http_deadline import DeadlineHTTPHandler, DeadlineHTTPSHandler
from operation_diagnostics import DIAGNOSTICS, Category, Outcome, Failure, SafeArgumentParser
import time

class ExportError(Exception):
    """A fixed code and numeric delay only; never retain a provider body/header."""
    def __init__(self, code, retry_after=None):
        super().__init__(code)
        self.retry_after = retry_after


def retry_after_seconds(value, now=None, server_date=None):
    if not isinstance(value,str) or len(value)>128: return None
    now = now or dt.datetime.now(dt.timezone.utc)
    try:
        if re.fullmatch(r'[0-9]+',value): seconds=int(value)
        else:
            date=parsedate_to_datetime(value)
            if date.tzinfo is None: return None
            seconds=math.ceil((date-now).total_seconds())
            if server_date:
                try:
                    server=parsedate_to_datetime(server_date)
                    if server.tzinfo is not None: seconds=max(seconds,math.ceil((date-server).total_seconds()))
                except (ValueError,TypeError,OverflowError): pass
        return min(86401,max(0,seconds))  # Beyond one day requires review, never early retry.
    except (ValueError,TypeError,OverflowError): return None


class RunBudget:
    def __init__(self, seconds=120, clock=time.monotonic):
        if not 0 < seconds <= 120: raise ExportError('configuration_invalid')
        self.clock=clock; self.until=clock()+seconds
    def remaining(self, maximum=30, reserve=0):
        left=self.until-self.clock()-reserve
        if left<=0: raise ExportError('run_deadline')
        return min(maximum,left)


@dataclass(frozen=True)
class GoogleConfig:
    token: str = ''
    enabled: bool = False
    billing_disabled_verified_at: str = ''
    request_limit: int = 16
    timeout: float = 15
    # Only loopback fixture HTTP is allowed here; production defaults are fixed.
    endpoint: str = 'https://sheets.googleapis.com/v4/spreadsheets'

class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ExportError('redirect_denied')

class GoogleSheets:
    def __init__(self, config):
        self.config = config
        self.remaining = config.request_limit
        self.budget = None
        self.opener = urllib.request.build_opener(_NoRedirect(), DeadlineHTTPHandler(), DeadlineHTTPSHandler())

    def _guard(self):
        c = self.config
        try:
            verified = dt.datetime.fromisoformat(c.billing_disabled_verified_at)
            age = dt.datetime.now(dt.timezone.utc) - verified
            recent = dt.timedelta(0) <= age <= dt.timedelta(hours=24)
        except (ValueError, TypeError):
            recent = False
        if c.enabled is not True or not recent:
            raise ExportError('budget_disabled')
        if not c.token or not 1 <= c.request_limit <= 20 or not 0 < c.timeout <= 30:
            raise ExportError('configuration_invalid')
        parsed = urllib.parse.urlparse(c.endpoint)
        production = c.endpoint == 'https://sheets.googleapis.com/v4/spreadsheets'
        fixture = parsed.scheme == 'http' and parsed.hostname in ('127.0.0.1', 'localhost', '::1')
        if not production and not fixture:
            raise ExportError('configuration_invalid')

    def _request(self, method, path, body=None):
        self._guard()
        if self.remaining <= 0:
            raise ExportError('request_limit')
        self.remaining -= 1
        raw = json.dumps(body, ensure_ascii=False, separators=(',', ':')).encode() if body is not None else None
        if raw is not None and len(raw) > 1_900_000:
            raise ExportError('payload_too_large')
        request = urllib.request.Request(self.config.endpoint + path, data=raw, method=method,
            headers={'Authorization': 'Bearer ' + self.config.token, 'Content-Type': 'application/json'})
        try:
            with self.opener.open(request, timeout=self.budget.remaining(self.config.timeout,reserve=5) if self.budget else self.config.timeout) as response:
                data = response.read(2_100_001)
            if len(data) > 2_100_000:
                raise ExportError('response_too_large')
            value = json.loads(data)
            if not isinstance(value, dict) or 'error' in value:
                raise ExportError('provider_response')
            return value
        except urllib.error.HTTPError as error:
            # Duplicate ID and partial/invalid batches are verified by the same read seam.
            wait=retry_after_seconds(error.headers.get('Retry-After'),server_date=error.headers.get('Date'))
            error.close()
            raise ExportError('provider_http_' + str(error.code),wait) from None
        except (TimeoutError, socket.timeout):
            raise ExportError('provider_timeout') from None
        except urllib.error.URLError:
            raise ExportError('provider_transport') from None
        except (ValueError, TypeError):
            raise ExportError('provider_response') from None

    def deliver(self, job):
        """Return a verified immutable receipt or a safe retryable failure.

        Existing snapshot IDs are read and compared, never rewritten. The complete
        snapshot grid and reserved ledger row must equal this accepted payload.
        """
        self._guard()
        grid, ledger = snapshot_grid(job)
        sheet_id = job['sheet_id']
        ledger_id = job['ledger_sheet_id']
        row = job['ledger_row']
        title = 'Accepted_' + job['accepted_version_id']
        width = max(map(len, grid))
        prefix = '/' + urllib.parse.quote(job['spreadsheet_id'], safe='')
        def cells(values):
            return [{'values': [{'userEnteredValue': {'stringValue': str(v)}} for v in line]} for line in values]
        batch = {'requests': [
            {'addSheet': {'properties': {'sheetId': sheet_id, 'title': title,
                'gridProperties': {'rowCount': len(grid), 'columnCount': width}}}},
            {'updateCells': {'start': {'sheetId': sheet_id, 'rowIndex': 0, 'columnIndex': 0},
                'rows': cells(grid), 'fields': 'userEnteredValue'}},
            {'updateCells': {'start': {'sheetId': ledger_id, 'rowIndex': row, 'columnIndex': 0},
                'rows': cells([ledger]), 'fields': 'userEnteredValue'}}]}
        # Bound everything before any provider call.
        if len(json.dumps(batch, ensure_ascii=False, separators=(',', ':')).encode()) > 1_900_000:
            raise ExportError('payload_too_large')
        metadata = self._request('GET', prefix + '?' + urllib.parse.urlencode({'fields': 'sheets.properties'}))
        properties = [s.get('properties', {}) for s in metadata.get('sheets', [])]
        ledger_property = next((p for p in properties if p.get('sheetId') == ledger_id), None)
        if not ledger_property or ledger_property.get('title') != 'TeamStats Ledger':
            raise ExportError('destination_conflict')
        sizes = ledger_property.get('gridProperties', {})
        if sizes.get('rowCount', 0) <= row or sizes.get('columnCount', 0) < len(ledger):
            raise ExportError('destination_capacity')
        latest_property = next((p for p in properties if p.get('title') == 'TeamStats Latest'), None)
        if not latest_property or latest_property.get('sheetId') in (sheet_id, ledger_id):
            raise ExportError('destination_conflict')
        projection = self._request('GET', prefix + '?' + urllib.parse.urlencode({
            'ranges': "'TeamStats Latest'!A2:A2",
            'fields': 'sheets(properties(sheetId),data(rowData(values(userEnteredValue))))'}))
        try:
            latest = projection['sheets'][0]
            formula = latest['data'][0]['rowData'][0]['values'][0]['userEnteredValue']
            if len(projection['sheets']) != 1 or latest['properties']['sheetId'] != latest_property['sheetId']:
                raise ExportError('destination_conflict')
            if formula != {'formulaValue': LATEST_FORMULA}:
                raise ExportError('destination_conflict')
        except (KeyError, IndexError, TypeError):
            raise ExportError('destination_conflict') from None
        present = next((p for p in properties if p.get('sheetId') == sheet_id), None)
        if present and present.get('title') != title:
            raise ExportError('destination_conflict')
        write_error = None
        write_retry_after = None
        if not present:
            ledger_preflight = self._request('GET', prefix + '?' + urllib.parse.urlencode({
                'ranges': "'TeamStats Ledger'!A" + str(row + 1) + ':' + _column(len(ledger)) + str(row + 1),
                'fields': 'sheets(properties(sheetId),data(rowData(values(userEnteredValue))))'}))
            try:
                sheets = ledger_preflight['sheets']
                if len(sheets) != 1 or sheets[0]['properties']['sheetId'] != ledger_id:
                    raise ExportError('destination_conflict')
                existing_rows = [r for block in sheets[0].get('data', []) for r in block.get('rowData', [])]
                nonempty = any(cell.get('userEnteredValue', {}) not in ({}, {'stringValue': ''})
                    for r in existing_rows for cell in r.get('values', []))
                if nonempty:
                    # A concurrent copy of this same job may have finished after
                    # the metadata read. Its matching ledger permits readback,
                    # never another write; unrelated observed collisions fail.
                    if existing_rows != cells([ledger]):
                        raise ExportError('destination_conflict')
                    present = True
            except (KeyError, TypeError):
                raise ExportError('destination_conflict') from None
            if not present:
                try:
                    result = self._request('POST', prefix + ':batchUpdate', batch)
                    replies = result.get('replies', [])
                    if len(replies) != 3 or replies[0].get('addSheet', {}).get('properties', {}).get('sheetId') != sheet_id:
                        write_error = 'provider_response'
                except ExportError as error:
                    write_error = str(error)
                    write_retry_after = error.retry_after
        # A successful HTTP write, timeout, concurrent duplicate, or preexisting ID
        # all need the same complete receipt. Never acknowledge the HTTP status alone.
        ranges = ["'" + title + "'!A1:" + _column(width) + str(len(grid)),
                  "'TeamStats Ledger'!A" + str(row + 1) + ':' + _column(len(ledger)) + str(row + 1)]
        query = urllib.parse.urlencode([('ranges', r) for r in ranges] + [
            ('fields', 'sheets(properties(sheetId,title),data(startRow,startColumn,rowData(values(userEnteredValue))))')])
        try:
            readback = self._request('GET', prefix + '?' + query)
            expected = {sheet_id: (0, grid), ledger_id: (row, [ledger])}
            if not _matches(readback, expected):
                raise ExportError('destination_conflict')
        except ExportError:
            if write_error and write_error not in ('provider_http_400', 'provider_response'):
                raise ExportError(write_error,write_retry_after) from None
            raise
        return {k: job[k] for k in ('accepted_version_id', 'payload_sha256', 'spreadsheet_id', 'sheet_id', 'ledger_row')}

def _column(n):
    result = ''
    while n:
        n, d = divmod(n - 1, 26)
        result = chr(65 + d) + result
    return result

def _matches(response, expected):
    seen = set()
    for sheet in response.get('sheets', []):
        sheet_id = sheet.get('properties', {}).get('sheetId')
        if sheet_id not in expected or sheet_id in seen:
            return False
        seen.add(sheet_id)
        start, rows = expected[sheet_id]
        blocks = sheet.get('data', [])
        if len(blocks) != 1:
            return False
        block = blocks[0]
        if block.get('startRow', 0) != start or block.get('startColumn', 0) != 0:
            return False
        actual = block.get('rowData', [])
        if len(actual) != len(rows):
            return False
        for actual_row, expected_row in zip(actual, rows):
            values = actual_row.get('values', [])
            if len(values) != len(expected_row):
                return False
            for cell, value in zip(values, expected_row):
                if cell.get('userEnteredValue') != {'stringValue': str(value)}:
                    return False
    return seen == set(expected)

BOX_FIELDS = ('points', 'offensiveRebounds', 'defensiveRebounds', 'assists', 'turnovers', 'steals',
              'blocks', 'fouls', 'chargesDrawn', 'twosMade', 'twosMissed', 'threesMade',
              'threesMissed', 'freeThrowsMade', 'freeThrowsMissed')
FIELD_LABELS = {'points': 'Points', 'offensiveRebounds': 'Offensive rebounds',
    'defensiveRebounds': 'Defensive rebounds', 'assists': 'Assists', 'turnovers': 'Turnovers',
    'steals': 'Steals', 'blocks': 'Blocks', 'fouls': 'Fouls', 'chargesDrawn': 'Charges drawn',
    'twosMade': 'Two-point makes', 'twosMissed': 'Two-point misses', 'threesMade': 'Three-point makes',
    'threesMissed': 'Three-point misses', 'freeThrowsMade': 'Free throws made',
    'freeThrowsMissed': 'Free throws missed', 'paintTouches': 'Paint touches', 'total': 'Game paint touches'}
POSSESSION_FIELDS = ('paintTouches', 'offensiveRebounds', 'twosMade', 'twosMissed',
                     'threesMade', 'threesMissed', 'freeThrowsMade', 'freeThrowsMissed')

def snapshot_grid(job):
    """Human-readable literal grid, preserving missing values and roster history."""
    try:
        raw = job['payload_text']
        if hashlib.sha256(raw.encode()).hexdigest() != job['payload_sha256']:
            raise ExportError('payload_hash_mismatch')
        p = json.loads(raw)
        if p['schema'] != 1 or p['accepted_version_id'] != job['accepted_version_id']:
            raise ExportError('payload_identity_mismatch')
        sheet_id, ledger_id, row = job['sheet_id'], job['ledger_sheet_id'], job['ledger_row']
        if any(type(n) is not int or not 0 <= n <= 2147483647 for n in (sheet_id, ledger_id, row)) or sheet_id == ledger_id:
            raise ExportError('configuration_invalid')
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,200}', job['spreadsheet_id']):
            raise ExportError('configuration_invalid')
        game, kind = p['game'], p['dataset_type']
        grid = [['TeamStats accepted version', p['accepted_version_id'], job['payload_sha256']],
                ['Game ID', game['id'], 'Date', game['date'], 'Opponent', game['opponent']],
                ['Home/away', game['home_away'], 'Game type', game['game_type']],
                ['Dataset', kind, 'Generation', str(p['publication_generation']), 'Revision', str(p['revision'])]]
        # Identity, labels and user inputs are all stringValue; no formula parsing.
        roster = {r['id']: r for r in p['roster']}
        missing = lambda v: 'Not entered' if v is None else str(v)
        if kind in ('box_scores', 'player_paint_touches'):
            fields = BOX_FIELDS if kind == 'box_scores' else ('total',)
            grid.append(['Player ID', 'Roster version', 'Player', 'Jersey'] + [FIELD_LABELS[f] for f in fields])
            for record in p['records']:
                r = roster[record['playerID']]
                values = record['values'] if kind == 'box_scores' else record
                grid.append([r['id'], str(r['version']), r['display_name'], r['jersey_number']] +
                            [missing(values.get(f)) for f in fields])
        elif kind in ('our_possessions', 'opponent_possessions'):
            grid.append(['Possession ID', 'Team', 'Number', 'Turnover'] + [FIELD_LABELS[f] for f in POSSESSION_FIELDS])
            for record in sorted(p['records'], key=lambda r: r['number']):
                turnover = record.get('turnover')
                grid.append([record['id'], record['team'], str(record['number']),
                             'Not entered' if turnover is None else ('Yes' if turnover else 'No')] +
                            [missing(record['values'].get(f)) for f in POSSESSION_FIELDS])
        else:
            raise ExportError('payload_identity_mismatch')
        if len(grid) > 10000:
            raise ExportError('payload_too_large')
        width = max(map(len, grid))
        grid = [r + [' '] * (width - len(r)) for r in grid]
        # Numeric generation is a literal decimal padded for stable lexical ordering.
        ledger = [game['id'], kind, str(p['publication_generation']).zfill(20),
                  p['accepted_version_id'], job['payload_sha256'], str(sheet_id),
                  'Accepted_' + p['accepted_version_id'], str(p['revision'])]
        return grid, ledger
    except ExportError:
        raise
    except (KeyError, TypeError, ValueError):
        raise ExportError('payload_identity_mismatch') from None

class Backend:
    """PostgREST execution transport; credential acquisition belongs to trusted runtime."""
    def __init__(self, endpoint, service_token, timeout=15, *, api_key=None):
        url = urllib.parse.urlparse(endpoint)
        if not ((url.scheme == 'https' and url.hostname and url.hostname.endswith('.supabase.co')) or
                (url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost', '::1'))):
            raise ExportError('configuration_invalid')
        if url.username or url.password or url.query or url.fragment or not 0 < timeout <= 30:
            raise ExportError('configuration_invalid')
        if not isinstance(service_token,str) or not service_token or (api_key is not None and
                (not isinstance(api_key,str) or not api_key)):
            raise ExportError('configuration_invalid')
        self.api_key = service_token if api_key is None else api_key  # Legacy constructor compatibility only.
        self.budget = None
        self.endpoint, self.token, self.timeout = endpoint.rstrip('/'), service_token, timeout
        self.opener = urllib.request.build_opener(_NoRedirect(), DeadlineHTTPHandler(), DeadlineHTTPSHandler())

    def rpc(self, name, arguments):
        names = ('stats_export_claim', 'stats_export_claimed_reserve', 'stats_export_acknowledge', 'stats_export_record_failure')
        if name not in names:
            raise ExportError('configuration_invalid')
        req = urllib.request.Request(self.endpoint + '/rpc/' + name, method='POST',
            data=json.dumps(arguments).encode(), headers={'Content-Type': 'application/json',
            'apikey': self.api_key, 'Authorization': 'Bearer ' + self.token})
        try:
            with self.opener.open(req, timeout=self.budget.remaining(self.timeout) if self.budget else self.timeout) as response:
                data = response.read(5_000_001)
            if len(data) > 5_000_000:
                raise ExportError('backend_response')
            return json.loads(data)
        except urllib.error.HTTPError as error:
            try:
                if error.code in (401,403): raise ExportError('backend_denied')
                code=json.loads(error.read(8192)).get('code')
                mapped={'55000':'destination_unavailable','54000':'destination_capacity','PT409':'claim_lost','42501':'backend_denied'}
                reason=mapped.get(code,'configuration_invalid' if error.code in (401,403) else 'backend_transport')
            except (ValueError,AttributeError): reason='backend_transport'
            finally: error.close()
            raise ExportError(reason) from None
        except (urllib.error.URLError, TimeoutError, ValueError):
            raise ExportError('backend_transport') from None

def run_once(backend, google, max_jobs=3, *, seconds=120, clock=time.monotonic):
    started = time.monotonic()
    try:
        outcomes = _run_once(backend, google, max_jobs, RunBudget(seconds,clock))
    except BaseException as error:
        cancelled = isinstance(error, (KeyboardInterrupt, SystemExit))
        invalid = isinstance(error, ExportError) and str(error) in ('configuration_invalid','budget_disabled')
        DIAGNOSTICS.record(Category.EXPORT, Outcome.FAILED if invalid else Outcome.UNCONFIRMED,
                           Failure.DISABLED if str(error)=='budget_disabled' else Failure.DENIED if str(error)=='backend_denied' else Failure.INVALID if invalid else Failure.CANCELLED if cancelled else Failure.UNAVAILABLE,
                           seconds=time.monotonic()-started)
        raise
    failures = [x for x in outcomes if x['state'] != 'delivered']
    codes={x.get('error_code') for x in failures}
    failure = (Failure.DISABLED if 'budget_disabled' in codes else Failure.DENIED if codes & {'provider_http_401','provider_http_403'}
        else Failure.INVALID if codes & {'configuration_invalid','payload_too_large','payload_hash_mismatch','payload_identity_mismatch','destination_conflict'}
        else Failure.CAPACITY if 'destination_capacity' in codes else Failure.UNAVAILABLE if failures else Failure.NONE)
    DIAGNOSTICS.record(Category.EXPORT, Outcome.FAILED if failures else Outcome.SUCCEEDED,
                       failure, seconds=time.monotonic()-started)
    return outcomes


def _run_once(backend, google, max_jobs, budget):
    """One job at a time; database claims and due times survive process exit."""
    if type(max_jobs) is not int or not 1 <= max_jobs <= 3:
        raise ExportError('configuration_invalid')
    google._guard()  # Disabled/stale budget or missing credentials never consume a claim.
    backend.budget=google.budget=budget
    google.remaining=google.config.request_limit
    outcomes=[]
    for _ in range(max_jobs):
        if budget.until-budget.clock()<5: break
        claim=backend.rpc('stats_export_claim',{})
        if claim is None: break
        try:
            job_id=str(uuid.UUID(claim['job_id'])); token=str(uuid.UUID(claim['claim_token']))
        except (KeyError,TypeError,ValueError): raise ExportError('backend_transport') from None
        arguments={'p_job_id':job_id,'p_claim_token':token}
        try:
            job=backend.rpc('stats_export_claimed_reserve',arguments)
            receipt=google.deliver(job)  # Preflight + complete readback before any resubmission.
            backend.rpc('stats_export_acknowledge',dict(arguments,p_receipt=receipt))
            outcomes.append({'job_id':job_id,'state':'delivered'})
        except ExportError as error:
            if str(error) in ('claim_lost','backend_denied'): raise  # A stale worker cannot update a successor.
            safe={'budget_disabled','configuration_invalid','request_limit','payload_too_large',
                'payload_hash_mismatch','payload_identity_mismatch','destination_conflict','destination_capacity',
                'destination_unavailable','provider_response','provider_timeout','provider_transport',
                'response_too_large','redirect_denied','backend_transport','run_deadline'}
            code=str(error)
            if code not in safe and not re.fullmatch(r'provider_http_[1-5][0-9]{2}',code): code='backend_transport'
            result=backend.rpc('stats_export_record_failure',dict(arguments,p_error_code=code,p_retry_after=error.retry_after))
            if result and result.get('state')=='delivered':
                outcomes.append({'job_id':job_id,'state':'delivered'})  # Lost acknowledgement, server-confirmed receipt.
            else: outcomes.append({'job_id':job_id,'state':'failed','error_code':code})
            if code in ('budget_disabled','configuration_invalid','provider_http_401','provider_http_403',
                        'provider_http_429','provider_timeout','provider_transport','backend_transport','run_deadline'):
                break  # A shared outage/throttle must not consume the rest of this invocation.
    return outcomes


def scheduler_once(config, backend, google, **bounds):
    """Disabled by default. One invocation only; installs no timer or recurring job."""
    if not isinstance(config,dict): raise ExportError('configuration_invalid')
    if config.get('scheduler_enabled') is not True: return {'state':'disabled'}
    return {'state':'processed','outcomes':run_once(backend,google,**bounds)}

def backend_from_config(config, environment):
    """Explicit credential selection; a missing worker credential never falls back."""
    mode=config.get('backend_credential_mode')
    if mode=='worker':
        bearer=environment.get('TEAMSTATS_EXPORT_WORKER_TOKEN','')
        key=environment.get('TEAMSTATS_SUPABASE_PUBLISHABLE_KEY','')
    elif mode=='legacy_service_role':
        bearer=key=environment.get('TEAMSTATS_EXPORT_SERVICE_TOKEN','')
    else: raise ExportError('configuration_invalid')
    return Backend(config.get('backend_rest_url',''),bearer,api_key=key)


def main():
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument('--config', help='private trusted runtime JSON configuration')
    parser.add_argument('--scheduled-once', action='store_true', help='disabled-by-default bounded scheduling entry; registers nothing')
    parser.add_argument('--status', action='store_true', help='passive readiness; no backend or Google requests')
    args = parser.parse_args()
    try:
        if args.status:
            config = {}
            if args.config:
                with open(args.config, encoding='utf-8') as handle: config = json.load(handle)
            if not isinstance(config, dict): raise ValueError()
            google = GoogleSheets(GoogleConfig(token=os.environ.get('TEAMSTATS_GOOGLE_ACCESS_TOKEN', ''),
                enabled=config.get('google_enabled', False), billing_disabled_verified_at=config.get('billing_disabled_verified_at', '')))
            permitted = False
            try: google._guard(); permitted = True
            except ExportError: pass
            enabled = config.get('google_enabled') is True
            configured = False
            if permitted:
                try: backend_from_config(config,os.environ); configured = True
                except ExportError: pass
            print(json.dumps(DIAGNOSTICS.availability(enabled=enabled, configured=configured)))
            return 3
        with open(args.config, encoding='utf-8') as handle:
            config = json.load(handle)
        if not isinstance(config, dict): raise ValueError()
        if args.scheduled_once and config.get('scheduler_enabled') is not True:
            print(json.dumps({'state':'disabled'})); return 3
        # Credentials are supplied by trusted environment injection, not JSON or CLI.
        backend = backend_from_config(config,os.environ)
        google = GoogleSheets(GoogleConfig(token=os.environ.get('TEAMSTATS_GOOGLE_ACCESS_TOKEN', ''),
            enabled=config.get('google_enabled', False),
            billing_disabled_verified_at=config.get('billing_disabled_verified_at', '')))
        outcomes = scheduler_once(config,backend,google)['outcomes'] if args.scheduled_once else run_once(backend,google)
        # Only totals/fixed error codes; no records, destinations, IDs or secrets.
        print(json.dumps({'delivered': sum(x['state'] == 'delivered' for x in outcomes),
                          'failed': sum(x['state'] == 'failed' for x in outcomes),
                          'errors': sorted({x['error_code'] for x in outcomes if 'error_code' in x})}))
    except KeyboardInterrupt:
        DIAGNOSTICS.record(Category.HEALTH, Outcome.CANCELLED, Failure.CANCELLED)
        return 130
    except Exception:
        DIAGNOSTICS.record(Category.HEALTH, Outcome.FAILED, Failure.UNAVAILABLE, attempts=0)
        print('Export stopped: configuration or backend unavailable', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    result = main()
    DIAGNOSTICS.flush()
    sys.exit(result)
