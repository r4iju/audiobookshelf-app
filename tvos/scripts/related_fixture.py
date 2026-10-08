"""Synthetic Audiobookshelf 2.30 author and series endpoints on top of verification/fixture.py.

Shapes follow the 2.30 server source: AuthorController.findOne/getImage, LibraryController.getSeriesForLibrary
(`/api/libraries/:id/series/:seriesId`, which the server asks mobile clients to use over the deprecated global
`/api/series/:id`), LibraryController.getAllSeriesForLibrary (seriesFilters, `filter=authors.<base64>`), and library items
filtered by `authors.<base64>` or `series.<base64>` with `sort=sequence` (CAST(sequence AS FLOAT), nulls last).
Book data, authorization and progress come from the base fixture through an authenticated loopback request.
"""
import argparse
import base64
import json
import re
import ssl
import struct
import sys
import urllib.error
import urllib.request
import zlib
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verification.fixture import make_server  # noqa: E402

AUTHOR = {'id': 'author', 'asin': None, 'name': 'Audiobookshelf QA', 'libraryId': 'books', 'imagePath': '/metadata/authors/author.png',
          'description': 'Audiobookshelf QA writes synthetic stories for verifying listening apps. Every title here is generated test data.',
          'addedAt': 1700000000000, 'updatedAt': 1700000000000}
# Sequences are deliberately out of title order and include a decimal and a double-digit entry,
# so a client that sorts by title or as text shows the wrong order.
SERIES = [
    {'id': 'series-saga', 'name': 'The Tomorrow Saga', 'description': 'Read in order: each story picks up where the last one ends.',
     'books': [('book-5', '1'), ('book-2', '2'), ('book-9', '2.5'), ('book-1', '10')]},
    {'id': 'series-evening', 'name': 'Evening Tales', 'description': None, 'books': [('book-3', '1')]},
]


def png(width=8, height=8, color=(237, 128, 63)):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    pixels = b''.join(b'\x00' + bytes(color) * width for _ in range(height))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


def decode(value):
    return base64.b64decode(value.replace(' ', '+')).decode()


def series_json(series):
    return {'id': series['id'], 'name': series['name'], 'nameIgnorePrefix': series['name'].removeprefix('The ') + (', The' if series['name'].startswith('The ') else ''),
            'description': series['description'], 'addedAt': 1700000000000, 'updatedAt': 1700000000000, 'libraryId': 'books'}


def membership(item_id):
    return [(series, sequence) for series in SERIES for book, sequence in series['books'] if book == item_id]


def make_related_server(port, prefix='/abs', bind='127.0.0.1'):
    server, prefix = make_server(port, prefix, bind=bind)
    base = server.RequestHandlerClass
    state = {'fail': None, 'observations': []}

    class Relay(Exception):
        def __init__(self, status, body):
            self.status, self.body = status, body

    class RelatedHandler(base):
        def loopback(self, path):
            tls = getattr(self.server, 'related_tls', False)
            request = urllib.request.Request(f"{'https' if tls else 'http'}://127.0.0.1:{self.server.server_port}{prefix}{path}",
                                             headers={'Authorization': self.headers.get('Authorization', ''), 'X-Related-Loopback': '1'})
            try:
                with urllib.request.urlopen(request, timeout=5, context=ssl._create_unverified_context() if tls else None) as response:
                    return json.loads(response.read())
            except urllib.error.HTTPError as error:
                raise Relay(error.code, error.read())

        def all_books(self):
            return self.loopback('/api/libraries/books/items?limit=100&page=0&minified=1')['results']

        def with_series(self, item, expanded):
            item = json.loads(json.dumps(item))
            # Every 2.30 item shape (minified, expanded) carries its libraryId; the base fixture omits it.
            item.setdefault('libraryId', 'books' if item.get('mediaType') == 'book' else 'podcasts')
            members = membership(item['id'])
            if not members:
                return item
            metadata = item['media']['metadata']
            metadata['seriesName'] = ', '.join(f"{series['name']} #{sequence}" for series, sequence in members)
            if expanded:
                metadata['series'] = [{'id': series['id'], 'name': series['name'], 'sequence': sequence} for series, sequence in members]
            return item

        def handled(self, path, query):
            if self.headers.get('X-Related-Loopback'):
                return False
            try:
                return self.related(path, query)
            except Relay as relay:
                self.respond(relay.status, relay.body)
                return True

        def related(self, path, query):
            if path == '/__related__/configure' and self.command == 'POST':
                body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or b'{}')
                state['fail'] = body.get('fail')
                state['observations'].clear()
                self.respond(200, {})
                return True
            if path == '/__related__/reset-progress' and self.command == 'POST':
                # Configure also runs mid-journey, so only this explicit test boundary resets secondary titles.
                for key in list(self.progress):
                    if key[0] != 'book-0':
                        del self.progress[key]
                self.account['mediaProgress'] = list(self.progress.values())
                self.respond(200, {})
                return True
            if path == '/__related__/observations':
                # Earlier journeys in the same run may finish books, so report what the series progress now counts.
                finished = {series['id']: sum(1 for book, _ in series['books'] if self.progress.get((book, None), {}).get('isFinished')) for series in SERIES}
                self.respond(200, {'requests': state['observations'], 'finished': finished})
                return True
            series_detail = re.fullmatch(r'/api/libraries/([^/]+)/series/([^/]+)', path)
            related = path.startswith('/api/authors/') or series_detail or path == '/api/libraries/books/series'
            filtered = path == '/api/libraries/books/items' and query.get('filter', [''])[0].split('.')[0] in ('authors', 'series')
            item = path.startswith('/api/items/') and path.count('/') == 3
            search = path == '/api/libraries/books/search'
            if not (related or filtered or item or search):
                return False
            self.route()
            if not self.authorized():
                self.respond(401, {})
                return True
            state['observations'].append({'path': path, 'query': {key: values[0] for key, values in query.items()}})
            kind = 'author' if path.startswith('/api/authors/') else 'series' if 'series' in path or query.get('filter', [''])[0].startswith('series.') else None
            if kind and state['fail'] == kind:
                state['fail'] = None
                self.respond(503, {'error': 'Synthetic temporary failure'})
                return True
            if path == '/api/authors/author/image':
                self.respond(200, png(), 'image/png')
                return True
            if path.startswith('/api/authors/'):
                if path != '/api/authors/author':
                    self.respond(404, {})
                    return True
                author = dict(AUTHOR)
                include = query.get('include', [''])[0].split(',')
                if 'items' in include:
                    books = self.all_books()
                    author['libraryItems'] = books
                    if 'series' in include:
                        author['series'] = [{'id': series['id'], 'name': series['name'], 'items': [self.with_series(book, False) for book in self.ordered(series, books)]} for series in SERIES]
                self.respond(200, author)
                return True
            if series_detail:
                library, series_id = series_detail.groups()
                series = next((entry for entry in SERIES if entry['id'] == series_id), None)
                if library != 'books' or series is None:
                    self.respond(404, {})
                    return True
                result = series_json(series)
                if 'progress' in query.get('include', [''])[0].split(','):
                    finished = [book for book, _ in series['books'] if self.progress.get((book, None), {}).get('isFinished')]
                    result['progress'] = {'libraryItemIds': [book for book, _ in series['books']], 'libraryItemIdsFinished': finished, 'isFinished': len(finished) == len(series['books'])}
                self.respond(200, result)
                return True
            if path == '/api/libraries/books/series':
                selected = query.get('filter', [''])[0]
                matches = SERIES if not selected else [entry for entry in SERIES if selected.startswith('authors.') and decode(selected[8:]) == AUTHOR['id']]
                matches = sorted(matches, key=lambda entry: entry['name'].lower(), reverse=query.get('desc', ['0'])[0] == '1')
                books = self.all_books()
                limit = int(query.get('limit', ['0'])[0]); page = int(query.get('page', ['0'])[0])
                window = matches[page * limit:(page + 1) * limit] if limit else matches
                results = [{**series_json(entry), 'books': [self.with_series(book, False) for book in self.ordered(entry, books)]} for entry in window]
                self.respond(200, {'results': results, 'total': len(matches), 'limit': limit, 'page': page, 'sortBy': query.get('sort', [None])[0], 'sortDesc': False, 'filterBy': selected or None, 'minified': True, 'include': ''})
                return True
            if filtered:
                group, value = query['filter'][0].split('.', 1)
                value = decode(value)
                books = self.all_books()
                limit = min(100, max(1, int(query.get('limit', ['60'])[0]))); page = max(0, int(query.get('page', ['0'])[0]))
                if group == 'authors':
                    matches = [book for book in books if any(author['id'] == value for author in book['media']['metadata'].get('authors', []))]
                    matches = [self.with_series(book, False) for book in matches]
                    if query.get('desc', ['0'])[0] == '1':
                        matches.reverse()
                else:
                    series = next((entry for entry in SERIES if entry['id'] == value), None)
                    matches = []
                    if series:
                        ordered = self.ordered(series, books) if query.get('sort', [''])[0] == 'sequence' else [book for book in books if book['id'] in dict(series['books'])]
                        sequence = dict(series['books'])
                        matches = [{**book, 'media': {**book['media'], 'metadata': {**book['media']['metadata'], 'series': {'id': series['id'], 'name': series['name'], 'sequence': sequence[book['id']]}}}} for book in ordered]
                self.respond(200, {'results': matches[page * limit:(page + 1) * limit], 'total': len(matches), 'limit': limit, 'page': page})
                return True
            if item:
                self.respond(200, self.with_series(self.loopback(path + '?expanded=1'), True))
                return True
            response = self.loopback(path + '?' + urlparse(self.path).query)
            if not isinstance(response, dict):
                self.respond(200, response)
                return True
            text = query.get('q', [''])[0].lower()
            books = None
            response['series'] = []
            for series in SERIES:
                if text and text in series['name'].lower():
                    books = books or self.all_books()
                    response['series'].append({'series': series_json(series), 'books': [self.with_series(book, False) for book in self.ordered(series, books)]})
            for author in response.get('authors') or []:
                if author['id'] == AUTHOR['id']:
                    author.update({key: AUTHOR[key] for key in ('description', 'imagePath', 'libraryId')}, numBooks=61)
            self.respond(200, response)
            return True

        @staticmethod
        def ordered(series, books):
            by_id = {book['id']: book for book in books}
            return [by_id[book] for book, _ in sorted(series['books'], key=lambda entry: float(entry[1])) if book in by_id]

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path.startswith(prefix + '/') and self.handled(parsed.path[len(prefix):], parse_qs(parsed.query)):
                return
            super().do_GET()

        def do_POST(self):
            parsed = urlparse(self.path)
            if parsed.path in (prefix + '/__related__/configure', prefix + '/__related__/reset-progress') and self.handled(parsed.path[len(prefix):], {}):
                return
            super().do_POST()

    server.RequestHandlerClass = RelatedHandler
    return server, prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--prefix', default='/abs')
    parser.add_argument('--tls-cert')
    parser.add_argument('--tls-key')
    args = parser.parse_args()
    server, prefix = make_related_server(args.port, args.prefix)
    if args.tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.tls_cert, args.tls_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        server.related_tls = True
    print(f"{'https' if args.tls_cert else 'http'}://127.0.0.1:{server.server_port}{prefix}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
