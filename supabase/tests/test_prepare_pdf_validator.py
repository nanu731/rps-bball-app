"""Preparation safety only; actual MuPDF/Edge integration is opt-in and separate."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('prepare',Path(__file__).parents[1]/'prepare_pdf_validator.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class PreparationTests(unittest.TestCase):
    def test_unverified_artifact_creates_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            destination=Path(directory)/'new-service'
            with self.assertRaisesRegex(ValueError,'checksum'):module.prepare(destination,b'TEST ONLY invalid artifact')
            self.assertFalse(destination.exists())
    def test_existing_work_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            destination=Path(directory);file=destination/'keep';file.write_text('TEST ONLY retained work')
            with self.assertRaisesRegex(ValueError,'preserved'):module.prepare(destination,b'')
            self.assertEqual(file.read_text(),'TEST ONLY retained work')
