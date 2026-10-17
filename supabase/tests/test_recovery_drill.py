"""Synthetic file-byte recovery, separate from database and provider recovery."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("recovery_drill", Path(__file__).parents[1] / "recovery_drill.py")
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)


class ObjectRecoveryTests(unittest.TestCase):
    def test_restore_preserves_object_key_and_bytes_without_touching_other_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            key = "teamstats-private/synthetic-team/synthetic-version"
            path = source / key
            path.parent.mkdir(parents=True)
            data = b"TEST ONLY independent recovery bytes\n"
            path.write_bytes(data)
            sentinel = root / "unrelated"
            sentinel.write_bytes(b"TEST ONLY preserve me")
            entry = {"key": key, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            recovery.restore_objects(source, root / "restored", [entry])
            self.assertEqual((root / "restored" / key).read_bytes(), data)
            self.assertEqual(sentinel.read_bytes(), b"TEST ONLY preserve me")
            self.assertEqual(path.read_bytes(), data)

    def test_bad_inventory_or_missing_bytes_never_creates_a_recovered_destination(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            key = "teamstats-private/synthetic/item"
            (source / key).parent.mkdir(parents=True)
            (source / key).write_bytes(b"TEST")
            entry = {"key": key, "bytes": 4, "sha256": hashlib.sha256(b"TEST").hexdigest()}
            cases = [[dict(entry, key="../outside")], [dict(entry, key="/absolute")],
                     [dict(entry, key="teamstats-private/missing")], [dict(entry, bytes=5)],
                     [dict(entry, sha256="0" * 64)], [entry, entry]]
            link = source / "teamstats-private/link"
            link.symlink_to(source / "teamstats-private/synthetic", target_is_directory=True)
            cases.append([dict(entry, key="teamstats-private/link/item")])
            for number, inventory in enumerate(cases):
                destination = root / f"restored-{number}"
                with self.subTest(inventory=number), self.assertRaises(ValueError):
                    recovery.restore_objects(source, destination, inventory)
                self.assertFalse(destination.exists())
            self.assertEqual((source / key).read_bytes(), b"TEST")

    def test_interrupted_copy_has_no_complete_receipt_and_cannot_overwrite_on_retry(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            key = "teamstats-private/synthetic/item"
            (source / key).parent.mkdir(parents=True)
            (source / key).write_bytes(b"TEST")
            entry = {"key": key, "bytes": 4, "sha256": hashlib.sha256(b"TEST").hexdigest()}
            destination = root / "interrupted"
            with patch.object(recovery.shutil, "copyfile", side_effect=OSError("TEST ONLY disk failure")):
                with self.assertRaises(OSError):
                    recovery.restore_objects(source, destination, [entry])
            self.assertTrue((destination / "INCOMPLETE").exists())
            self.assertFalse((destination / "recovery-complete.json").exists())
            with self.assertRaises(FileExistsError):
                recovery.restore_objects(source, destination, [entry])
            self.assertEqual((source / key).read_bytes(), b"TEST")

    def test_occupied_destination_retains_existing_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            source.mkdir()
            destination = root / "occupied"
            destination.mkdir()
            (destination / "sentinel").write_bytes(b"TEST ONLY original")
            with self.assertRaises(FileExistsError):
                recovery.restore_objects(source, destination, [])
            self.assertEqual((destination / "sentinel").read_bytes(), b"TEST ONLY original")

    def test_database_guard_rejects_remote_hosts_and_arbitrary_container_arguments(self):
        with patch.dict("os.environ", {"PGHOST": "hosted.example.invalid"}):
            with self.assertRaises(ValueError):
                recovery.IsolatedPostgres(Path("unused"), Path("unused"), None)
        with patch.dict("os.environ", {"PGHOST": "127.0.0.1"}):
            with self.assertRaises(ValueError):
                recovery.IsolatedPostgres(Path("unused"), None, "--privileged")


if __name__ == "__main__":
    unittest.main()
