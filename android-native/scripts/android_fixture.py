"""Android journey fixture: the shared synthetic server plus server 2.30 routes only Android journeys use.

The shared fixture belongs to the cross-platform verification suite, so Android-only routes are layered
here instead of edited into it.
"""
import argparse
import copy
import io
import json
import re
import ssl
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verification.fixture import make_server  # noqa: E402


def android_server(port, prefix, bind='127.0.0.1'):
    server, prefix = make_server(port, prefix, 'baseline', 'modern', bind)
    base = server.RequestHandlerClass
    # Listening sync can be refused on its own, whatever the shared mode, so reading and listening
    # ordering is observable with a document present. Any reconfiguration accepts listening again.
    refusal = {'listening': False, 'reading': False}
    discard_delay = {'seconds': 0}
    # The shared fixture reconfigures progress entries it assumes exist, and keeps progress and
    # bookmarks one journey class added for the next. Reconfiguring restores the titles that had
    # progress at startup, drops progress added since and clears bookmarks, so classes pass alone and
    # in one run alike. Entries that exist are left for the mode to set, so modes can be layered.
    def probe_for(token):
        probe = base.__new__(base)
        probe.headers = {'Authorization': token} if token else {}
        return probe
    probes = [probe_for(None), probe_for('Bearer fresh-other')]
    accounts = [probe.progress for probe in probes]
    originals = [copy.deepcopy(entries) for entries in accounts]
    # Server 2.30 item actions the shared fixture does not model. Nothing is sent anywhere: feeds and
    # e-reader deliveries are only recorded for journeys to observe.
    actions = {'feeds': {}, 'devices': [], 'sent': [], 'ebook': False}

    def reset_actions(mode):
        actions.update(feeds={}, devices=[], sent=[], ebook=mode.startswith('pdf-') or mode.startswith('epub-'))

    def feed_for(item_id, slug, meta):
        return {'id': 'feed-' + slug, 'slug': slug, 'entityType': 'libraryItem', 'entityId': item_id, 'feedUrl': '/feed/' + slug,
                'meta': {'title': item_id, 'preventIndexing': bool(meta.get('preventIndexing', True)),
                         'ownerName': meta.get('ownerName') or None, 'ownerEmail': meta.get('ownerEmail') or None}}

    class AndroidHandler(base):
        def own_path(self):
            path = urlparse(self.path).path
            return path[len(prefix):] if path.startswith(prefix + '/') else None

        def identify_progress(self):
            # Server 2.30 progress records carry an id that discarding progress addresses.
            for entry in self.progress.values():
                entry.setdefault('id', 'progress-' + entry['libraryItemId'] + ('-' + entry['episodeId'] if entry.get('episodeId') else ''))

        def respond(self, status, value, *args, **kwargs):
            item_id = getattr(self, 'feed_item', None)
            if item_id and status == 200 and isinstance(value, dict):
                value = {**value, 'rssFeed': actions['feeds'].get(item_id)}
            return super().respond(status, value, *args, **kwargs)

        def is_admin(self):
            return self.account.get('type') in ('admin', 'root')

        def body(self):
            return json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')

        def do_GET(self):
            # Handlers are reused across keep-alive requests, so the marker is cleared for each one.
            self.feed_item = None
            if self.own_path() == '/__android__/actions':
                self.route()
                return self.respond(200, {'feeds': list(actions['feeds'].values()), 'sentEbooks': actions['sent']})
            item = re.fullmatch(r'/api/items/([^/]+)', self.own_path() or '')
            if item and 'rssfeed' in parse_qs(urlparse(self.path).query).get('include', [''])[0].split(','):
                self.feed_item = item[1]
            if self.own_path() == '/__android__/progress':
                self.route()
                return self.respond(200, {'progress': list(self.progress.values())})
            single = re.fullmatch(r'/api/me/progress/([^/]+)(?:/([^/]+))?', self.own_path() or '')
            if single:
                self.route()
                if not self.authorized():
                    return self.respond(401, {})
                self.identify_progress()
                entry = self.progress.get((single[1], single[2]))
                return self.respond(200, entry) if entry else self.respond(404, {})
            self.identify_progress()
            super().do_GET()

        def do_PATCH(self):
            book = re.fullmatch(r'/api/me/progress/(book-[0-9]+)', self.own_path() or '')
            if book:
                body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
                data = json.loads(body or b'{}')
                if isinstance(data.get('isFinished'), bool) and 'ebookLocation' not in data:
                    self.route()
                    self.observed_request['isFinished'] = data['isFinished']
                    if not self.authorized():
                        return self.respond(401, {})
                    key = (book[1], None)
                    current = self.progress.get(key, {'libraryItemId': book[1], 'episodeId': None, 'duration': 20})
                    finished = data['isFinished']
                    current.update(isFinished=finished, progress=1 if finished else 0, lastUpdate=int(time.time() * 1000))
                    if not finished:
                        current['currentTime'] = 0
                    self.progress[key] = current
                    self.identify_progress()
                    self.account['mediaProgress'] = list(self.progress.values())
                    return self.respond(200, current)
                if refusal['reading'] and 'ebookLocation' in data:
                    self.route()
                    self.observed_request.update(ebookLocation=data['ebookLocation'], applied=False)
                    return self.respond(503, {})
                self.rfile = io.BytesIO(body)
            super().do_PATCH()

        def do_POST(self):
            path = self.own_path()
            if path == '/__android__/ereader-devices':
                actions['devices'] = [{'name': name} for name in self.body().get('names', [])]
                self.route()
                return self.respond(200, {})
            if path == '/__android__/open-feed':
                data = self.body()
                actions['feeds'][data['itemId']] = feed_for(data['itemId'], data['slug'], {})
                self.route()
                return self.respond(200, {})
            if path == '/api/authorize':
                self.route()
                if not self.authorized():
                    return self.respond(401, {})
                return self.respond(200, {'user': self.account, 'userDefaultLibraryId': 'books', 'ereaderDevices': actions['devices'],
                                          'serverSettings': {'version': '2.30.0-fixture', 'language': 'en-us'}})
            if path == '/api/emails/send-ebook-to-device':
                data = self.body()
                self.route()
                if not self.authorized():
                    return self.respond(401, {})
                if not any(device['name'] == data.get('deviceName') for device in actions['devices']):
                    return self.respond(404, {})
                if data.get('libraryItemId') != 'book-0' or not actions['ebook']:
                    return self.respond(404, {})
                actions['sent'].append({'libraryItemId': data['libraryItemId'], 'deviceName': data['deviceName']})
                return self.respond(200, {})
            opening = re.fullmatch(r'/api/feeds/item/([^/]+)/open', path or '')
            if opening:
                data = self.body()
                self.route()
                if not self.authorized():
                    return self.respond(401, {})
                if not self.is_admin():
                    return self.respond(403, {})
                slug = data.get('slug')
                if not slug or not data.get('serverAddress'):
                    return self.respond(400, 'Invalid request body', 'text/plain')
                if any(feed['slug'] == slug for feed in actions['feeds'].values()):
                    return self.respond(400, 'Slug already in use', 'text/plain')
                feed = feed_for(opening[1], slug, data.get('metadataDetails') or {})
                actions['feeds'][opening[1]] = feed
                return self.respond(200, {'feed': feed})
            closing = re.fullmatch(r'/api/feeds/([^/]+)/close', path or '')
            if closing:
                self.rfile.read(int(self.headers.get('Content-Length', 0)))
                self.route()
                if not self.authorized():
                    return self.respond(401, {})
                if not self.is_admin():
                    return self.respond(403, {})
                item_id = next((key for key, feed in actions['feeds'].items() if feed['id'] == closing[1]), None)
                if item_id is None:
                    return self.respond(404, {})
                del actions['feeds'][item_id]
                return self.respond(200, {})
            if path == '/__android__/slow-discard':
                discard_delay['seconds'] = float(self.body().get('seconds', 0))
                self.route()
                return self.respond(200, discard_delay)
            if path == '/__android__/refuse-reading':
                refusal['reading'] = bool(self.body().get('refuse'))
                self.route()
                return self.respond(200, refusal)
            if path == '/__android__/refuse-listening':
                data = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
                refusal['listening'] = bool(data.get('refuse'))
                self.route()
                return self.respond(200, refusal)
            if path == '/__fixture__/configure':
                body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
                self.rfile = io.BytesIO(body)
                reset_actions(json.loads(body or b'{}').get('mode', ''))
                refusal['listening'] = False
                refusal['reading'] = False
                discard_delay['seconds'] = 0
                for probe, entries, original in zip(probes, accounts, originals):
                    for key in [key for key in entries if key not in original]:
                        del entries[key]
                    for key, entry in original.items():
                        entries.setdefault(key, copy.deepcopy(entry))
                    probe.account['bookmarks'] = []
                    probe.account['mediaProgress'] = list(entries.values())
            if path == '/api/session/local-all' and refusal['listening']:
                self.rfile.read(int(self.headers.get('Content-Length', 0)))
                self.route()
                return self.respond(503, {})
            super().do_POST()

        def do_DELETE(self):
            discard = re.fullmatch(r'/api/me/progress/([^/]+)', self.own_path() or '')
            if discard:
                self.route()
                if not self.authorized():
                    return self.respond(401, {})
                self.identify_progress()
                time.sleep(discard_delay['seconds'])
                key = next((key for key, entry in self.progress.items() if entry.get('id') == discard[1]), None)
                if key is None:
                    return self.respond(404, {})
                del self.progress[key]
                self.account['mediaProgress'] = list(self.progress.values())
                return self.respond(200, {})
            super().do_DELETE()

    server.RequestHandlerClass = AndroidHandler
    return server, prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--prefix', default='/abs')
    parser.add_argument('--tls-cert')
    parser.add_argument('--tls-key')
    args = parser.parse_args()
    server, prefix = android_server(args.port, args.prefix)
    if args.tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.tls_cert, args.tls_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f"{'https' if args.tls_cert else 'http'}://127.0.0.1:{server.server_port}{prefix}", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
