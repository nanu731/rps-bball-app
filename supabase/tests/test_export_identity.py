"""Synthetic credential transport; not signed PostgREST/Google acceptance."""
import unittest
from test_sheets_export import Fixture, job, worker

class ExportIdentityTests(unittest.TestCase):
    def test_dedicated_bearer_and_publishable_key_are_distinct(self):
        fixture=Fixture();self.addCleanup(fixture.close)
        backend=worker.Backend('http://127.0.0.1:'+str(fixture.server.server_port)+'/rest/v1',
            'SYNTHETIC_WORKER',api_key='SYNTHETIC_PUBLIC')
        self.assertIsNone(backend.rpc('stats_export_claim',{}))
        self.assertEqual(fixture.backend_headers,[('stats_export_claim','SYNTHETIC_PUBLIC','Bearer SYNTHETIC_WORKER')])

    def test_backend_denial_after_applied_provider_write_stops_without_further_rpc(self):
        fixture=Fixture('timeout_applied');self.addCleanup(fixture.close)
        fixture.backend_jobs=[job()];fixture.backend_denial='stats_export_acknowledge'
        backend=worker.Backend('http://127.0.0.1:'+str(fixture.server.server_port)+'/rest/v1','SYNTHETIC_WORKER',api_key='SYNTHETIC_PUBLIC')
        with self.assertRaisesRegex(worker.ExportError,'backend_denied'):
            worker.run_once(backend,worker.GoogleSheets(fixture.config(timeout=.03)))
        self.assertEqual([x[0] for x in fixture.backend_headers],['stats_export_claim','stats_export_claimed_reserve','stats_export_acknowledge'])
        self.assertEqual(len(fixture.batches),1)
        self.assertEqual(fixture.backend_states,{})
        # A later invocation has renewed authority; same immutable reservation is read back.
        fixture.backend_denial=None;fixture.claimed.clear();fixture.mode='success'
        backend=worker.Backend(backend.endpoint,'SYNTHETIC_RENEWED',api_key='SYNTHETIC_PUBLIC')
        self.assertEqual(worker.run_once(backend,worker.GoogleSheets(fixture.config())),[dict(job_id=job()['job_id'],state='delivered')])
        self.assertEqual(len(fixture.batches),1)

    def test_explicit_credential_mode_never_falls_back_to_service_token(self):
        env={'TEAMSTATS_EXPORT_SERVICE_TOKEN':'SYNTHETIC_BROAD'}
        config={'backend_rest_url':'http://127.0.0.1:1/rest/v1','backend_credential_mode':'worker'}
        with self.assertRaisesRegex(worker.ExportError,'configuration_invalid'):
            worker.backend_from_config(config,env)
        env.update(TEAMSTATS_EXPORT_WORKER_TOKEN='SYNTHETIC_WORKER',TEAMSTATS_SUPABASE_PUBLISHABLE_KEY='SYNTHETIC_PUBLIC')
        dedicated=worker.backend_from_config(config,env)
        self.assertEqual((dedicated.token,dedicated.api_key),('SYNTHETIC_WORKER','SYNTHETIC_PUBLIC'))
        config['backend_credential_mode']='legacy_service_role'
        legacy=worker.backend_from_config(config,env)
        self.assertEqual((legacy.token,legacy.api_key),('SYNTHETIC_BROAD','SYNTHETIC_BROAD'))
        for mode in (None,'unknown',True):
            config['backend_credential_mode']=mode
            with self.assertRaisesRegex(worker.ExportError,'configuration_invalid'):worker.backend_from_config(config,env)

    def test_backend_http_denial_is_honest_even_with_unexpected_body(self):
        fixture=Fixture();self.addCleanup(fixture.close)
        fixture.backend_denial='stats_export_claim';fixture.backend_denial_payload='SYNTHETIC unexpected provider body'
        backend=worker.Backend('http://127.0.0.1:'+str(fixture.server.server_port)+'/rest/v1','SYNTHETIC')
        for status in (401,403):
            fixture.backend_denial_status=status
            with self.assertRaisesRegex(worker.ExportError,'backend_denied'):backend.rpc('stats_export_claim',{})
        self.assertEqual(len(fixture.backend_headers),2)

    def test_google_denial_can_record_failure_without_claiming_more_work(self):
        for status in (401,403):
            fixture=Fixture('provider_'+str(status))
            try:
                fixture.backend_jobs=[job()]
                backend=worker.Backend('http://127.0.0.1:'+str(fixture.server.server_port)+'/rest/v1','SYNTHETIC_WORKER',api_key='SYNTHETIC_PUBLIC')
                result=worker.run_once(backend,worker.GoogleSheets(fixture.config()))
                self.assertEqual(result,[dict(job_id=job()['job_id'],state='failed',error_code='provider_http_'+str(status))])
                self.assertEqual([x[0] for x in fixture.backend_headers],['stats_export_claim','stats_export_claimed_reserve','stats_export_record_failure'])
                self.assertEqual(len(fixture.batches),0)
                fixture.mode='success';fixture.claimed.clear()
                self.assertEqual(worker.run_once(backend,worker.GoogleSheets(fixture.config())),[dict(job_id=job()['job_id'],state='delivered')])
                self.assertEqual(len(fixture.batches),1)
            finally:fixture.close()
