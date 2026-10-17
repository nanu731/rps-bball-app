"""Loopback-only trusted private-byte gateway; no hosted deployment or billing claim.

Privileged keys stay in an ignored 0600 configuration. Every user operation first
crosses the signed PostgREST command seam; service commands recheck its live session.
Actual Storage objects and an independently pinned validator establish receipts.
"""
from __future__ import annotations
import argparse
import functools
from operation_diagnostics import DIAGNOSTICS, Category, Outcome, Failure, SafeArgumentParser
import hashlib
import http.server
import json
import math
import os
from pathlib import Path
import re
import resource
import signal
import stat
import sys
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from http_deadline import DeadlineSocket, DeadlineHTTPHandler

MAX_BYTES = 10 * 1024 * 1024
BUCKET = 'teamstats-private'

class FileFailure(Exception):
    def __init__(self, code: str, status: int = 409, retry_after: int | None = None):
        self.code, self.status, self.retry_after = code, status, retry_after
        super().__init__(code)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise FileFailure('provider_redirect_denied', 502)


def identifier(value: str) -> str:
    try:
        parsed = uuid.UUID(value)
    except (ValueError, TypeError, AttributeError):
        raise FileFailure('invalid_identity', 400) from None
    if str(parsed) != value.lower():
        raise FileFailure('invalid_identity', 400)
    return str(parsed)

def loopback_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost', '::1') or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise FileFailure('local_endpoint_required', 503)
    return value.rstrip('/')

class Providers:
    """Actual HTTP adapter. Errors never expose provider bodies/keys/contacts."""
    def __init__(self, config: dict):
        self.rest = loopback_url(config['rest_url'])
        self.storage = loopback_url(config['storage_url'])
        self.public_key = config['publishable_key']
        self.service_key = config['service_role_key']
        self.timeout = 30
        self.opener = urllib.request.build_opener(NoRedirect(), DeadlineHTTPHandler())

    def request(self, url: str, method: str, data: bytes | None, headers: dict, maximum: int) -> bytes:
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                length = response.headers.get('Content-Length')
                if length and int(length) > maximum:
                    raise FileFailure('provider_response_too_large', 502)
                body = response.read(maximum + 1)
                if len(body) > maximum:
                    raise FileFailure('provider_response_too_large', 502)
                return body
        except urllib.error.HTTPError as error:
            try:
                if error.code in (401, 403):
                    raise FileFailure('access_denied', error.code) from None
                if error.code == 429:
                    wait = error.headers.get('Retry-After', '')
                    retry = int(wait) if re.fullmatch(r'[0-9]{1,4}', wait) and 1 <= int(wait) <= 3600 else None
                    raise FileFailure('rate_limited', 429, retry) from None
                # Only stable SQLSTATE is retained; raw SQL/provider details stay private.
                try:
                    error_body = json.loads(error.read(8192))
                    code = error_body.get('code')
                    missing_storage_key = code == 'NoSuchKey' and error_body.get('statusCode') in ('404', 404)
                except (ValueError, AttributeError):
                    code = None
                    missing_storage_key = False
                mapping = {'42501': ('access_denied', 403), '40001': ('reload_or_reconcile', 409), 'PT409': ('reload_or_reconcile', 409),
                           '22023': ('invalid_file_input', 422), 'P0001': ('capacity_unavailable', 503)}
                if error.code == 404 or missing_storage_key:
                    raise FileFailure('object_not_found', 404) from None
                if code in mapping:
                    raise FileFailure(*mapping[code]) from None
                raise FileFailure('provider_operation_unconfirmed', 502) from None
            finally:
                error.close()
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError):
            raise FileFailure('provider_operation_unconfirmed', 502) from None

    def rpc(self, name: str, arguments: dict, token: str | None = None) -> dict:
        key = self.public_key if token else self.service_key
        body = self.request(self.rest + '/rpc/' + name, 'POST', json.dumps(arguments).encode(),
                            {'Content-Type': 'application/json', 'apikey': key,
                             'Authorization': 'Bearer ' + (token or self.service_key)}, 16384)
        try:
            reply = json.loads(body)
        except ValueError:
            raise FileFailure('provider_response_invalid', 502) from None
        if not isinstance(reply, dict):
            raise FileFailure('provider_response_invalid', 502)
        return reply

    def object_url(self, path: str) -> str:
        parts = path.split('/')
        if len(parts) != 3 or any(identifier(part) != part for part in parts):
            raise FileFailure('trusted_object_identity_invalid', 502)
        return self.storage + '/object/' + BUCKET + '/' + path

    def put(self, path: str, data: bytes, content_type: str):
        # Storage's immutable insert path; never send x-upsert:true or overwrite.
        self.request(self.object_url(path), 'POST', data,
                     {'Authorization': 'Bearer ' + self.service_key, 'apikey': self.service_key,
                      'Content-Type': content_type, 'x-upsert': 'false'}, 8192)

    def get(self, path: str, maximum: int) -> bytes:
        url = self.object_url(path).replace('/object/', '/object/authenticated/', 1)
        return self.request(url, 'GET', None,
                            {'Authorization': 'Bearer ' + self.service_key, 'apikey': self.service_key}, maximum)

class TrustedValidator:
    """Pinned subprocess with deadline/process-group/RSS limits, one decode at a time."""
    def __init__(self, config: dict):
        self.command = Path(config['validator_path']).resolve()
        self.pin = config['validator_sha256']
        self.directory = Path(config['temporary_directory']).resolve()
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        if not self.command.is_file() or hashlib.sha256(self.command.read_bytes()).hexdigest() != self.pin:
            raise FileFailure('validator_pin_invalid', 503)
        self.environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'TMPDIR': str(self.directory)}
        for name in ('TEAMSTATS_PDF_RENDERER', 'TEAMSTATS_PDF_RENDERER_SHA256'):
            if name in config:
                self.environment[name] = str(config[name])
        self.lock = threading.BoundedSemaphore(1)

    @staticmethod
    def limits():
        resource.setrlimit(resource.RLIMIT_CPU, (45, 45))
        resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024 * 1024, 16 * 1024 * 1024))
        resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    @staticmethod
    def group_members(group: int) -> list[tuple[int, int]]:
        try:
            usage = subprocess.run(['/bin/ps', '-eo', 'pid=,pgid=,rss='], capture_output=True, text=True, timeout=3)
            if usage.returncode != 0 or not isinstance(usage.stdout, str) or not usage.stdout.strip():
                raise ValueError()
            members = []
            for line in usage.stdout.splitlines():
                parts = line.split()
                if len(parts) != 3 or any(not value.isdecimal() for value in parts):
                    raise ValueError()
                pid, pgid, rss = map(int, parts)
                if pgid == group:
                    members.append((pid, rss))
            return members
        except (OSError, subprocess.TimeoutExpired, ValueError):
            raise FileFailure('validation_monitor_unavailable', 503) from None

    def validate(self, kind: str, data: bytes) -> dict:
        if not self.lock.acquire(timeout=1):
            raise FileFailure('validator_busy', 503)
        lease_safe = True
        try:
            # Pin is rechecked before execution, not just at startup.
            if hashlib.sha256(self.command.read_bytes()).hexdigest() != self.pin:
                raise FileFailure('validator_pin_invalid', 503)
            with tempfile.NamedTemporaryFile(dir=self.directory, suffix='.input') as source:
                os.chmod(source.name, 0o600)
                source.write(data); source.flush()
                request = json.dumps({'path': source.name, 'kind': kind}).encode()
                # Files bound output without risking pipe deadlock. No raw output is logged.
                with tempfile.TemporaryFile(dir=self.directory) as output, tempfile.TemporaryFile(dir=self.directory) as diagnostics:
                    process = subprocess.Popen([str(self.command)], stdin=subprocess.PIPE, stdout=output, stderr=diagnostics,
                                               env=self.environment, start_new_session=True, preexec_fn=self.limits)
                    lease_safe = False
                    try:
                        process.stdin.write(request); process.stdin.close()
                        deadline = time.monotonic() + 60
                        while process.poll() is None:
                            members = self.group_members(process.pid)
                            if time.monotonic() > deadline or sum(rss for _, rss in members) > 512 * 1024:
                                raise FileFailure('validation_resource_limit', 422)
                            time.sleep(0.05)
                        if any(pid != process.pid for pid, _ in self.group_members(process.pid)):
                            raise FileFailure('validation_child_process_unconfirmed', 503)
                        output.seek(0); result = output.read(8193)
                        if process.returncode != 0 or len(result) > 8192:
                            raise FileFailure('validation_unavailable', 503)
                        try:
                            reply = json.loads(result)
                        except ValueError:
                            raise FileFailure('validation_unavailable', 503) from None
                        return verified_validation(kind, data, reply)
                    finally:
                        # Parent exit is not proof that renderer children exited. Always
                        # terminate the owned group and reap its parent before releasing
                        # the single-parser lease, including monitoring/output failures.
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait(timeout=3)
                        deadline = time.monotonic() + 3
                        while True:
                            try:
                                os.killpg(process.pid, 0)
                            except ProcessLookupError:
                                lease_safe = True
                                break
                            if time.monotonic() > deadline:
                                raise FileFailure('validation_cleanup_unconfirmed', 503)
                            time.sleep(0.01)
        finally:
            # Unconfirmed cleanup keeps this parser unavailable until operator restart.
            if lease_safe:
                self.lock.release()

def verified_validation(kind: str, data: bytes, reply: dict) -> dict:
    if not isinstance(reply, dict) or reply.get('valid') is not True:
        # Only allowlisted failure codes, never native/provider diagnostics.
        code = reply.get('failure_reason') if isinstance(reply, dict) else None
        allowed = {'unsupported_type', 'encrypted_pdf', 'malformed_file', 'resource_limit', 'unsupported_codec',
                   'duration_limit', 'dimension_limit', 'size_limit', 'active_content', 'unreadable_content',
                   'invalid_request', 'unreadable', 'invalid_pdf', 'active_pdf', 'validator_unavailable',
                   'invalid_video', 'dimensions_limit'}
        raise FileFailure(code if code in allowed else 'file_validation_failed', 503 if code=='validator_unavailable' else 422)
    digest = hashlib.sha256(data).hexdigest()
    media_type = 'application/pdf' if kind == 'scouting' else 'video/mp4'
    if type(reply.get('byte_count')) is not int or reply['byte_count'] != len(data) or reply.get('sha256') != digest or reply.get('media_type') != media_type:
        raise FileFailure('validator_receipt_mismatch', 422)
    details = reply.get('details')
    if not isinstance(details, dict):
        raise FileFailure('validator_receipt_mismatch', 422)
    # Normalize the pinned native validator's bounded integer decode report.
    if kind == 'scouting' and 'page_count' in details:
        details = {'pageCount': details['page_count']}
    elif kind == 'practice' and 'duration_milliseconds' in details:
        milliseconds = details.get('duration_milliseconds')
        video_frames, audio_buffers = details.get('decoded_video_frames'), details.get('decoded_audio_buffers')
        if type(milliseconds) is not int or type(video_frames) is not int or video_frames<1 or type(audio_buffers) is not int or audio_buffers<0:
            raise FileFailure('validator_receipt_mismatch', 422)
        details = {'duration': milliseconds / 1000, 'width': details.get('width'), 'height': details.get('height'),
                   'videoCodec': 'h264', 'audioCodec': 'aac' if audio_buffers>0 else None}
    if kind == 'scouting':
        pages = details.get('pageCount')
        if type(pages) is not int or not 1 <= pages <= 500:
            raise FileFailure('validator_receipt_mismatch', 422)
        details = {'pageCount': pages}
    else:
        duration, width, height = details.get('duration'), details.get('width'), details.get('height')
        if type(duration) not in (int, float) or not math.isfinite(duration) or not 0 < duration <= 30 or type(width) is not int or type(height) is not int or width<=0 or height<=0 or max(width,height)>1920 or min(width,height)>1080 or details.get('videoCodec') != 'h264' or details.get('audioCodec') not in (None, 'aac'):
            raise FileFailure('validator_receipt_mismatch', 422)
        details = {'duration': duration, 'width': width, 'height': height, 'videoCodec': 'h264', 'audioCodec': details.get('audioCodec')}
    return {'byte_count': len(data), 'sha256': digest, 'content_type': media_type, 'validation_details': details}

def observed_file(function):
    @functools.wraps(function)
    def call(*args, **kwargs):
        started = time.monotonic()
        try:
            result = function(*args, **kwargs)
        except BaseException as error:
            failure = Failure.UNAVAILABLE
            if isinstance(error, (KeyboardInterrupt, SystemExit)): failure = Failure.CANCELLED
            elif isinstance(error, FileFailure):
                if error.status in (401, 403): failure = Failure.DENIED
                elif error.status == 429 or error.code in {'private_file_capacity_unknown', 'capacity_unavailable'}: failure = Failure.CAPACITY
                elif 400 <= error.status < 500: failure = Failure.INVALID
            DIAGNOSTICS.record(Category.FILE,
                Outcome.UNCONFIRMED if failure in (Failure.UNAVAILABLE, Failure.CANCELLED) else Outcome.FAILED,
                failure, seconds=time.monotonic()-started)
            raise
        DIAGNOSTICS.record(Category.FILE, Outcome.SUCCEEDED, seconds=time.monotonic()-started)
        return result
    return call


class FileGateway:
    """Public byte seam used by HTTP and synthetic external-provider fixtures."""
    def __init__(self, providers: Providers, validator: TrustedValidator):
        self.providers, self.validator = providers, validator

    def admit(self, token: str):
        # Separate committed RPC: transfer failure/disconnect cannot refund admission.
        # Never replay this write after a missing reply, and never trust a client actor ID.
        reply = self.providers.rpc('file_request_admission', {}, token)
        if (set(reply) != {'allowed', 'retry_after'} or type(reply['allowed']) is not bool
                or type(reply['retry_after']) is not int):
            raise FileFailure('admission_unavailable', 503)
        if not reply['allowed']:
            if not 1 <= reply['retry_after'] <= 60:
                raise FileFailure('admission_unavailable', 503)
            raise FileFailure('rate_limited', 429, reply['retry_after'])
        if reply['retry_after'] != 0:
            raise FileFailure('admission_unavailable', 503)

    @observed_file
    def upload(self, token: str, operation: str, stream, length: int, reconcile: bool = False) -> dict:
        operation = identifier(operation)
        self.admit(token)
        self.providers.rpc('file_upload_access', {'p_operation_id': operation, 'p_reconcile': reconcile}, token)
        ticket = self.providers.rpc('file_worker_claim_upload', {'p_operation_id': operation, 'p_reconcile': reconcile})
        declared = ticket.get('declared_bytes')
        if type(declared) is not int or not 0 < declared <= MAX_BYTES:
            raise FileFailure('trusted_size_invalid', 502)
        if reconcile:
            try:
                data = self.providers.get(ticket['object_path'], declared)
            except FileFailure as failure:
                if failure.code == 'object_not_found':
                    self.providers.rpc('file_worker_missing', {'p_operation_id': operation})
                    raise FileFailure('upload_not_stored_start_new_operation', 409) from None
                raise
        else:
            if length != declared:
                raise FileFailure('upload_size_mismatch_reconcile', 422)
            data = stream.read(declared)
            if len(data) != declared:
                raise FileFailure('upload_interrupted_reconcile', 409)
        try:
            receipt = self.validator.validate(ticket['kind'], data)
        except FileFailure as failure:
            if failure.status == 422:
                self.providers.rpc('file_worker_finish', {'p_operation_id': operation, 'p_byte_count': None,
                                   'p_sha256': None, 'p_content_type': None, 'p_validation_details': None,
                                   'p_failure_reason': failure.code})
            raise
        if not reconcile:
            self.providers.put(ticket['object_path'], data, receipt['content_type'])
            stored = self.providers.get(ticket['object_path'], declared)
            if len(stored) != len(data) or hashlib.sha256(stored).hexdigest() != receipt['sha256']:
                raise FileFailure('durable_bytes_unconfirmed_reconcile', 502)
        # No client hash, MIME or PUT-success string becomes the trusted receipt.
        return self.providers.rpc('file_worker_finish', dict(p_operation_id=operation,
                                  p_byte_count=receipt['byte_count'], p_sha256=receipt['sha256'],
                                  p_content_type=receipt['content_type'], p_validation_details=receipt['validation_details']))

    @observed_file
    def download(self, token: str, version: str, operation: str) -> tuple[bytes, dict]:
        self.admit(token)
        version, operation = identifier(version), identifier(operation)
        ticket = self.providers.rpc('file_delivery', {'p_team_id': self.team_for_version(token, version),
                                   'p_version_id': version, 'p_operation_id': operation}, token)
        trusted = self.providers.rpc('file_worker_claim_delivery', {'p_operation_id': operation})
        if trusted.get('version_id') != version or ticket.get('version_id') != version:
            raise FileFailure('delivery_identity_invalid', 502)
        count = trusted.get('byte_count')
        if type(count) is not int or not 0 < count <= MAX_BYTES:
            raise FileFailure('trusted_size_invalid', 502)
        data = self.providers.get(trusted['object_path'], count)
        if len(data) != count or hashlib.sha256(data).hexdigest() != trusted.get('sha256'):
            raise FileFailure('delivery_integrity_failed', 502)
        return data, trusted

    def team_for_version(self, token: str, version: str) -> str:
        # Filtered RLS read, not an arbitrary caller-supplied owner identity.
        body = self.providers.request(self.providers.rest + '/file_resource_versions?id=eq.' + version + '&select=team_id&limit=1',
                                      'GET', None, {'apikey': self.providers.public_key, 'Authorization': 'Bearer ' + token}, 4096)
        try:
            rows = json.loads(body)
            if not isinstance(rows, list) or len(rows) != 1:
                raise ValueError()
            return identifier(rows[0]['team_id'])
        except (ValueError, KeyError, TypeError):
            raise FileFailure('access_denied', 403) from None

def serve(gateway: FileGateway, port: int):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'
        def setup(self):
            super().setup()
            self.connection.settimeout(30)  # Includes request-line/header parsing.
        def log_message(self, *args):
            pass  # Never log tokens, user identities, storage paths or provider diagnostics.
        def respond(self, status: int, body: bytes, content_type: str = 'application/json', digest: str | None = None, retry_after: int | None = None):
            self.send_response(status); self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body))); self.send_header('Cache-Control', 'no-store')
            self.send_header('Connection', 'close')
            if digest: self.send_header('X-TeamStats-SHA256', digest)
            if retry_after is not None: self.send_header('Retry-After', str(retry_after))
            self.end_headers(); self.wfile.write(body); self.close_connection = True
        def perform(self):
            try:
                self.connection.settimeout(30)
                if self.command == 'GET' and self.path == '/health/live':
                    self.respond(200, b'{"liveness":"alive"}'); return
                if self.command == 'GET' and self.path == '/health/ready':
                    status = DIAGNOSTICS.availability(enabled=True, configured=True)
                    status['hosted_delivery'] = 'disabled'
                    self.respond(503, json.dumps(status).encode()); return
                authorization = self.headers.get('Authorization', '')
                if not authorization.startswith('Bearer ') or len(authorization) > 16384:
                    raise FileFailure('verified_session_required', 401)
                token = authorization[7:]
                parsed = urllib.parse.urlsplit(self.path)
                parts = parsed.path.strip('/').split('/')
                if self.command == 'POST' and len(parts) in (2, 3) and parts[0] == 'uploads' and not parsed.query:
                    reconcile = len(parts) == 3 and parts[2] == 'reconcile'
                    if len(parts) == 3 and not reconcile: raise FileFailure('route_not_found', 404)
                    length_text = self.headers.get('Content-Length', '')
                    if not re.fullmatch(r'[0-9]{1,9}', length_text) or self.headers.get('Transfer-Encoding'):
                        raise FileFailure('bounded_content_length_required', 411)
                    length = int(length_text)
                    if length > MAX_BYTES or (reconcile and length != 0): raise FileFailure('upload_size_limit', 413)
                    reply = gateway.upload(token, parts[1], self.rfile, length, reconcile)
                    self.respond(200, json.dumps(reply).encode())
                elif self.command == 'GET' and len(parts) == 2 and parts[0] == 'files':
                    query = urllib.parse.parse_qs(parsed.query)
                    if set(query) != {'operation'} or len(query['operation']) != 1: raise FileFailure('delivery_operation_required', 400)
                    data, receipt = gateway.download(token, parts[1], query['operation'][0])
                    self.respond(200, data, receipt['content_type'], receipt['sha256'])
                else: raise FileFailure('route_not_found', 404)
            except FileFailure as failure:
                self.respond(failure.status, json.dumps({'error': failure.code}).encode(), retry_after=failure.retry_after)
            except (KeyError, TypeError, ValueError, OSError, TimeoutError):
                self.respond(503, b'{"error":"operation_unconfirmed_reconcile"}')
        do_POST = perform
        do_GET = perform
    # Bound parallel request bodies/thread count; parser concurrency is separately one.
    class Server(http.server.HTTPServer):
        def handle_error(self, request, client_address):
            # HTTPServer's default traceback can include arbitrary exception text.
            DIAGNOSTICS.record(Category.FILE, Outcome.UNCONFIRMED, Failure.UNAVAILABLE)
        def get_request(self):
            connection, address = super().get_request()
            return DeadlineSocket.wrap(connection, time.monotonic() + 90), address
    Server(('127.0.0.1', port), Handler).serve_forever()

def main():
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--status', action='store_true', help='passive local prerequisites; no provider probes')
    args = parser.parse_args()
    try:
        if args.config is None:
            if args.status:
                print(json.dumps(DIAGNOSTICS.availability(enabled=True, configured=False)))
                return 3
            raise ValueError()
        permissions = args.config.stat()
        if not stat.S_ISREG(permissions.st_mode) or permissions.st_mode & 0o077:
            raise ValueError()
        config = json.loads(args.config.read_text())
        if not isinstance(config, dict): raise ValueError()
        if config.get('mode') != 'isolated_local' or config.get('hosted_enabled') is not False:
            raise ValueError()
        if args.status:
            configured = all(bool(config.get(key)) for key in
                ('rest_url', 'storage_url', 'publishable_key', 'service_role_key', 'validator_path', 'validator_sha256', 'temporary_directory'))
            report = DIAGNOSTICS.availability(enabled=True, configured=configured)
            report['hosted_delivery'] = 'disabled'
            print(json.dumps(report))
            return 3  # Presence alone never establishes delivery readiness.
        port = config.get('listen_port')
        if type(port) is not int or not 1024 <= port <= 65535:
            raise ValueError()
        serve(FileGateway(Providers(config), TrustedValidator(config)), port)
    except KeyboardInterrupt:
        DIAGNOSTICS.record(Category.HEALTH, Outcome.CANCELLED, Failure.CANCELLED)
        return 130
    except Exception:
        DIAGNOSTICS.record(Category.HEALTH, Outcome.FAILED, Failure.UNAVAILABLE, attempts=0)
        print('Worker unavailable: check private local prerequisites.', file=sys.stderr)
        return 1

if __name__ == '__main__':
    result = main()
    DIAGNOSTICS.flush()
    raise SystemExit(result)
