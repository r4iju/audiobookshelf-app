"""Synthetic Audiobookshelf 2.30 item server actions on top of tvos/scripts/related_fixture.py.

Shapes and checks follow the 2.30 server source:
- POST /api/authorize: Auth.getUserLoginResponsePayload, with ereaderDevices filtered by EmailSettings.checkUserCanAccessDevice.
- GET /api/items/:id?expanded=1&include=rssfeed: LibraryItemController.findOne adds rssFeed (Feed.toOldJSONMinified or null).
- POST /api/feeds/item/:id/open and POST /api/feeds/:id/close: RSSFeedController with its admin-only middleware (403),
  body validation, audio and slug checks, and RssFeedManager.getFeedOptionsFromReqOptions.
- POST /api/emails/send-ebook-to-device: EmailController.sendEBookToDevice checks, in the same order.
Feeds live in memory and no email is sent: a successful send is only recorded for the journeys to observe.
"""
import argparse
import copy
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tvos' / 'scripts'))
from related_fixture import make_related_server  # noqa: E402

QA_USER = '00000000-0000-4000-8000-000000000001'
DEVICES = [
    {'name': 'Reading Tablet', 'email': 'tablet@example.invalid', 'availabilityOption': 'userOrUp', 'users': []},
    {'name': 'Admin Reader', 'email': 'admin-reader@example.invalid', 'availabilityOption': 'adminOrUp', 'users': []},
    {'name': 'Shared Kindle', 'email': 'kindle@example.invalid', 'availabilityOption': 'specificUsers', 'users': [QA_USER]},
    {'name': 'Other Kindle', 'email': 'other-kindle@example.invalid', 'availabilityOption': 'specificUsers', 'users': ['someone-else']},
]
EBOOK = {'ino': 'pdf', 'ebookFormat': 'pdf', 'metadata': {'filename': 'stories.pdf', 'ext': '.pdf', 'size': 1024}}


def can_access(device, user):
    availability = device.get('availabilityOption') or 'adminOrUp'
    admin = user['type'] in ('root', 'admin')
    if availability == 'adminOrUp':
        return admin
    if availability == 'userOrUp':
        return admin or user['type'] == 'user'
    if availability == 'guestOrUp':
        return True
    if availability == 'specificUsers':
        return user['id'] in (device.get('users') or [])
    return False


def make_item_actions_server(port, prefix='/abs', bind='127.0.0.1'):
    server, prefix = make_related_server(port, prefix, bind=bind)
    base = server.RequestHandlerClass
    state = {'role': 'user', 'ebook': True, 'fail': None, 'feeds': {}, 'sent': [], 'requests': []}

    def reset(role='user', ebook=True, fail=None, feed=False):
        state.update(role=role, ebook=ebook, fail=fail, feeds={}, sent=[], requests=[])
        if feed:
            state['feeds']['qa-feed'] = {'id': 'qa-feed', 'entityType': 'libraryItem', 'entityId': 'book-0', 'feedUrl': '/feed/qa-feed',
                                         'meta': {'title': 'Stories for Tomorrow 01', 'description': None, 'preventIndexing': True,
                                                  'ownerName': 'QA Owner', 'ownerEmail': None}}

    class ItemActionsHandler(base):
        def own_loopback(self, path):
            tls = getattr(self.server, 'related_tls', False)
            request = urllib.request.Request(f"{'https' if tls else 'http'}://127.0.0.1:{self.server.server_port}{prefix}{path}",
                                             headers={'Authorization': self.headers.get('Authorization', ''), 'X-Actions-Loopback': '1'})
            try:
                import ssl
                with urllib.request.urlopen(request, timeout=5, context=ssl._create_unverified_context() if tls else None) as response:
                    return 200, json.loads(response.read())
            except urllib.error.HTTPError as error:
                return error.code, None

        def user_now(self):
            return {**copy.deepcopy(self.account), 'type': state['role']}

        def item(self, item_id):
            status, item = self.own_loopback(f'/api/items/{item_id}?expanded=1')
            if status != 200:
                return status, None
            if state['ebook'] and item_id == 'book-0':
                item['media']['ebookFile'] = dict(EBOOK)
            return 200, item

        def body(self):
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length) if length else b''
            try:
                return json.loads(raw) if raw else {}
            except ValueError:
                return {}

        def plain(self, status, text):
            self.respond(status, text.encode(), 'text/plain; charset=utf-8')

        def actions_get(self, path, query):
            if path == '/__actions__/observations':
                self.respond(200, {'requests': state['requests'], 'feeds': list(state['feeds'].values()), 'sent': state['sent']})
                return True
            if not (path.startswith('/api/items/') and path.count('/') == 3) or self.headers.get('X-Actions-Loopback') or self.headers.get('X-Related-Loopback'):
                return False
            if not self.authorized():
                self.respond(401, {})
                return True
            item_id = path.rsplit('/', 1)[1]
            include = query.get('include', [''])[0].split(',')
            if 'rssfeed' in include:
                state['requests'].append({'method': 'GET', 'path': path, 'query': {key: values[0] for key, values in query.items()}})
            status, item = self.item(item_id)
            if status != 200:
                self.respond(status, {})
                return True
            if 'rssfeed' in include:
                item['rssFeed'] = next((feed for feed in state['feeds'].values() if feed['entityId'] == item_id), None)
            self.respond(200, item)
            return True

        def actions_post(self, path):
            if path == '/__actions__/configure':
                options = self.body()
                reset(role=options.get('role', 'user'), ebook=options.get('ebook', True), fail=options.get('fail'), feed=options.get('feed', False))
                self.respond(200, {})
                return True
            handled = path == '/api/authorize' or path == '/api/emails/send-ebook-to-device' or path.startswith('/api/feeds/')
            if not handled:
                return False
            body = self.body()
            if not self.authorized():
                self.respond(401, {})
                return True
            state['requests'].append({'method': 'POST', 'path': path, 'body': body})
            user = self.user_now()
            if path == '/api/authorize':
                self.respond(200, {'user': user, 'userDefaultLibraryId': 'books', 'serverSettings': {'version': '2.30.0-fixture', 'language': 'en-us'},
                                   'ereaderDevices': [device for device in DEVICES if can_access(device, user)], 'Source': 'docker'})
                return True
            if path.startswith('/api/feeds/'):
                return self.feeds(path, body, user)
            return self.send_ebook(body, user)

        def failing(self, kind):
            if state['fail'] == kind:
                state['fail'] = None
                return True
            return False

        def feeds(self, path, body, user):
            if user['type'] not in ('root', 'admin'):
                self.respond(403, {})
                return True
            parts = path.strip('/').split('/')
            if len(parts) == 5 and parts[2] == 'item' and parts[4] == 'open':
                status, item = self.item(parts[3])
                if status != 200:
                    self.respond(404, {})
                    return True
                if not isinstance(body.get('serverAddress'), str) or not body.get('serverAddress') or not isinstance(body.get('slug'), str) or not body.get('slug'):
                    self.plain(400, 'Invalid request body')
                    return True
                if not (item['media'].get('tracks') or item['media'].get('episodes')):
                    self.plain(400, 'Item has no audio tracks')
                    return True
                if body['slug'] in state['feeds']:
                    self.plain(400, 'Slug already in use')
                    return True
                if self.failing('open'):
                    self.plain(500, 'Failed to open RSS feed')
                    return True
                details = body.get('metadataDetails') or {}
                feed = {'id': body['slug'], 'entityType': 'libraryItem', 'entityId': parts[3], 'feedUrl': '/feed/' + body['slug'],
                        'meta': {'title': item['media']['metadata'].get('title'), 'description': item['media']['metadata'].get('description'),
                                 'preventIndexing': details.get('preventIndexing') is not False,
                                 'ownerName': details.get('ownerName') if isinstance(details.get('ownerName'), str) and details.get('ownerName') else None,
                                 'ownerEmail': details.get('ownerEmail') if isinstance(details.get('ownerEmail'), str) and details.get('ownerEmail') else None}}
                state['feeds'][feed['id']] = feed
                self.respond(200, {'feed': feed})
                return True
            if len(parts) == 4 and parts[3] == 'close':
                if parts[2] not in state['feeds']:
                    self.respond(404, {})
                    return True
                if self.failing('close'):
                    self.plain(500, 'Internal Server Error')
                    return True
                del state['feeds'][parts[2]]
                self.plain(200, 'OK')
                return True
            self.respond(404, {})
            return True

        def send_ebook(self, body, user):
            device = next((entry for entry in DEVICES if entry['name'] == body.get('deviceName')), None)
            if device is None:
                self.plain(404, 'Ereader device not found')
                return True
            if not can_access(device, user):
                self.respond(403, {})
                return True
            status, item = self.item(str(body.get('libraryItemId')))
            if status != 200:
                self.plain(404, 'Library item not found')
                return True
            if not item['media'].get('ebookFile'):
                self.plain(404, 'Ebook file not found')
                return True
            if self.failing('send'):
                self.plain(400, 'Failed to send ebook to device')
                return True
            state['sent'].append({'libraryItemId': body['libraryItemId'], 'deviceName': device['name']})
            self.plain(200, 'OK')
            return True

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path.startswith(prefix + '/') and self.actions_get(parsed.path[len(prefix):], parse_qs(parsed.query)):
                return
            super().do_GET()

        def do_POST(self):
            parsed = urlparse(self.path)
            if parsed.path.startswith(prefix + '/') and self.actions_post(parsed.path[len(prefix):]):
                return
            super().do_POST()

    server.RequestHandlerClass = ItemActionsHandler
    return server, prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--prefix', default='/abs')
    args = parser.parse_args()
    server, prefix = make_item_actions_server(args.port, args.prefix)
    print(f'http://127.0.0.1:{server.server_port}{prefix}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
