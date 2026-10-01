"""Loopback-only, synthetic Audiobookshelf reference server; never uses live credentials."""
import argparse
import io
import json
import math
import struct
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def audio(seconds):
    data = io.BytesIO()
    with wave.open(data, 'wb') as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(16000)
        stream.writeframes(b''.join(struct.pack('<h', int(600 * math.sin(2 * math.pi * 220 * i / 16000))) for i in range(seconds * 16000)))
    return data.getvalue()


def make_server(port=18765, prefix='/abs'):
    tracks = [audio(8), audio(12)]
    chapters = [{'id': 0, 'title': 'Opening', 'start': 0, 'end': 8}, {'id': 1, 'title': 'Next chapter', 'start': 8, 'end': 20}]
    items = [{'id': f'book-{i}', 'mediaType': 'book', 'media': {
        'metadata': {'title': f'Stories for Tomorrow {i + 1:02}', 'authorName': 'Audiobookshelf QA', 'authors': [{'id': 'author', 'name': 'Audiobookshelf QA'}],
                     'description': '<p>Synthetic two-file audio. No live library data.</p>'},
        'duration': 20, 'numTracks': 2, 'chapters': chapters}} for i in range(61)]
    user = {'id': '00000000-0000-4000-8000-000000000001', 'username': 'qa', 'type': 'user',
            'permissions': {'download': True, 'update': True, 'delete': False, 'upload': False},
            'mediaProgress': [], 'bookmarks': [], 'settings': {}}
    reports = []
    requests = []
    prefix = '/' + prefix.strip('/') if prefix.strip('/') else ''

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def headers_for(self, kind, size):
            self.send_header('Content-Type', kind)
            self.send_header('Content-Length', str(size))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type, x-return-tokens, x-refresh-token')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')

        def respond(self, status, value, kind='application/json'):
            data = value if isinstance(value, bytes) else json.dumps(value).encode()
            self.send_response(status)
            self.headers_for(kind, len(data))
            self.end_headers()
            self.wfile.write(data)

        def do_OPTIONS(self):
            self.respond(200, {})

        def route(self):
            parsed = urlparse(self.path)
            if prefix and not parsed.path.startswith(prefix + '/'):
                return None, {}
            path = parsed.path[len(prefix):]
            requests.append({'method': self.command, 'path': path})
            return path, parse_qs(parsed.query)

        def authorized(self):
            return self.headers.get('Authorization') == 'Bearer fresh'

        def do_GET(self):
            path, query = self.route()
            if path == '/status':
                return self.respond(200, {'isInit': True, 'version': '2.30.0-fixture', 'authMethods': ['local'], 'language': 'en-us', 'serverSettings': {}})
            if path == '/__fixture__/observations':
                return self.respond(200, {'reports': reports, 'requests': requests})
            if not self.authorized():
                return self.respond(401, {'error': 'Unauthorized'})
            if path == '/api/libraries':
                return self.respond(200, {'libraries': [{'id': 'books', 'name': 'Audiobooks', 'mediaType': 'book'}, {'id': 'podcasts', 'name': 'Podcasts', 'mediaType': 'podcast'}]})
            if path == '/api/libraries/books/items':
                page = max(0, int(query.get('page', ['0'])[0])); limit = min(100, max(1, int(query.get('limit', ['60'])[0])))
                return self.respond(200, {'results': items[page * limit:(page + 1) * limit], 'total': len(items), 'limit': limit, 'page': page})
            if path == '/api/libraries/books/personalized':
                return self.respond(200, [{'id': 'recently-added', 'label': 'Recently Added', 'type': 'book', 'entities': items[:10], 'total': 61}])
            if path == '/api/me':
                return self.respond(200, user)
            if path == '/api/items/podcast':
                return self.respond(200, {'id': 'podcast', 'mediaType': 'podcast', 'media': {'metadata': {'title': 'Evening Stories', 'author': 'QA Studio'}, 'episodes': [{'id': 'episode', 'title': 'A Quiet Evening', 'duration': 20}]}})
            if path and path.startswith('/api/items/book-') and not path.endswith('/cover'):
                try:
                    return self.respond(200, items[int(path.rsplit('-', 1)[1])])
                except (ValueError, IndexError):
                    return self.respond(404, {})
            if path and path.endswith('/cover'):
                image = Path(__file__).resolve().parents[1] / 'static/book_placeholder.jpg'
                return self.respond(200, image.read_bytes(), 'image/jpeg')
            if path in ('/audio/0', '/audio/1'):
                data = tracks[int(path[-1])]
                start, end = 0, len(data) - 1
                if self.headers.get('Range'):
                    value = self.headers['Range'].split('=')[1].split('-')
                    if not value[0]:
                        start = max(0, len(data) - int(value[1]))
                    else:
                        start = int(value[0]); end = min(int(value[1]) if value[1] else end, end)
                    self.send_response(206)
                    self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
                else:
                    self.send_response(200)
                self.headers_for('audio/wav', end - start + 1)
                self.send_header('Accept-Ranges', 'bytes')
                self.end_headers()
                self.wfile.write(data[start:end + 1])
                return
            self.respond(404, {'error': 'Not found'})

        def do_POST(self):
            path, _ = self.route()
            try:
                data = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
            except (ValueError, TypeError):
                return self.respond(400, {})
            if path == '/login':
                if data != {'username': 'qa', 'password': 'qa'}:
                    return self.respond(401, {})
                return self.respond(200, {'user': {**user, 'token': 'expired', 'accessToken': 'expired', 'refreshToken': 'refresh'},
                    'serverSettings': {'version': '2.30.0-fixture', 'language': 'en-us'}, 'userDefaultLibraryId': 'books', 'ereaderDevices': []})
            if path == '/auth/refresh':
                if self.headers.get('x-refresh-token') != 'refresh':
                    return self.respond(401, {})
                return self.respond(200, {'user': {**user, 'token': 'fresh', 'accessToken': 'fresh', 'refreshToken': 'refresh'}})
            if not self.authorized():
                return self.respond(401, {})
            if path and '/play' in path:
                return self.respond(200, {'id': 'session', 'libraryItemId': 'book-0', 'currentTime': 6, 'duration': 20, 'playMethod': 0,
                    'displayTitle': 'Playback fixture', 'displayAuthor': 'QA Studio', 'audioTracks': [
                        {'contentUrl': '/audio/0', 'startOffset': 0, 'duration': 8, 'mimeType': 'audio/wav'},
                        {'contentUrl': '/audio/1', 'startOffset': 8, 'duration': 12, 'mimeType': 'audio/wav'}], 'chapters': chapters})
            if path in ('/api/session/session/sync', '/api/session/session/close'):
                reports.append({'path': path, **data})
                return self.respond(200, {})
            self.respond(404, {})

    return ThreadingHTTPServer(('127.0.0.1', port), Handler), prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=18765)
    parser.add_argument('--prefix', default='/abs')
    args = parser.parse_args()
    server, prefix = make_server(args.port, args.prefix)
    print(f'http://127.0.0.1:{server.server_port}{prefix}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
