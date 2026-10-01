import json
from pathlib import Path
import subprocess
import sys
import unittest
from urllib.request import Request, urlopen


class LocalReferenceJourney(unittest.TestCase):
    def test_listener_refreshes_browses_and_reports_progress(self):
        server = subprocess.Popen([sys.executable, '-m', 'verification.fixture', '--port', '0'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            address = server.stdout.readline().strip()
            self.assertTrue(address.startswith('http://127.0.0.1:'), server.stderr.read() if not address else address)
            def request(path, data=None, token=None, headers=None):
                value = Request(address + path, json.dumps(data).encode() if data is not None else None,
                                {'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + token} if token else {}), **(headers or {})})
                with urlopen(value, timeout=3) as response:
                    return json.load(response)
            login = request('/login', {'username': 'qa', 'password': 'qa'})
            self.assertEqual(login['serverSettings']['version'], '2.30.0-fixture')
            fresh = request('/auth/refresh', {}, headers={'x-refresh-token': login['user']['refreshToken']})['user']['accessToken']
            self.assertEqual(request('/api/libraries', token=fresh)['libraries'][0]['name'], 'Audiobooks')
            self.assertEqual(len(request('/api/libraries/books/items?page=1&limit=60', token=fresh)['results']), 1)
            session = request('/api/items/book-0/play', {}, fresh)
            request('/api/session/' + session['id'] + '/close', {'currentTime': 9, 'timeListened': 3, 'duration': 20}, fresh)
            observed = request('/__fixture__/observations')
            self.assertEqual(observed['reports'][0]['timeListened'], 3)
            self.assertEqual(observed['reports'][0]['currentTime'], 9)
        finally:
            server.terminate()
            server.communicate(timeout=5)


    def test_media_supports_suffix_ranges_for_player_probes(self):
        server = subprocess.Popen([sys.executable, '-m', 'verification.fixture', '--port', '0'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            address = server.stdout.readline().strip()
            request = Request(address + '/audio/0', headers={'Authorization': 'Bearer fresh', 'Range': 'bytes=-8'})
            with urlopen(request, timeout=3) as response:
                self.assertEqual(response.status, 206)
                self.assertEqual(response.headers['Content-Range'], 'bytes 256036-256043/256044')
                self.assertEqual(len(response.read()), 8)
        finally:
            server.terminate()
            server.communicate(timeout=5)


if __name__ == '__main__':
    unittest.main()
