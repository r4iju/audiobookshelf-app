"""Validate the generated resources in a disposable source tree, without owner data."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ANDROID = Path(__file__).resolve().parents[2]

class LocalizationInputs(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        root = Path(self.scratch.name)
        self.android = root / 'android-native'
        shutil.copytree(ANDROID / 'scripts', self.android / 'scripts')
        shutil.copytree(ANDROID / 'app/src/main/strings', self.android / 'app/src/main/strings')
        shutil.copytree(ANDROID / 'app/src/main/res', self.android / 'app/src/main/res')
        (root / 'strings').mkdir()
        (root / 'strings/de.json').write_text(json.dumps({'ButtonLibrary': 'INHERITED_SENTINEL'}))

    def generate(self, *args):
        script = self.android / 'scripts/generate-strings.py'
        return subprocess.run(['python3', str(script), *args], capture_output=True, text=True)

    def test_upstream_translations_never_enter_generated_runtime(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = self.android / 'app/src/main/res'
        self.assertFalse(any('INHERITED_SENTINEL' in path.read_text() for path in resources.glob('values*/strings.xml')))
        self.assertTrue((resources / 'values-fr/strings.xml').exists(), 'Locale inventory must come from maintained inputs')

    def test_check_rejects_changed_generated_resource(self):
        self.assertEqual(self.generate().returncode, 0)
        resource = self.android / 'app/src/main/res/values/strings.xml'
        resource.write_text(resource.read_text().replace('Library', 'Stale text'))
        self.assertNotEqual(self.generate('--check').returncode, 0, 'Stale packaged strings must fail validation')

if __name__ == '__main__':
    unittest.main()
