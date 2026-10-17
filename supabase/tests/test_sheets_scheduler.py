"""Synthetic scheduler/transport behavior, never actual Google delivery."""
import datetime as dt
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import sheets_export as worker

class SchedulerTests(unittest.TestCase):
    def test_disabled_or_missing_setup_does_not_claim_or_spend_attempts(self):
        class Backend:
            def rpc(self,*args): raise AssertionError('Disabled entry reached backend')
        result=worker.scheduler_once({},Backend(),worker.GoogleSheets(worker.GoogleConfig()))
        self.assertEqual(result,{'state':'disabled'})
        with self.assertRaisesRegex(worker.ExportError,'budget_disabled'):
            worker.scheduler_once({'scheduler_enabled':True},Backend(),worker.GoogleSheets(worker.GoogleConfig()))

    def test_retry_after_seconds_dates_malformed_and_excessive(self):
        now=dt.datetime(2037,1,1,tzinfo=dt.timezone.utc)
        for raw,expected in [('120',120),('0',0),('Thu, 01 Jan 2037 00:02:00 GMT',120),
            ('Wed, 31 Dec 2036 23:59:00 GMT',0),('invalid secret',None),('-1',None),('',None),(None,None),('999999999',86401)]:
            self.assertEqual(worker.retry_after_seconds(raw,now),expected)

    def test_provider_date_prevents_fast_clock_from_shortening_retry_after(self):
        fast=dt.datetime(2038,1,1,tzinfo=dt.timezone.utc)
        self.assertEqual(worker.retry_after_seconds('Thu, 01 Jan 2037 00:02:00 GMT',fast,
            server_date='Thu, 01 Jan 2037 00:00:00 GMT'),120)

    def test_whole_run_budget_stops_new_work_and_bounds_transport(self):
        now=[0.0];budget=worker.RunBudget(10,lambda:now[0])
        self.assertEqual(budget.remaining(30,reserve=5),5)
        now[0]=10
        with self.assertRaisesRegex(worker.ExportError,'run_deadline'):budget.remaining()
        class Backend:
            def rpc(self,*args): raise AssertionError('No time left to claim')
        class Google:
            config=worker.GoogleConfig()
            def _guard(self): pass
        self.assertEqual(worker.run_once(Backend(),Google(),seconds=1,clock=lambda:0),[])

    def test_retry_after_survives_actual_http_throttle_and_readback(self):
        from test_sheets_export import Fixture,job
        fixture=Fixture('quota');fixture.retry_after='120'
        try:
            with self.assertRaises(worker.ExportError) as caught:
                worker.GoogleSheets(fixture.config()).deliver(job())
            self.assertEqual(str(caught.exception),'provider_http_429')
            self.assertEqual(caught.exception.retry_after,120)
        finally:fixture.server.shutdown();fixture.server.server_close()

    def test_global_throttle_stops_this_invocation_without_claiming_other_jobs(self):
        import uuid
        from test_sheets_export import Fixture,job
        fixture=Fixture('quota')
        fixture.backend_jobs=[dict(job(),job_id=str(uuid.uuid4())) for _ in range(4)]
        try:
            backend=worker.Backend('http://127.0.0.1:'+str(fixture.server.server_port)+'/rest/v1','SYNTHETIC')
            result=worker.run_once(backend,worker.GoogleSheets(fixture.config()))
            self.assertEqual(len(result),1)
            self.assertEqual(len(fixture.claimed),1)
        finally:fixture.server.shutdown();fixture.server.server_close()

    def test_maximum_jobs_and_disabled_cli(self):
        import json,os,subprocess,tempfile,uuid
        class Backend:
            claimed=0
            def rpc(self,name,arguments):
                if name=='stats_export_claim':
                    self.claimed+=1;return dict(job_id=str(uuid.uuid4()),claim_token=str(uuid.uuid4()))
                if name=='stats_export_claimed_reserve':return {}
        class Google:
            config=worker.GoogleConfig()
            def _guard(self):pass
            def deliver(self,job):return {}
        backend=Backend();self.assertEqual(len(worker.run_once(backend,Google())),3);self.assertEqual(backend.claimed,3)
        with self.assertRaisesRegex(worker.ExportError,'configuration_invalid'):worker.run_once(backend,Google(),max_jobs=4)
        env={k:v for k,v in os.environ.items() if k not in ['TEAMSTATS_EXPORT_SERVICE_TOKEN','TEAMSTATS_GOOGLE_ACCESS_TOKEN']}
        with tempfile.TemporaryDirectory() as directory:
            config=Path(directory)/'synthetic.json';config.write_text('{}')
            result=subprocess.run([sys.executable,str(Path(worker.__file__)),'--scheduled-once','--config',str(config)],env=env,capture_output=True,text=True,timeout=3)
            self.assertEqual(result.returncode,3);self.assertEqual(json.loads(result.stdout),{'state':'disabled'})
            self.assertEqual(result.stderr,'')

if __name__=='__main__':unittest.main()
