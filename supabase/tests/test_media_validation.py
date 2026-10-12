"""Actual bounded synthetic files through the trusted validator's stdin/stdout seam."""
import hashlib,json,os,subprocess,tempfile,unittest,zlib
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

class MediaValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="teamstats-validator-test-")
        self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
    def validate(self,data,kind="scouting",name="synthetic.pdf"):
        path=self.root/name;path.write_bytes(data)
        process=subprocess.run([BINARY],input=json.dumps({"path":str(path),"kind":kind}),text=True,capture_output=True,timeout=35)
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
        process=subprocess.run([BINARY],input=json.dumps({"path":str(link),"kind":"scouting"}),text=True,capture_output=True,timeout=35)
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
                process=subprocess.run([BINARY],input=request,text=True,capture_output=True,timeout=35)
                result=json.loads(process.stdout);self.assertFalse(result["valid"])
                self.assertNotIn("/unused",process.stdout)

    def test_unconfigured_or_mismatched_renderer_fails_closed(self):
        source=self.root/"synthetic.pdf";source.write_bytes(pdf())
        for env in [dict(os.environ,TEAMSTATS_PDF_RENDERER=""),dict(os.environ,TEAMSTATS_PDF_RENDERER_SHA256="0"*64)]:
            with self.subTest(configured=bool(env.get("TEAMSTATS_PDF_RENDERER"))):
                process=subprocess.run([BINARY],input=json.dumps({"path":str(source),"kind":"scouting"}),text=True,capture_output=True,env=env,timeout=35)
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
