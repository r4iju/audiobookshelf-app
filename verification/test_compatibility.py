"""Drive the shipped TV API client through an actual loopback server."""
import json
import subprocess
import unittest

from verification.test_fixture import FixtureJourneyBase


class ProductionClientCompatibility(FixtureJourneyBase):
    fixture_arguments = []
    def test_shipped_client_refreshes_and_restores_before_reporting_multi_file_progress(self):
        journey = subprocess.run(
            ['swift', 'run', '--package-path', 'verification/ClientJourney', 'client-journey', self.address],
            capture_output=True, text=True, timeout=90)
        self.assertEqual(journey.returncode, 0, journey.stderr)
        result = json.loads(journey.stdout)
        self.assertEqual(result['client'], 'TVCore')
        self.assertEqual(result['workflows'], ['authentication', 'credential-restoration', 'library-pagination', 'book-playback', 'podcast-playback', 'authenticated-media', 'progress-close'])
        observed = self.request('/__fixture__/observations')
        self.assertEqual(sum(r['path'] == '/auth/refresh' for r in observed['requests']), 1)
        self.assertEqual(observed['reports'][-1]['currentTime'], 9)
        self.assertEqual(observed['reports'][-1]['timeListened'], 3)


class CandidateSchemaCompatibility(FixtureJourneyBase):
    fixture_arguments = ['--scenario', 'library-schema-change']

    def test_candidate_schema_break_blocks_upgrade_at_affected_workflow(self):
        result = subprocess.run(['swift', 'run', '--package-path', 'verification/ClientJourney', 'client-journey', self.address], capture_output=True, text=True, timeout=90)
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stderr.strip().splitlines()[-1])
        self.assertEqual(report['workflow'], 'library-pagination')
        self.assertEqual(report['result'], 'failed')


if __name__ == '__main__':
    unittest.main()
