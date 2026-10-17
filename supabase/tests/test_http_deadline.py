"""Actual isolated TLS/HTTP streams, not external provider integration."""
import http.server
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from http_deadline import DeadlineHTTPSHandler

@unittest.skipUnless(shutil.which('openssl'),'Existing OpenSSL tool unavailable for synthetic TLS certificate')
class TLSDeadlineTests(unittest.TestCase):
    def test_tls_verification_and_absolute_response_deadline(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder); key=folder/'key.pem'; cert=folder/'cert.pem'
            subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),
                '-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost'],check=True,capture_output=True)
            class Handler(http.server.BaseHTTPRequestHandler):
                def log_message(self,*args): pass
                def do_GET(self):
                    self.send_response(200);self.send_header('Content-Length','10');self.end_headers()
                    try:
                        for _ in range(10):
                            self.wfile.write(b'x');self.wfile.flush()
                            if self.path=='/slow':time.sleep(.02)
                    except (OSError,ssl.SSLError):pass
            server=http.server.HTTPServer(('127.0.0.1',0),Handler)
            context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(cert,key)
            server.socket=context.wrap_socket(server.socket,server_side=True)
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            try:
                trusted=ssl.create_default_context(cafile=str(cert))
                opener=urllib.request.build_opener(DeadlineHTTPSHandler(context=trusted))
                base='https://localhost:'+str(server.server_port)
                with opener.open(base+'/normal',timeout=2) as response:self.assertEqual(response.read(100),b'xxxxxxxxxx')
                with self.assertRaises(TimeoutError):
                    with opener.open(base+'/slow',timeout=.08) as response:response.read(100)
            finally:
                server.shutdown();server.server_close();thread.join()
