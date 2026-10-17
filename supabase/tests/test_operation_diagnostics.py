"""Synthetic public recording/output/status seams, no provider activation."""
import concurrent.futures
import io
import json
from pathlib import Path
import sys
import threading
import time
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from operation_diagnostics import Diagnostics, Category, Outcome, Failure
import sheets_export

def guarded_google():
    import datetime as dt
    return sheets_export.GoogleSheets(sheets_export.GoogleConfig(token='SYNTHETIC',enabled=True,
        billing_disabled_verified_at=dt.datetime.now(dt.timezone.utc).isoformat(),endpoint='http://127.0.0.1:1'))

class DiagnosticTests(unittest.TestCase):
    def test_actual_output_closed_fields_and_bounded_growth(self):
        out = io.StringIO(); now = [1000.0]
        d = Diagnostics(sink=lambda line: out.write(line+'\n'), clock=lambda: now[0])
        d.record(Category.FILE, Outcome.FAILED, Failure.DENIED)
        d.output.join()
        event = json.loads(out.getvalue())
        self.assertEqual(set(event), {'category','outcome','failure','duration_ms','attempts'})
        self.assertEqual(event['failure'], 'denied')
        sentinel = 'TEST ONLY token email@example.invalid /student.jpg?secret=canary'
        d.record(sentinel, Outcome.FAILED, sentinel)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda _: d.record(Category.FILE, Outcome.FAILED, Failure.UNAVAILABLE),range(1000)))
        d.output.join(); s=d.snapshot()
        self.assertEqual(len(s['events']),64); self.assertEqual(s['discarded'],937)
        self.assertNotIn(sentinel,out.getvalue()); self.assertLessEqual(len(out.getvalue().splitlines()),32)
        now[0] += 900; self.assertEqual(d.snapshot()['events'],[])
        print('TEST ONLY DIAGNOSTIC '+json.dumps(event,sort_keys=True))

    def test_blocked_and_failed_sinks_do_not_change_export_results(self):
        entered=threading.Event(); release=threading.Event()
        def sink(_): entered.set(); release.wait(2); raise OSError('TEST ONLY secret disk error')
        d=Diagnostics(sink=sink)
        d.record(Category.EXPORT,Outcome.FAILED,Failure.UNAVAILABLE); self.assertTrue(entered.wait(1))
        started=time.monotonic()
        for _ in range(1000): d.record(Category.FILE,Outcome.CANCELLED,Failure.CANCELLED)
        self.assertLess(d.output.qsize(),2)
        print('TEST ONLY DIAGNOSTIC 1000 blocked-sink events seconds=',time.monotonic()-started)
        release.set(); d.output.join(); self.assertGreater(d.snapshot()['sink_failures'],0)

    def test_readiness_is_not_inferred_from_liveness_config_or_old_failure(self):
        now=[1000.0]; d=Diagnostics(sink=lambda _:None,clock=lambda:now[0])
        self.assertEqual(d.availability(enabled=False,configured=False)['readiness'],'disabled')
        self.assertEqual(d.availability(enabled=True,configured=False)['readiness'],'configuration_unavailable')
        self.assertEqual(d.availability(enabled=True,configured=True)['readiness'],'not_verified')
        d.record(Category.FILE,Outcome.UNCONFIRMED,Failure.UNAVAILABLE)
        self.assertEqual(d.availability(enabled=True,configured=True)['readiness'],'downstream_unavailable')
        d.record(Category.FILE,Outcome.FAILED,Failure.INVALID)
        self.assertEqual(d.availability(enabled=True,configured=True)['dependency'],'recent_failure')
        now[0]+=60; self.assertEqual(d.availability(enabled=True,configured=True)['dependency'],'not_checked')

    def test_export_backend_failure_emits_sanitized_uncertainty(self):
        import unittest.mock
        d=Diagnostics(sink=lambda _:None)
        class Backend:
            def rpc(self,*args): raise sheets_export.ExportError('TEST ONLY secret token raw response')
        with unittest.mock.patch.object(sheets_export,'DIAGNOSTICS',d,create=True):
            with self.assertRaises(sheets_export.ExportError): sheets_export.run_once(Backend(),guarded_google())
        self.assertTrue(any(e['category']=='export_run' and e['outcome']=='unconfirmed' for e in d.snapshot()['events']))
        self.assertNotIn('secret',json.dumps(d.snapshot()))

class WorkerStatusTests(unittest.TestCase):
    def test_default_sink_does_not_hold_python_stderr_lock_at_shutdown(self):
        import subprocess
        script = r"""
import io,sys,threading,time,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
from operation_diagnostics import Diagnostics,Category,Outcome
class Blocked(io.RawIOBase):
    def writable(self):return True
    def write(self,data):time.sleep(5);return len(data)
sys.stderr=io.TextIOWrapper(io.BufferedWriter(Blocked(),buffer_size=16),line_buffering=True)
d=Diagnostics();d.record(Category.EXPORT,Outcome.SUCCEEDED)
until=time.monotonic()+1
while not d.flush() and time.monotonic()<until: pass
"""
        result=subprocess.run([sys.executable,'-c',script],cwd=Path(__file__).resolve().parents[1],
            capture_output=True,text=True,timeout=4)
        self.assertEqual(result.returncode,0,result.stderr)
        emitted=json.loads(result.stderr)
        self.assertEqual(emitted['category'],'export_run')
        self.assertEqual(set(emitted),{'category','outcome','failure','duration_ms','attempts'})

    def test_actual_cli_outputs_are_passive_and_do_not_echo_paths_or_unknown_arguments(self):
        import subprocess,os,tempfile,datetime
        root=Path(__file__).resolve().parents[1]
        env=dict(os.environ)
        for name in ['TEAMSTATS_GOOGLE_ACCESS_TOKEN','TEAMSTATS_EXPORT_SERVICE_TOKEN']: env.pop(name,None)
        for worker,expected in [('private_file_gateway.py','configuration_unavailable'),('sheets_export.py','disabled')]:
            result=subprocess.run([sys.executable,str(root/worker),'--status'],env=env,capture_output=True,text=True,timeout=3)
            self.assertEqual(result.returncode,3)
            report=json.loads(result.stdout); self.assertEqual(report['readiness'],expected)
            self.assertEqual(report['liveness'],'alive')
            bad=subprocess.run([sys.executable,str(root/worker),'--TEST_ONLY_SECRET_FILENAME'],env=env,capture_output=True,text=True,timeout=3)
            self.assertEqual(bad.returncode,2); self.assertNotIn('TEST_ONLY_SECRET_FILENAME',bad.stderr)
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'TEST_ONLY_PRIVATE_FILENAME.json'
            path.write_text(json.dumps({'google_enabled':True,'billing_disabled_verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}))
            result=subprocess.run([sys.executable,str(root/'sheets_export.py'),'--status','--config',str(path)],env=env,capture_output=True,text=True,timeout=3)
            self.assertEqual(json.loads(result.stdout)['readiness'],'configuration_unavailable')
            self.assertNotIn(path.name,result.stdout+result.stderr)

    def test_cancelled_run_is_unconfirmed_and_sink_failure_does_not_break_empty_run(self):
        from unittest.mock import patch
        d=Diagnostics(sink=lambda _: (_ for _ in ()).throw(OSError('TEST ONLY secret file error')))
        class Cancelled:
            def rpc(self,*args): raise KeyboardInterrupt()
        class Empty:
            def rpc(self,*args): return None
        with patch.object(sheets_export,'DIAGNOSTICS',d):
            with self.assertRaises(KeyboardInterrupt): sheets_export.run_once(Cancelled(),guarded_google())
            self.assertEqual(sheets_export.run_once(Empty(),guarded_google()),[])
        d.output.join()
        snapshot=d.snapshot()
        self.assertGreater(snapshot['sink_failures'],0)
        self.assertTrue(any(e['outcome']=='unconfirmed' and e['failure']=='cancelled' for e in snapshot['events']))
        self.assertNotIn('secret',json.dumps(snapshot))

if __name__ == '__main__': unittest.main()
