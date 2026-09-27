import concurrent.futures
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / 'persist.py'
spec = importlib.util.spec_from_file_location('storage', HELPER)
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)
EMPTY = {'version': 1, 'protocols': []}
LIBRARY = {'version': 1, 'protocols': [dict(id='calm', name='Calm', inhale=5.5, holdIn=0, exhale=5.5, holdOut=0)]}


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'data.json'

    def write(self, operation, payload):
        return subprocess.run([sys.executable, str(HELPER), str(self.path), operation, json.dumps(payload)], capture_output=True, text=True)

    def test_library_roundtrip_and_conflict(self):
        self.assertEqual(self.write('protocols', dict(expected=EMPTY, library=LIBRARY)).returncode, 0)
        self.assertEqual(json.loads(self.path.read_text()), LIBRARY)
        result = self.write('protocols', dict(expected=EMPTY, library=EMPTY))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('changed on disk', result.stderr)
        self.assertEqual(json.loads(self.path.read_text()), LIBRARY)

    def test_second_inhale_roundtrip(self):
        library = {'version': 1, 'protocols': [dict(id='sigh', name='My sigh', inhale=3, topUp=1, holdIn=0, exhale=6, holdOut=0)]}
        self.assertEqual(self.write('protocols', dict(expected=EMPTY, library=library)).returncode, 0)
        self.assertEqual(json.loads(self.path.read_text()), library)
        invalid = {'version': 1, 'protocols': [dict(library['protocols'][0], topUp=-1)]}
        self.assertNotEqual(self.write('protocols', dict(expected=library, library=invalid)).returncode, 0)
        self.assertEqual(json.loads(self.path.read_text()), library)

    def test_concurrent_history_updates(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: self.write('add-minutes', dict(day='2026-09-27', minutes=1)), range(32)))
        self.assertTrue(all(result.returncode == 0 for result in results))
        self.assertEqual(json.loads(self.path.read_text()), {'days': {'2026-09-27': 32}})

    def test_corrupt_existing_files_are_preserved(self):
        for raw in ['{', '{"days":null}', '{"days":{"2026-09-27":"bad"}}']:
            self.path.write_text(raw)
            self.assertNotEqual(self.write('add-minutes', dict(day='2026-09-27', minutes=1)).returncode, 0)
            self.assertEqual(self.path.read_text(), raw)
        self.path.write_text('{')
        self.assertNotEqual(self.write('protocols', dict(expected=EMPTY, library=LIBRARY)).returncode, 0)
        self.assertEqual(self.path.read_text(), '{')

    def test_interruption_before_replace_preserves_destination(self):
        self.path.write_text(json.dumps(EMPTY))
        with patch.object(storage.os, 'replace', side_effect=OSError('simulated write failure')):
            with self.assertRaises(OSError):
                storage.atomic_write(self.path, LIBRARY)
        self.assertEqual(json.loads(self.path.read_text()), EMPTY)
        self.assertEqual(list(self.path.parent.glob('*.tmp')), [])

    def test_unwritable_destination_reports_failure(self):
        self.path.mkdir()
        self.assertNotEqual(self.write('protocols', dict(expected=EMPTY, library=LIBRARY)).returncode, 0)
        self.assertTrue(self.path.is_dir())


if __name__ == '__main__':
    unittest.main()
