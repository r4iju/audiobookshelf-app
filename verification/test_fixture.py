import json
import selectors
import subprocess
import sys
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen


class FixtureJourneyBase(unittest.TestCase):
    def setUp(self):
        self.server = subprocess.Popen([sys.executable, '-m', 'verification.fixture', '--port', '0', *getattr(self, 'fixture_arguments', [])], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(self.stop_server)
        with selectors.DefaultSelector() as ready:
            ready.register(self.server.stdout, selectors.EVENT_READ)
            self.assertTrue(ready.select(timeout=5), 'Fixture did not start within five seconds')
        self.address = self.server.stdout.readline().strip()
        self.assertTrue(self.address.startswith('http://127.0.0.1:'), 'Fixture did not publish its local address')

    def stop_server(self):
        self.server.terminate()
        self.server.communicate(timeout=5)

    def request(self, path, data=None, token=None, headers=None):
        value = Request(self.address + path, json.dumps(data).encode() if data is not None else None,
                        {'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + token} if token else {}), **(headers or {})})
        with urlopen(value, timeout=3) as response:
            return json.load(response)


class LocalReferenceJourney(FixtureJourneyBase):
    def test_listener_refreshes_browses_and_reports_progress(self):
        login = self.request('/login', {'username': 'qa', 'password': 'qa'})
        self.assertEqual(login['serverSettings']['version'], '2.30.0-fixture')
        fresh = self.request('/auth/refresh', {}, headers={'x-refresh-token': login['user']['refreshToken']})['user']['accessToken']
        self.assertEqual(self.request('/api/libraries', token=fresh)['libraries'][0]['name'], 'Audiobooks')
        self.assertEqual(len(self.request('/api/libraries/books/items?page=1&limit=60', token=fresh)['results']), 1)
        session = self.request('/api/items/book-0/play', {}, fresh)
        self.request('/api/session/' + session['id'] + '/close', {'currentTime': 9, 'timeListened': 3, 'duration': 20}, fresh)
        observed = self.request('/__fixture__/observations')
        self.assertEqual(observed['reports'][0]['timeListened'], 3)
        self.assertEqual(observed['reports'][0]['currentTime'], 9)

    def test_closed_progress_survives_a_new_session_for_the_same_item(self):
        first = self.request('/api/items/book-0/play', {}, 'fresh')
        self.request('/api/session/' + first['id'] + '/close', {'currentTime': 9, 'timeListened': 3, 'duration': 20}, 'fresh')
        resumed = self.request('/api/items/book-0/play', {}, 'fresh')
        self.assertEqual(resumed['currentTime'], 9)
        self.assertEqual(self.request('/api/items/book-1/play', {}, 'fresh')['currentTime'], 6)
        self.assertEqual(self.request('/api/me', token='fresh')['mediaProgress'][0]['currentTime'], 9)

    def test_media_supports_suffix_ranges_for_player_probes(self):
        request = Request(self.address + '/audio/0', headers={'Authorization': 'Bearer fresh', 'Range': 'bytes=-8'})
        with urlopen(request, timeout=3) as response:
            self.assertEqual(response.status, 206)
            self.assertEqual(response.headers['Content-Range'], 'bytes 256036-256043/256044')
            self.assertEqual(len(response.read()), 8)

    def test_requested_book_identity_is_preserved_and_invalid_play_is_rejected(self):
        session = self.request('/api/items/book-60/play', {}, 'fresh')
        self.assertEqual(session['libraryItemId'], 'book-60')
        with self.assertRaises(HTTPError) as error:
            self.request('/api/nonexistent/play', {}, 'fresh')
        self.addCleanup(error.exception.close)
        self.assertEqual(error.exception.code, 404)

    def test_unsatisfiable_range_has_an_explicit_media_recovery_response(self):
        request = Request(self.address + '/audio/0', headers={'Authorization': 'Bearer fresh', 'Range': 'bytes=999999-'})
        with self.assertRaises(HTTPError) as error:
            urlopen(request, timeout=3)
        self.addCleanup(error.exception.close)
        self.assertEqual(error.exception.code, 416)
        self.assertEqual(error.exception.headers['Content-Range'], 'bytes */256044')


if __name__ == '__main__':
    unittest.main()
