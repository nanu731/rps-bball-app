"""Public gateway HTTP/validator seams with synthetic external-provider fixtures.

These tests verify transport/recovery/integrity, not real Storage or real PDF/video
content validation. The test subprocess deliberately recognizes only TEST bytes.
"""
import hashlib
import http.server
import importlib.util
import io
import json
import os
import socket
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import uuid

SPEC = importlib.util.spec_from_file_location('private_file_gateway', Path(__file__).parents[1] / 'private_file_gateway.py')
MODULE = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MODULE)
TEAM = 'f1000000-0000-4000-8000-000000000001'
RESOURCE = 'f2000000-0000-4000-8000-000000000001'
VERSION = 'f3000000-0000-4000-8000-000000000001'
OPERATION = 'f4000000-0000-4000-8000-000000000001'
PATH = TEAM + '/' + RESOURCE + '/' + VERSION
DATA = b'TEST ONLY synthetic readable file bytes'

class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.objects = {}; self.receipt = None; self.transfer_started = False
        self.revoked = False; self.uncertain_put = False; self.missing_get = False
        self.missing_http400 = False; self.corrupt_get = False; self.claimed = False; self.finish_count = 0; self.missing = False
        case = self
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def send(self, value, status=200):
                body = value if isinstance(value, bytes) else json.dumps(value).encode()
                self.send_response(status); self.send_header('Content-Length', str(len(body)));self.end_headers();self.wfile.write(body)
            def do_GET(self):
                if self.path.startswith('/rest/file_resource_versions?'):
                    self.send([] if case.revoked else [{'team_id':TEAM}]);return
                if self.path.startswith('/storage/object/'):
                    if case.missing_get or PATH not in case.objects:
                        self.send({'code':'NoSuchKey','statusCode':'404','error':'not_found'} if case.missing_http400 else {'error':'not found'},400 if case.missing_http400 else 404);return
                    self.send(b'WRONG' if case.corrupt_get else case.objects[PATH]);return
                self.send({},404)
            def do_POST(self):
                body = self.rfile.read(int(self.headers['Content-Length']))
                if self.path.startswith('/storage/object/'):
                    if self.headers.get('x-upsert') != 'false':self.send({'error':'overwrite'},400);return
                    if PATH in case.objects:self.send({'error':'duplicate'},409);return
                    case.objects[PATH] = body
                    if case.uncertain_put:self.send({'error':'lost reply'},500);return
                    self.send({'Key':'synthetic'});return
                args=json.loads(body); name=self.path.rsplit('/',1)[-1]
                if name=='file_upload_access':
                    if case.revoked:self.send({'code':'42501','message':'PRIVATE diagnostic must not escape'},403);return
                    self.send({'id':VERSION,'status':'uploading'});return
                if name=='file_worker_claim_upload':
                    if case.claimed and not args['p_reconcile']:self.send({'code':'PT409'},409);return
                    case.claimed=True
                    self.send({'version_id':VERSION,'team_id':TEAM,'kind':'scouting','object_path':PATH,'declared_bytes':len(DATA)});return
                if name=='file_worker_finish':
                    case.finish_count+=1
                    case.receipt={'id':VERSION,'status':'failed' if args.get('p_failure_reason') else 'ready',
                                  'byte_count':args['p_byte_count'],'sha256':args['p_sha256'],'content_type':args['p_content_type']}
                    self.send(case.receipt);return
                if name=='file_worker_missing':case.missing=True;self.send({'id':VERSION});return
                if name=='file_delivery':
                    if case.revoked:self.send({'code':'42501'},403);return
                    self.send({'version_id':VERSION,'operation_id':args['p_operation_id'],'byte_count':len(DATA),'sha256':hashlib.sha256(DATA).hexdigest(),'content_type':'application/pdf'});return
                if name=='file_worker_claim_delivery':
                    if case.transfer_started:self.send({'code':'42501'},403);return
                    case.transfer_started=True
                    self.send({'version_id':VERSION,'object_path':PATH,'byte_count':len(DATA),'sha256':hashlib.sha256(DATA).hexdigest(),'content_type':'application/pdf'});return
                self.send({},404)
        self.server=http.server.HTTPServer(('127.0.0.1',0),Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.temp=tempfile.TemporaryDirectory()
        self.validator_path=Path(self.temp.name)/'synthetic-validator'
        self.write_validator()
        base='http://127.0.0.1:'+str(self.server.server_port)
        self.config={'rest_url':base+'/rest','storage_url':base+'/storage','publishable_key':'SYNTHETIC PUBLIC',
                     'service_role_key':'SYNTHETIC SERVER ONLY','validator_path':str(self.validator_path),
                     'validator_sha256':hashlib.sha256(self.validator_path.read_bytes()).hexdigest(),'temporary_directory':self.temp.name}
        self.gateway=MODULE.FileGateway(MODULE.Providers(self.config),MODULE.TrustedValidator(self.config))
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.temp.cleanup()
    def write_validator(self, replacement=None):
        script="""#!/usr/bin/python3
import sys,json,pathlib,hashlib
request=json.load(sys.stdin);data=pathlib.Path(request['path']).read_bytes()
reply={'valid':True,'media_type':'application/pdf','byte_count':len(data),'sha256':hashlib.sha256(data).hexdigest(),'details':{'pageCount':1}}
"""
        if replacement:script+=replacement+'\n'
        script+='print(json.dumps(reply))\n'
        self.validator_path.write_text(script);self.validator_path.chmod(0o700)
    def failure(self, function, expected):
        with self.assertRaises(MODULE.FileFailure) as caught:function()
        self.assertEqual(caught.exception.code,expected)
    def upload(self):return self.gateway.upload('SYNTHETIC USER',OPERATION,io.BytesIO(DATA),len(DATA))
    def test_actual_http_put_and_readback_are_required_before_receipt(self):
        reply=self.upload();self.assertEqual(reply['status'],'ready');self.assertEqual(self.objects[PATH],DATA)
        self.assertEqual(reply['sha256'],hashlib.sha256(DATA).hexdigest())
    def test_lost_put_reply_requires_reconcile_and_never_overwrites(self):
        self.uncertain_put=True
        self.failure(self.upload,'provider_operation_unconfirmed');self.assertIsNone(self.receipt)
        reply=self.gateway.upload('SYNTHETIC USER',OPERATION,io.BytesIO(b''),0,True)
        self.assertEqual(reply['status'],'ready');self.assertEqual(self.objects[PATH],DATA)
    def test_blind_upload_retry_cannot_retransfer_uncertain_object(self):
        self.upload();self.failure(self.upload,'reload_or_reconcile');self.assertEqual(self.finish_count,1)
    def test_reconcile_missing_object_retains_identity_and_allows_fresh_attempt(self):
        self.failure(lambda:self.gateway.upload('SYNTHETIC USER',OPERATION,io.BytesIO(b''),0,True),'upload_not_stored_start_new_operation')
        self.assertTrue(self.missing);self.assertIsNone(self.receipt)
    def test_actual_storage_http400_no_such_key_shape_reconciles_missing_upload(self):
        self.missing_http400=True
        self.failure(lambda:self.gateway.upload('SYNTHETIC USER',OPERATION,io.BytesIO(b''),0,True),'upload_not_stored_start_new_operation')
        self.assertTrue(self.missing);self.assertIsNone(self.receipt)
    def test_corrupt_storage_readback_cannot_create_receipt(self):
        self.corrupt_get=True;self.failure(self.upload,'durable_bytes_unconfirmed_reconcile');self.assertIsNone(self.receipt)
    def test_short_upload_is_uncertain_without_byte_receipt(self):
        self.failure(lambda:self.gateway.upload('SYNTHETIC USER',OPERATION,io.BytesIO(DATA[:-1]),len(DATA)),'upload_interrupted_reconcile')
        self.assertEqual(self.objects,{});self.assertIsNone(self.receipt)
    def test_wrong_content_length_does_not_upload_or_correct_it(self):
        self.failure(lambda:self.gateway.upload('SYNTHETIC USER',OPERATION,io.BytesIO(DATA),len(DATA)-1),'upload_size_mismatch_reconcile')
        self.assertEqual(self.objects,{})
    def test_confirmed_denial_does_not_expose_private_diagnostics(self):
        self.revoked=True;self.failure(self.upload,'access_denied');self.assertEqual(self.objects,{})
    def test_complete_download_matches_actual_bytes_and_integrity(self):
        self.upload();data,receipt=self.gateway.download('SYNTHETIC USER',VERSION,str(uuid.uuid4()))
        self.assertEqual(data,DATA);self.assertEqual(receipt['byte_count'],len(DATA))
    def test_same_delivery_is_not_a_free_retransfer(self):
        self.upload();operation=str(uuid.uuid4());self.gateway.download('SYNTHETIC USER',VERSION,operation)
        self.failure(lambda:self.gateway.download('SYNTHETIC USER',VERSION,operation),'access_denied')
    def test_revocation_blocks_later_download_and_preserves_uploaded_bytes(self):
        self.upload();self.revoked=True
        self.failure(lambda:self.gateway.download('SYNTHETIC USER',VERSION,str(uuid.uuid4())),'access_denied')
        self.assertEqual(self.objects[PATH],DATA)
    def test_corrupted_download_never_reaches_player(self):
        self.upload();self.corrupt_get=True
        self.failure(lambda:self.gateway.download('SYNTHETIC USER',VERSION,str(uuid.uuid4())),'delivery_integrity_failed')
    def test_validator_pin_change_fails_closed(self):
        self.write_validator("reply['valid']=False")
        self.failure(self.upload,'validator_pin_invalid');self.assertEqual(self.objects,{})
    def test_validator_cannot_lie_about_actual_digest(self):
        self.write_validator("reply['sha256']='0'*64")
        config=dict(self.config,validator_sha256=hashlib.sha256(self.validator_path.read_bytes()).hexdigest())
        gateway=MODULE.FileGateway(MODULE.Providers(config),MODULE.TrustedValidator(config))
        self.failure(lambda:gateway.upload('SYNTHETIC USER',OPERATION,io.BytesIO(DATA),len(DATA)),'validator_receipt_mismatch')
        self.assertEqual(self.objects,{});self.assertEqual(self.receipt['status'],'failed')
    def monitor_failure(self, fault):
        pid_file=Path(self.temp.name)/'validator-child-pids'
        self.write_validator("import os,subprocess,time\nchild=subprocess.Popen(['/bin/sleep','30'])\nopen("+repr(str(pid_file))+",'w').write(str(os.getpid())+' '+str(child.pid))\ntime.sleep(30)")
        config=dict(self.config,validator_sha256=hashlib.sha256(self.validator_path.read_bytes()).hexdigest())
        validator=MODULE.TrustedValidator(config)
        real_run=subprocess.run
        def failed_monitor(command,*args,**kwargs):
            if command[0]=='/bin/ps':
                deadline=time.monotonic()+2
                while not pid_file.exists() and time.monotonic()<deadline:time.sleep(.01)
                if isinstance(fault,Exception):raise fault
                return fault
            return real_run(command,*args,**kwargs)
        try:
            with patch.object(MODULE.subprocess,'run',side_effect=failed_monitor):
                with self.assertRaises(MODULE.FileFailure) as caught:validator.validate('scouting',DATA)
                self.assertEqual(caught.exception.code,'validation_monitor_unavailable')
            parent,child=map(int,pid_file.read_text().split())
            for pid in (parent,child):
                with self.assertRaises(ProcessLookupError):os.kill(pid,0)
        finally:
            if pid_file.exists():
                parent=int(pid_file.read_text().split()[0])
                try:os.killpg(parent,signal.SIGKILL)
                except ProcessLookupError:pass
    def test_monitor_timeout_terminates_actual_child_group(self):
        self.monitor_failure(subprocess.TimeoutExpired(['/bin/ps'],3))
    def test_monitor_oserror_terminates_actual_child_group(self):
        self.monitor_failure(OSError('SYNTHETIC monitor unavailable'))
    def test_monitor_nonzero_exit_terminates_actual_child_group(self):
        self.monitor_failure(subprocess.CompletedProcess(['/bin/ps'],1,stdout=''))
    def test_monitor_malformed_rows_terminate_actual_child_group(self):
        self.monitor_failure(subprocess.CompletedProcess(['/bin/ps'],0,stdout='malformed row'))
    def test_orphan_renderer_is_not_a_successful_validation(self):
        pid_file=Path(self.temp.name)/'orphan-renderer'
        self.write_validator("import os,subprocess\nchild=subprocess.Popen(['/bin/sleep','30'])\nopen("+repr(str(pid_file))+",'w').write(str(os.getpid())+' '+str(child.pid))")
        config=dict(self.config,validator_sha256=hashlib.sha256(self.validator_path.read_bytes()).hexdigest())
        validator=MODULE.TrustedValidator(config)
        try:
            with self.assertRaises(MODULE.FileFailure) as caught:validator.validate('scouting',DATA)
            self.assertEqual(caught.exception.code,'validation_child_process_unconfirmed')
            parent,child=map(int,pid_file.read_text().split())
            for pid in (parent,child):
                with self.assertRaises(ProcessLookupError):os.kill(pid,0)
        finally:
            if pid_file.exists():
                parent=int(pid_file.read_text().split()[0])
                try:os.killpg(parent,signal.SIGKILL)
                except ProcessLookupError:pass

    def test_external_endpoint_configuration_is_denied(self):
        self.failure(lambda:MODULE.Providers(dict(self.config,rest_url='https://external.example.invalid/rest')),'local_endpoint_required')
    def test_credentials_in_endpoint_are_denied(self):
        self.failure(lambda:MODULE.Providers(dict(self.config,storage_url='http://user:secret@127.0.0.1/storage')),'local_endpoint_required')
    def test_http_upload_exact_length_reaches_response_without_waiting_for_eof(self):
        with socket.socket() as probe:
            probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
        config=dict(self.config,mode='isolated_local',hosted_enabled=False,listen_port=port)
        path=Path(self.temp.name)/'gateway.local.json';path.write_text(json.dumps(config));path.chmod(0o600)
        process=subprocess.Popen([sys.executable,str(Path(__file__).parents[1]/'private_file_gateway.py'),'--config',str(path)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            deadline=time.monotonic()+3
            while True:
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.1):break
                except OSError:
                    if time.monotonic()>deadline:self.fail('gateway did not start')
                    time.sleep(.03)
            request=urllib.request.Request('http://127.0.0.1:'+str(port)+'/uploads/'+OPERATION,data=DATA,
                                           headers={'Authorization':'Bearer SYNTHETIC USER'},method='POST')
            with urllib.request.urlopen(request,timeout=5) as response:
                self.assertEqual(response.status,200);self.assertEqual(json.load(response)['status'],'ready')
                self.assertEqual(response.headers['Cache-Control'],'no-store')
            self.assertEqual(self.objects[PATH],DATA)
        finally:
            process.terminate();process.wait(timeout=3)

    @unittest.skipUnless(os.environ.get('TEAMSTATS_MEDIA_VALIDATOR') and os.environ.get('TEAMSTATS_MEDIA_FIXTURES'), 'Actual pinned native validator/fixtures must be configured')
    def test_actual_portrait_clip_has_consistent_native_and_gateway_bounds(self):
        binary=Path(os.environ['TEAMSTATS_MEDIA_VALIDATOR'])
        config={'validator_path':str(binary),'validator_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'temporary_directory':self.temp.name}
        data=(Path(os.environ['TEAMSTATS_MEDIA_FIXTURES'])/'portrait-h264.mp4').read_bytes()
        receipt=MODULE.TrustedValidator(config).validate('practice',data)
        self.assertEqual((receipt['validation_details']['width'],receipt['validation_details']['height']),(1080,1920))
        self.assertEqual(receipt['sha256'],hashlib.sha256(data).hexdigest())

    def test_non_uuid_identity_cannot_inject_provider_path(self):
        self.failure(lambda:self.gateway.upload('SYNTHETIC USER','../other',io.BytesIO(DATA),len(DATA)),'invalid_identity')

if __name__=='__main__':unittest.main()
