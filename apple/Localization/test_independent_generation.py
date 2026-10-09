import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


class IndependentGenerationTests(unittest.TestCase):
    def test_tables_generate_without_reading_inherited_translations(self):
        spec = importlib.util.spec_from_file_location("native_generation", Path(__file__).with_name("generate.py"))
        generation = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generation)
        original = Path.read_text

        def read(path, *args, **kwargs):
            if path.parent == generation.REPOSITORY / "strings":
                raise AssertionError("Apple localization must not read inherited GPL translations")
            return original(path, *args, **kwargs)

        with patch.object(Path, "read_text", read):
            outputs = generation.outputs()
        self.assertIn(generation.RESOURCES / "en.lproj" / generation.TABLE, outputs)
        self.assertEqual(len(outputs), len(generation.languages()) + 1)


if __name__ == "__main__":
    unittest.main()
