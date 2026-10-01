import json
import os
import selectors
import signal
import subprocess
import sys
import threading
import time
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


class ConnectionBurstJourney(FixtureJourneyBase):
    def test_a_burst_queued_while_the_fixture_is_busy_is_answered_in_full(self):
        # Every app request reaches the fixture on a new connection through the realtime proxy, which reports any refused or
        # reset connection as HTTP 503. Starting playback right after the PDF reader closes sends such a burst while
        # handler threads keep the single accept loop waiting; stopping the process holds that loop deterministically.
        answered, failures = [], []

        def observe():
            try:
                with urlopen(self.address + '/__fixture__/observations', timeout=10) as response:
                    answered.append(response.status)
            except OSError as error:
                failures.append(repr(error))

        os.kill(self.server.pid, signal.SIGSTOP)
        try:
            clients = [threading.Thread(target=observe) for _ in range(40)]
            for client in clients:
                client.start()
            time.sleep(0.5)
        finally:
            os.kill(self.server.pid, signal.SIGCONT)
        for client in clients:
            client.join()
        self.assertEqual(failures, [])
        self.assertEqual(answered, [200] * 40)


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
        saved = self.request('/api/me', token='fresh')['mediaProgress'][0]
        self.assertEqual(saved['currentTime'], 9)
        self.assertEqual(saved['progress'], 0.45)

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


class MidSessionTokenJourney(FixtureJourneyBase):
    def rejected(self, path, data=None, token=None, headers=None):
        with self.assertRaises(HTTPError) as error:
            self.request(path, data, token, headers)
        self.addCleanup(error.exception.close)
        return error.exception.code

    def media_status(self, token):
        try:
            with urlopen(Request(self.address + '/audio/1', headers={'Authorization': 'Bearer ' + token, 'Range': 'bytes=0-1'}), timeout=3) as response:
                return response.status
        except HTTPError as error:
            error.close()
            return error.code

    def test_expired_access_is_rejected_until_the_session_refreshes_to_a_new_token(self):
        refresh = self.request('/login', {'username': 'qa', 'password': 'qa'})['user']['refreshToken']
        first = self.request('/auth/refresh', {}, headers={'x-refresh-token': refresh})['user']['accessToken']
        self.assertEqual(self.media_status(first), 206)
        self.request('/__fixture__/expire-access', {})
        self.assertEqual(self.media_status(first), 401)
        self.assertEqual(self.rejected('/api/me', token=first), 401)
        renewed = self.request('/auth/refresh', {}, headers={'x-refresh-token': refresh})['user']
        self.assertNotEqual(renewed['accessToken'], first)
        self.assertEqual(renewed['username'], 'qa')
        self.assertEqual(self.media_status(renewed['accessToken']), 206)
        self.assertEqual(self.request('/api/me', token=renewed['accessToken'])['username'], 'qa')

    def test_revoked_account_cannot_refresh_or_stream_until_it_signs_in_again(self):
        refresh = self.request('/login', {'username': 'qa', 'password': 'qa'})['user']['refreshToken']
        access = self.request('/auth/refresh', {}, headers={'x-refresh-token': refresh})['user']['accessToken']
        other_refresh = self.request('/login', {'username': 'qa-other', 'password': 'qa'})['user']['refreshToken']
        other = self.request('/auth/refresh', {}, headers={'x-refresh-token': other_refresh})['user']['accessToken']
        self.request('/__fixture__/revoke', {'username': 'qa'})
        self.assertEqual(self.media_status(access), 401)
        self.assertEqual(self.rejected('/auth/refresh', {}, headers={'x-refresh-token': refresh}), 401)
        self.assertEqual(self.media_status(other), 206, 'Revoking one account must not sign out another')
        again = self.request('/login', {'username': 'qa', 'password': 'qa'})['user']['refreshToken']
        renewed = self.request('/auth/refresh', {}, headers={'x-refresh-token': again})['user']['accessToken']
        self.assertEqual(self.media_status(renewed), 206)
        self.assertEqual(self.request('/__fixture__/observations')['revocations'], ['00000000-0000-4000-8000-000000000001'])

    def test_configuring_a_mode_restores_the_original_tokens(self):
        self.request('/__fixture__/expire-access', {})
        self.request('/__fixture__/revoke', {'username': 'qa'})
        self.request('/__fixture__/configure', {'mode': 'baseline'})
        self.assertEqual(self.media_status('fresh'), 206)
        self.assertEqual(self.request('/auth/refresh', {}, headers={'x-refresh-token': 'refresh'})['user']['accessToken'], 'fresh')


if __name__ == '__main__':
    unittest.main()
