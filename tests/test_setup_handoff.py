"""Exercise the handoff consumed by subsequent build/fix sessions."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / 'veris/skills/veris-reference/scripts'
spec = importlib.util.spec_from_file_location('check_setup', SCRIPTS / 'check-setup.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class SetupHandoffTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        (self.project / 'src').mkdir()
        (self.project / '.veris/bin').mkdir(parents=True)
        for name in ('record.sh', 'ledger.sh'):
            shutil.copyfile(SCRIPTS / name, self.project / '.veris/bin' / name)
        for name in ('.veris/NOTES.md', '.veris/twin.yaml', '.gitignore'):
            (self.project / name).write_text('fixture\n')
        self.metadata = dict(source_roots=['src'], build_command='false',
                             build_outputs=[], artifact_policy='local')
        self.write_metadata(self.metadata)

    def write_metadata(self, value):
        (self.project / '.veris/setup.json').write_text(json.dumps(value))

    def test_no_git_and_no_build_outputs_are_supported_without_running_build(self):
        result = subprocess.run([sys.executable, str(SCRIPTS / 'check-setup.py'),
                                 '--project', str(self.project)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.project / '.git').exists())

    def test_green_run_report_does_not_replace_handoff(self):
        (self.project / 'RUN.md').write_text('Application passed\n')
        for name in ('.veris/NOTES.md', '.veris/setup.json', '.veris/bin/record.sh',
                     '.veris/bin/ledger.sh', '.gitignore'):
            (self.project / name).unlink()
        self.assertEqual(len(checker.check(self.project, SCRIPTS)), 5)

    def test_metadata_requires_object_and_build_facts(self):
        for value in (None, [], {'source_roots': 'src'},
                      {**self.metadata, 'source_roots': ['absent']},
                      {**self.metadata, 'build_command': ''},
                      {**self.metadata, 'build_outputs': None},
                      {**self.metadata, 'artifact_policy': 'unknown'}):
            with self.subTest(value=value):
                self.write_metadata(value)
                self.assertTrue(checker.check(self.project, SCRIPTS))

    def test_malformed_files_return_findings_without_dumping_contents(self):
        secret_marker = 'private-fixture-value'
        (self.project / '.veris/setup.json').write_text(secret_marker)
        (self.project / '.veris/NOTES.md').write_bytes(b'\xff')
        errors = checker.check(self.project, SCRIPTS)
        self.assertEqual(len(errors), 2)
        self.assertNotIn(secret_marker, '\n'.join(errors))

    def test_glob_source_roots_supported_by_record_helper(self):
        (self.project / 'packages/example/src').mkdir(parents=True)
        self.write_metadata({**self.metadata, 'source_roots': ['packages/*/src']})
        self.assertEqual(checker.check(self.project, SCRIPTS), [])
        self.write_metadata({**self.metadata, 'source_roots': ['missing/*/src']})
        self.assertTrue(checker.check(self.project, SCRIPTS))

    def test_stale_helpers_are_detected(self):
        (self.project / '.veris/bin/record.sh').write_text('old copy\n')
        self.assertEqual(len(checker.check(self.project, SCRIPTS)), 1)


if __name__ == '__main__':
    unittest.main()
