import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]

class NoticeVariant(unittest.TestCase):
    def test_cast_switch_rejects_a_cast_free_inventory(self):
        spec = importlib.util.spec_from_file_location('notices', ROOT / 'releases/leafwake/generate-notices.py')
        notices = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(notices)
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            shutil.copytree(ROOT / 'releases/leafwake/dependency-licenses', root / 'releases/leafwake/dependency-licenses')
            (root / 'android-native').mkdir()
            shutil.copy(ROOT / 'android-native/LICENSE', root / 'android-native/LICENSE')
            shutil.copy(ROOT / 'releases/leafwake/ANDROID-CAST-PRIVACY.md', root / 'releases/leafwake/ANDROID-CAST-PRIVACY.md')
            inventory = root / 'runtime.tsv'
            core = ROOT / 'android-native/core/build/libs/core.jar'
            inventory.write_text(f'AudiobookshelfNativeAndroid:core:unspecified\t{core}\n')
            with patch.object(notices, 'ROOT', root), patch.object(sys, 'argv', ['notices', str(inventory), '--cast']), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    notices.main()

if __name__ == '__main__':
    unittest.main()
