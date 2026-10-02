"""The item actions fixture follows the 2.30 server checks the journeys rely on. Run: python3 -m unittest apple/scripts/test_item_actions_fixture.py"""
import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from item_actions_fixture import make_item_actions_server  # noqa: E402


class ItemActionsFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server, prefix = make_item_actions_server(0)
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
                raw = response.read()
                return response.status, json.loads(raw) if response.headers.get_content_type() == 'application/json' else raw.decode()
        except urllib.error.HTTPError as error:
            with error:
                return error.code, error.read().decode()

    def configure(self, **options):
        self.assertEqual(self.call('POST', '/__actions__/configure', options, auth=False)[0], 200)

    def test_authorize_lists_only_devices_the_user_may_use(self):
        self.configure(role='user')
        status, payload = self.call('POST', '/api/authorize')
        self.assertEqual(status, 200)
        self.assertEqual(payload['user']['type'], 'user')
        self.assertEqual([device['name'] for device in payload['ereaderDevices']], ['Reading Tablet', 'Shared Kindle'])
        self.configure(role='admin')
        self.assertEqual([device['name'] for device in self.call('POST', '/api/authorize')[1]['ereaderDevices']], ['Reading Tablet', 'Admin Reader', 'Shared Kindle'])
        self.assertEqual(self.call('POST', '/api/authorize', auth=False)[0], 401)

    def test_item_includes_its_open_feed_and_ebook(self):
        self.configure(role='user', feed=True)
        status, item = self.call('GET', '/api/items/book-0?expanded=1&include=rssfeed')
        self.assertEqual(status, 200)
        self.assertEqual(item['rssFeed']['feedUrl'], '/feed/qa-feed')
        self.assertEqual(item['media']['ebookFile']['ebookFormat'], 'pdf')
        self.assertEqual(item['libraryId'], 'books')
        self.assertTrue(item['media']['tracks'])
        self.assertIsNone(self.call('GET', '/api/items/book-1?expanded=1&include=rssfeed')[1]['rssFeed'])
        self.assertNotIn('rssFeed', self.call('GET', '/api/items/book-0?expanded=1')[1], 'Only include=rssfeed adds the feed')

    def test_feed_routes_are_admin_only_and_check_like_the_server(self):
        self.configure(role='user', feed=True)
        self.assertEqual(self.call('POST', '/api/feeds/qa-feed/close')[0], 403)
        self.assertEqual(self.call('POST', '/api/feeds/item/book-1/open', {'serverAddress': 'http://x/abs', 'slug': 'x'})[0], 403)
        self.configure(role='admin', feed=True)
        self.assertEqual(self.call('POST', '/api/feeds/item/book-1/open', {'slug': 'x'}), (400, 'Invalid request body'))
        self.assertEqual(self.call('POST', '/api/feeds/item/book-1/open', {'serverAddress': 'http://x/abs', 'slug': 'qa-feed'}), (400, 'Slug already in use'))
        self.assertEqual(self.call('POST', '/api/feeds/item/missing/open', {'serverAddress': 'http://x/abs', 'slug': 'x'})[0], 404)
        status, opened = self.call('POST', '/api/feeds/item/book-1/open', {'serverAddress': 'http://x/abs', 'slug': 'evening', 'metadataDetails': {'preventIndexing': False, 'ownerName': '', 'ownerEmail': 'o@example.invalid'}})
        self.assertEqual(status, 200)
        self.assertEqual(opened['feed']['meta'], {'title': 'Stories for Tomorrow 02', 'description': '<p>Synthetic two-file audio. No live library data.</p>', 'preventIndexing': False, 'ownerName': None, 'ownerEmail': 'o@example.invalid'})
        self.assertEqual(self.call('POST', '/api/feeds/evening/close'), (200, 'OK'))
        self.assertEqual(self.call('POST', '/api/feeds/evening/close')[0], 404)

    def test_send_checks_device_access_and_ebook_and_sends_nothing(self):
        self.configure(role='user')
        self.assertEqual(self.call('POST', '/api/emails/send-ebook-to-device', {'libraryItemId': 'book-0', 'deviceName': 'Nope'}), (404, 'Ereader device not found'))
        self.assertEqual(self.call('POST', '/api/emails/send-ebook-to-device', {'libraryItemId': 'book-0', 'deviceName': 'Admin Reader'})[0], 403)
        self.assertEqual(self.call('POST', '/api/emails/send-ebook-to-device', {'libraryItemId': 'book-1', 'deviceName': 'Shared Kindle'}), (404, 'Ebook file not found'))
        self.assertEqual(self.call('POST', '/api/emails/send-ebook-to-device', {'libraryItemId': 'book-0', 'deviceName': 'Shared Kindle'}), (200, 'OK'))
        self.configure(role='user', fail='send')
        self.assertEqual(self.call('POST', '/api/emails/send-ebook-to-device', {'libraryItemId': 'book-0', 'deviceName': 'Shared Kindle'}), (400, 'Failed to send ebook to device'))
        self.assertEqual(self.call('POST', '/api/emails/send-ebook-to-device', {'libraryItemId': 'book-0', 'deviceName': 'Shared Kindle'})[0], 200)
        sent = self.call('GET', '/__actions__/observations', auth=False)[1]['sent']
        self.assertEqual(sent, [{'libraryItemId': 'book-0', 'deviceName': 'Shared Kindle'}])


if __name__ == '__main__':
    unittest.main()
