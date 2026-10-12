"""Actual bounded synthetic files through the trusted validator's stdin/stdout seam."""
import hashlib,json,os,signal,subprocess,sys,tempfile,time,unittest,zlib
from pathlib import Path

BINARY=os.environ.get("TEAMSTATS_MEDIA_VALIDATOR")
CLIPS=os.environ.get("TEAMSTATS_MEDIA_FIXTURES")

def pdf(content=b"0 0 1 rg 0 0 10 10 re f",extra=b"",compressed=False):
    if compressed: content=zlib.compress(content)
    objects=[b"<< /Type /Catalog /Pages 2 0 R "+extra+b" >>",b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R >>",
      b"<< /Length "+str(len(content)).encode()+ (b" /Filter /FlateDecode" if compressed else b"")+b" >>\nstream\n"+content+b"\nendstream"]
    data=b"%PDF-1.7\n"; offsets=[0]
    for n,obj in enumerate(objects,1):
        offsets.append(len(data));data+=str(n).encode()+b" 0 obj\n"+obj+b"\nendobj\n"
    start=len(data);data+=b"xref\n0 5\n0000000000 65535 f \n"
    for offset in offsets[1:]:data+=f"{offset:010d} 00000 n \n".encode()
    return data+b"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n"+str(start).encode()+b"\n%%EOF\n"

def external_media_reference(data, target):
    """Rewrite only the synthetic writer's dref while retaining original samples.
    Its mdat precedes moov, so changing moov size does not move chunk offsets.
    """
    changed=0
    def boxes(payload):
        nonlocal changed
        output=b"";offset=0
        while offset<len(payload):
            size=int.from_bytes(payload[offset:offset+4],"big");kind=payload[offset+4:offset+8];header=8
            if size==1:size=int.from_bytes(payload[offset+8:offset+16],"big");header=16
            elif size==0:size=len(payload)-offset
            if size<header or size>len(payload)-offset:raise ValueError("Synthetic MP4 box shape changed")
            body=payload[offset+header:offset+size]
            if kind in (b"moov",b"trak",b"mdia",b"minf",b"dinf"):body=boxes(body)
            elif kind==b"dref":body=body[:8]+boxes(body[8:])
            elif kind==b"url ":body=b"\0\0\0\0"+target.encode()+b"\0";changed+=1
            output+=((1).to_bytes(4,"big")+kind+(len(body)+16).to_bytes(8,"big") if header==16 else (len(body)+8).to_bytes(4,"big")+kind)+body;offset+=size
        return output
    if data.index(b"mdat")>data.index(b"moov"):raise ValueError("Synthetic fixture requires mdat before moov")
    result=boxes(data)
    if changed!=1:raise ValueError("Expected exactly one synthetic data reference")
    return result

def many_pages(count):
    objects=[b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids ["+b" ".join(f"{n+3} 0 R".encode() for n in range(count))+b"] /Count "+str(count).encode()+b" >>"]
    objects += [b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>"]*count
    data=b"%PDF-1.7\n";offsets=[]
    for n,obj in enumerate(objects,1):
        offsets.append(len(data));data+=f"{n} 0 obj\n".encode()+obj+b"\nendobj\n"
    start=len(data);data+=f"xref\n0 {len(objects)+1}\n0000000000 65535 f \n".encode()
    for offset in offsets:data+=f"{offset:010d} 00000 n \n".encode()
    return data+f"trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n".encode()


def owned_group_exists(group):
    result=subprocess.run(['/bin/ps','-eo','pgid='],capture_output=True,text=True,timeout=3)
    rows=result.stdout.split()
    if result.returncode!=0 or not rows or any(not value.isdecimal() for value in rows):
        raise RuntimeError("validator_group_monitor_unavailable")
    return str(group) in rows

def supervised_run(command, *, input=None, text=True, capture_output=True, timeout=35, env=None):
    """Bound the entire owned native-test group, not just its parent process."""
    if not capture_output:raise ValueError("Native validator tests require bounded captured diagnostics")
    process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                             text=text,env=env,start_new_session=True)
    try:
        output,diagnostics=process.communicate(input=input,timeout=timeout)
        if owned_group_exists(process.pid):raise RuntimeError("validator_child_process_unconfirmed")
        return subprocess.CompletedProcess(command,process.returncode,output,diagnostics)
    finally:
        # Also covers successful-parent/orphan paths. Do not return an observed
        # validator result until every owned descendant is stopped and reaped.
        try:os.killpg(process.pid,signal.SIGKILL)
        except ProcessLookupError:pass
        process.wait(timeout=3)
        process.communicate(timeout=3)
        deadline=time.monotonic()+3
        while True:
            if not owned_group_exists(process.pid):break
            if time.monotonic()>deadline:raise RuntimeError("validator_group_cleanup_unconfirmed")
            time.sleep(.01)

class ProcessSupervisionTests(unittest.TestCase):
    def run_fault(self, orphan=False):
        with tempfile.TemporaryDirectory(prefix="teamstats-test-process-") as directory:
            path=Path(directory)/"owned-pids"
            script="import os,subprocess,time;child=subprocess.Popen(['/bin/sleep','30'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);open("+repr(str(path))+",'w').write(str(os.getpid())+' '+str(child.pid));"+("print('SYNTHETIC completed parent')" if orphan else "time.sleep(30)")
            try:
                if orphan:
                    with self.assertRaisesRegex(RuntimeError,'validator_child_process_unconfirmed'):
                        supervised_run([sys.executable,'-c',script],timeout=2)
                else:
                    with self.assertRaises(subprocess.TimeoutExpired):
                        supervised_run([sys.executable,'-c',script],timeout=.5)
                parent,child=map(int,path.read_text().split())
                for pid in (parent,child):
                    with self.assertRaises(ProcessLookupError):os.kill(pid,0)
            finally:
                if path.exists():
                    parent=int(path.read_text().split()[0])
                    try:os.killpg(parent,signal.SIGKILL)
                    except ProcessLookupError:pass
    def test_timed_out_native_test_cannot_leave_renderer_running(self):self.run_fault()
    def test_parent_exit_with_renderer_cannot_claim_finished_validation(self):self.run_fault(orphan=True)

class MediaValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="teamstats-validator-test-")
        self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
    def validate(self,data,kind="scouting",name="synthetic.pdf"):
        path=self.root/name;path.write_bytes(data)
        process=supervised_run([BINARY],input=json.dumps({"path":str(path),"kind":kind}),text=True,capture_output=True,timeout=35)
        self.assertEqual(process.returncode,0)
        result=json.loads(process.stdout);self.assertNotIn(str(path),process.stdout)
        return result
    def test_readable_pdf_has_authoritative_hash_and_length(self):
        data=pdf();result=self.validate(data)
        self.assertTrue(result["valid"]);self.assertEqual(result["media_type"],"application/pdf")
        self.assertEqual(result["byte_count"],len(data));self.assertEqual(result["sha256"],hashlib.sha256(data).hexdigest())
        self.assertEqual(result["details"]["page_count"],1)

    def test_pdf_exact_five_mib_and_one_byte_over(self):
        target=5*1024*1024
        content=b"%"+b"x"*(target-1000)+b"\n"
        for _ in range(3):
            size=len(pdf(content));content=b"%"+b"x"*(len(content)-2+target-size)+b"\n"
        data=pdf(content);self.assertEqual(len(data),target)
        self.assertTrue(self.validate(data)["valid"])
        self.assertFalse(self.validate(data+b" ")["valid"])

    def test_plain_compressed_pdf_is_rendered(self):
        self.assertTrue(self.validate(pdf(compressed=True))["valid"])

    def test_script_and_embedded_files_are_rejected(self):
        for extra in [b"/OpenAction << /S /JavaScript /JS (alert\\(1\\)) >>",b"/Names << /EmbeddedFiles << /Names [] >> >>",b"/AcroForm << /Fields [] >>",b"/Names << /J#61vaScript << /Names [] >> >>"]:
            with self.subTest(extra=extra):
                result=self.validate(pdf(extra=extra))
                self.assertFalse(result["valid"]);self.assertEqual(result["failure_reason"],"active_pdf")

    def test_pdf_over_size_missing_and_nonpdf_are_rejected(self):
        for data in [b"",b"not PDF",b"%PDF-"+b" "*(5*1024*1024)]:
            with self.subTest(length=len(data)):
                self.assertFalse(self.validate(data)["valid"])

    def test_source_is_preserved_and_symlink_is_not_followed(self):
        data=pdf();source=self.root/"source.pdf";source.write_bytes(data)
        link=self.root/"link.pdf";link.symlink_to(source)
        process=supervised_run([BINARY],input=json.dumps({"path":str(link),"kind":"scouting"}),text=True,capture_output=True,timeout=35)
        self.assertFalse(json.loads(process.stdout)["valid"])
        self.assertEqual(source.read_bytes(),data)

    def test_development_pdf_page_resource_bound_is_honest(self):
        result=self.validate(many_pages(501))
        self.assertFalse(result["valid"]);self.assertEqual(result["failure_reason"],"resource_limit")

    def test_malformed_structure_and_invalid_requests_are_rejected(self):
        for data in [pdf()[:-30],pdf().replace(b"/Count 1",b"/Count 0")]:
            with self.subTest(length=len(data)):
                self.assertFalse(self.validate(data)["valid"])
        for request in ["{}","not JSON","x"*16385,json.dumps({"path":"/unused", "kind":"film"})]:
            with self.subTest(request_size=len(request)):
                process=supervised_run([BINARY],input=request,text=True,capture_output=True,timeout=35)
                result=json.loads(process.stdout);self.assertFalse(result["valid"])
                self.assertNotIn("/unused",process.stdout)

    def test_unconfigured_or_mismatched_renderer_fails_closed(self):
        source=self.root/"synthetic.pdf";source.write_bytes(pdf())
        for env in [dict(os.environ,TEAMSTATS_PDF_RENDERER=""),dict(os.environ,TEAMSTATS_PDF_RENDERER_SHA256="0"*64)]:
            with self.subTest(configured=bool(env.get("TEAMSTATS_PDF_RENDERER"))):
                process=supervised_run([BINARY],input=json.dumps({"path":str(source),"kind":"scouting"}),text=True,capture_output=True,env=env,timeout=35)
                result=json.loads(process.stdout);self.assertFalse(result["valid"])
                self.assertEqual(result["failure_reason"],"validator_unavailable")

    @unittest.skipUnless(CLIPS, "Actual synthetic native fixtures must be configured")
    def test_password_encrypted_pdf_is_rejected(self):
        result=self.validate((Path(CLIPS)/"encrypted.pdf").read_bytes())
        self.assertFalse(result["valid"]);self.assertEqual(result["failure_reason"],"encrypted_pdf")

    @unittest.skipUnless(CLIPS, "Actual synthetic native clips must be configured")
    def test_optional_aac_audio_is_fully_decoded(self):
        result=self.validate((Path(CLIPS)/"h264-aac.mp4").read_bytes(),kind="practice",name="synthetic.mp4")
        self.assertTrue(result["valid"]);self.assertGreater(result["details"]["decoded_audio_buffers"],0)

    @unittest.skipUnless(CLIPS, "Actual synthetic native clips must be configured")
    def test_h264_mp4_is_fully_decoded(self):
        result=self.validate((Path(CLIPS)/"h264.mp4").read_bytes(),kind="practice",name="synthetic.mp4")
        self.assertTrue(result["valid"])
        self.assertEqual(result["media_type"],"video/mp4")
        self.assertEqual(result["details"]["decoded_video_frames"],3)

    @unittest.skipUnless(CLIPS, "Actual synthetic native clips must be configured")
    def test_external_local_media_reference_cannot_establish_uploaded_byte_receipt(self):
        data=(Path(CLIPS)/"h264.mp4").read_bytes()
        external=self.root/"outside-container.mp4";external.write_bytes(data)
        reference=external_media_reference(data,external.as_uri())
        result=self.validate(reference,kind="practice",name="reference.mp4")
        self.assertFalse(result["valid"])
        self.assertNotIn("sha256",result)
        self.assertEqual(external.read_bytes(),data)

    @unittest.skipUnless(CLIPS, "Actual synthetic native clips must be configured")
    def test_portrait_h264_is_fully_decoded_without_rotation(self):
        data=(Path(CLIPS)/"portrait-h264.mp4").read_bytes()
        result=self.validate(data,kind="practice",name="synthetic.mp4")
        self.assertTrue(result["valid"])
        self.assertEqual((result["details"]["width"],result["details"]["height"]),(1080,1920))
        self.assertEqual(result["sha256"],hashlib.sha256(data).hexdigest())

    @unittest.skipUnless(CLIPS, "Actual synthetic native clips must be configured")
    def test_unsupported_codec_duration_and_resolution_are_rejected(self):
        for name,reason in [("hevc.mp4","unsupported_codec"),("too-long.mp4","duration_limit"),("too-wide.mp4","dimensions_limit")]:
            with self.subTest(name=name):
                result=self.validate((Path(CLIPS)/name).read_bytes(),kind="practice",name="synthetic.mp4")
                self.assertFalse(result["valid"]);self.assertEqual(result["failure_reason"],reason)

    @unittest.skipUnless(CLIPS, "Actual synthetic native clips must be configured")
    def test_corrupt_and_truncated_video_are_not_metadata_successes(self):
        data=(Path(CLIPS)/"h264.mp4").read_bytes()
        location=data.index(b"mdat")+4
        size=int.from_bytes(data[location-8:location-4],"big")
        broken=data[:location]+b"!"*(size-8)+data[location+size-8:]
        for content in [data[:-20],broken,b"not MP4",b"x"*(10*1024*1024+1)]:
            with self.subTest(length=len(content)):
                self.assertFalse(self.validate(content,kind="practice",name="synthetic.mp4")["valid"])

    @unittest.skipUnless(CLIPS, "Actual synthetic native clips must be configured")
    def test_mp4_exact_ten_mib_and_one_byte_over(self):
        data=(Path(CLIPS)/"h264.mp4").read_bytes();padding=10*1024*1024-len(data)
        data+=padding.to_bytes(4,"big")+b"free"+b"\0"*(padding-8)
        self.assertEqual(len(data),10*1024*1024)
        self.assertTrue(self.validate(data,kind="practice",name="synthetic.mp4")["valid"])
        self.assertFalse(self.validate(data+b" ",kind="practice",name="synthetic.mp4")["valid"])

    def test_corrupt_compressed_page_stream_is_rejected(self):
        content=b"0 0 1 rg 0 0 10 10 re f";encoded=zlib.compress(content)
        corrupt=pdf(content,compressed=True).replace(encoded,b"!"*len(encoded))
        self.assertFalse(self.validate(corrupt)["valid"])

if __name__=="__main__":
    if not BINARY: raise SystemExit("Configure the locally compiled trusted validator binary")
    unittest.main()
