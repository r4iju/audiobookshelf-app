"""The progress reset fixture follows the 2.30 routes the journeys rely on. Run: python3 -m unittest apple/scripts/test_progress_reset_fixture.py"""
import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from progress_reset_fixture import make_progress_reset_server, row_id  # noqa: E402


class ProgressResetFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server, prefix = make_progress_reset_server(0)
        cls.base = f'http://127.0.0.1:{cls.server.server_port}{prefix}'
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def call(self, method, path, body=None, auth=True):
        request = urllib.request.Request(self.base + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                         headers={**({'Authorization': 'Bearer fresh'} if auth else {}), 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, json.loads(response.read() or b'{}')
        except urllib.error.HTTPError as error:
            with error:
                return error.code, None

    def configure(self, **options):
        self.assertEqual(self.call('POST', '/__reset__/configure', options, auth=False)[0], 200)

    def observations(self):
        return self.call('GET', '/__reset__/observations', auth=False)[1]

    def test_the_row_is_found_by_item_and_episode_and_deleted_by_its_id(self):
        self.configure()
        status, row = self.call('GET', '/api/me/progress/podcast/episode')
        self.assertEqual(status, 200)
        self.assertEqual(row['id'], row_id('podcast', 'episode'))
        self.assertEqual((row['libraryItemId'], row['episodeId'], row['currentTime']), ('podcast', 'episode', 6))
        self.assertEqual(self.call('DELETE', '/api/me/progress/podcast/episode')[0], 404, 'The delete route takes the row id, not the item')
        self.assertEqual(self.call('DELETE', '/api/me/progress/' + row['id'])[0], 200)
        self.assertEqual(self.call('GET', '/api/me/progress/podcast/episode')[0], 404)
        remaining = {(entry['libraryItemId'], entry['episodeId']) for entry in self.observations()['progress']}
        self.assertEqual(remaining, {('book-0', None), ('book-1', None), ('podcast', 'episode-morning')})
        me = self.call('GET', '/api/me')[1]
        self.assertNotIn(('podcast', 'episode'), {(entry['libraryItemId'], entry['episodeId']) for entry in me['mediaProgress']})
        self.assertEqual(self.observations()['deleted'], [{'id': row['id'], 'libraryItemId': 'podcast', 'episodeId': 'episode'}])

    def test_an_unknown_row_id_is_still_answered_with_200(self):
        self.configure()
        self.assertEqual(self.call('DELETE', '/api/me/progress/unknown-row')[0], 200)
        self.assertEqual(self.observations()['deleted'], [])
        self.assertEqual(len(self.observations()['progress']), 4)

    def test_a_configured_failure_fails_one_delete_and_keeps_the_row(self):
        self.configure(fail='delete')
        identity = row_id('book-0', None)
        self.assertEqual(self.call('DELETE', '/api/me/progress/' + identity)[0], 500)
        self.assertEqual(self.call('GET', '/api/me/progress/book-0')[0], 200)
        self.assertEqual(self.call('DELETE', '/api/me/progress/' + identity)[0], 200)
        self.assertEqual(self.call('GET', '/api/me/progress/book-0')[0], 404)

    def test_playback_starts_at_zero_only_without_a_row(self):
        self.configure()
        self.assertEqual(self.call('POST', '/api/items/book-1/play', {})[1]['currentTime'], 6)
        self.call('DELETE', '/api/me/progress/' + row_id('book-0', None))
        self.assertEqual(self.call('POST', '/api/items/book-0/play', {})[1]['currentTime'], 0)
        self.assertEqual([(session['libraryItemId'], session['currentTime']) for session in self.observations()['sessions']], [('book-1', 6), ('book-0', 0)])

    def test_requests_need_the_signed_in_user(self):
        self.configure()
        self.assertEqual(self.call('GET', '/api/me/progress/book-0', auth=False)[0], 401)
        self.assertEqual(self.call('DELETE', '/api/me/progress/' + row_id('book-0', None), auth=False)[0], 401)
        self.assertEqual(len(self.observations()['progress']), 4)


if __name__ == '__main__':
    unittest.main()
