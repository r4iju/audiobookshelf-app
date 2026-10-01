import json
import subprocess
import unittest


class LocalUpgradeGate(unittest.TestCase):
    def test_aligned_authentication_candidate_passes_and_schema_break_blocks_upgrade(self):
        aligned = subprocess.run(['python3', '-m', 'verification.compatibility', '--candidate', 'modern-auth'], capture_output=True, text=True, timeout=90)
        self.assertEqual(aligned.returncode, 0, aligned.stderr)
        accepted = json.loads(aligned.stdout)
        self.assertTrue(accepted['adoptCandidate'])
        self.assertTrue(all(row['result'] == 'passed' for row in accepted['baseline'] + accepted['candidate']))
        breaking = subprocess.run(['python3', '-m', 'verification.compatibility', '--candidate', 'library-schema-change'], capture_output=True, text=True, timeout=90)
        self.assertEqual(breaking.returncode, 1)
        blocked = json.loads(breaking.stdout)
        self.assertFalse(blocked['adoptCandidate'])
        self.assertEqual(blocked['affectedWorkflows'], ['library-pagination'])
        self.assertEqual(blocked['alignmentRequired'], ['TVCore'])


if __name__ == '__main__':
    unittest.main()
