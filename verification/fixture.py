"""Synthetic local Audiobookshelf reference server; loopback by default, never uses live credentials."""
import argparse
import io
import json
import math
import re
import struct
import ssl
import time
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


def make_server(port=18765, prefix='/abs', scenario='baseline', auth_mode='modern', bind='127.0.0.1'):
    tracks = [audio(8), audio(12)]
    chapters = [{'id': 0, 'title': 'Opening', 'start': 0, 'end': 8}, {'id': 1, 'title': 'Next chapter', 'start': 8, 'end': 20}]
    items = [{'id': f'book-{i}', 'mediaType': 'book', 'media': {
        'metadata': {'title': f'Stories for Tomorrow {i + 1:02}', 'authorName': 'Audiobookshelf QA', 'authors': [{'id': 'author', 'name': 'Audiobookshelf QA'}],
                     'narrators': ['QA Narrator'], 'genres': ['Fiction'], 'description': '<p>Synthetic two-file audio. No live library data.</p>'},
        'duration': 20, 'numTracks': 2, 'chapters': chapters}} for i in range(61)]
    user = {'id': '00000000-0000-4000-8000-000000000001', 'username': 'qa', 'type': 'user',
            'permissions': {'download': True, 'update': True, 'delete': False, 'upload': False},
            'mediaProgress': [], 'bookmarks': [], 'settings': {}}
    sessions = {}
    progress = {('book-0', None): {'libraryItemId': 'book-0', 'episodeId': None, 'currentTime': 6, 'duration': 20, 'progress': 0.3, 'isFinished': False}, ('book-60', None): {'libraryItemId': 'book-60', 'episodeId': None, 'currentTime': 6, 'duration': 20, 'progress': 0.3, 'isFinished': False}}
    user['mediaProgress'] = list(progress.values())
    reports = []
    login_outcomes = []
    requests = []
    configuration = {'mode': 'baseline', 'failed': False}
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
            observed = {'method': self.command, 'path': path}
            if path and re.fullmatch(r'/api/libraries/[^/]+/items', path):
                observed['page'] = parse_qs(parsed.query).get('page', ['0'])[0]
            requests.append(observed)
            return path, parse_qs(parsed.query)

        def authorized(self):
            return self.headers.get('Authorization') == 'Bearer fresh'

        def do_GET(self):
            path, query = self.route()
            if path == '/status':
                return self.respond(200, {'isInit': True, 'version': '2.30.0-fixture', 'authMethods': ['local'], 'language': 'en-us', 'serverSettings': {}})
            if path == '/__fixture__/observations':
                return self.respond(200, {'reports': reports, 'requests': requests, 'loginOutcomes': login_outcomes})
            if not self.authorized():
                return self.respond(401, {'error': 'Unauthorized'})
            if path == '/api/libraries':
                return self.respond(200, {'libraries': [{'id': 'books', 'name': 'Audiobooks', 'mediaType': 'book'}, {'id': 'podcasts', 'name': 'Podcasts', 'mediaType': 'podcast'}]})
            if path == '/api/libraries/books/items':
                page = max(0, int(query.get('page', ['0'])[0])); limit = min(100, max(1, int(query.get('limit', ['60'])[0])))
                mode = configuration['mode']
                if mode == 'empty':
                    return self.respond(200, {'results': [], 'total': 0})
                if not configuration['failed'] and (mode == 'catalog-error' or mode == 'page-error' and page == 1):
                    configuration['failed'] = True
                    return self.respond(503, {'error': 'Synthetic temporary failure'})
                return self.respond(200, {'items' if scenario == 'library-schema-change' else 'results': items[page * limit:(page + 1) * limit], 'total': len(items), 'limit': limit, 'page': page})
            if path == '/api/libraries/books/personalized':
                if configuration['mode'] == 'empty':
                    return self.respond(200, [])
                return self.respond(200, [{'id': 'continue-listening', 'label': 'Continue Listening', 'type': 'book', 'entities': [items[int(key[0].removeprefix('book-'))] for key, value in progress.items() if key[0].startswith('book-') and value.get('currentTime', 0) > 0 and not value.get('isFinished')], 'total': len(progress)}, {'id': 'recently-added', 'label': 'Recently Added', 'type': 'book', 'entities': items[:10], 'total': 61}])
            if path == '/api/me':
                return self.respond(200, {**user, 'permissions': {'download': False, 'update': False, 'delete': False, 'upload': False}} if configuration['mode'] == 'edge-metadata' else user)
            if path == '/api/items/podcast':
                return self.respond(200, {'id': 'podcast', 'mediaType': 'podcast', 'media': {'metadata': {'title': 'Evening Stories', 'author': 'QA Studio'}, 'episodes': [{'id': 'episode', 'title': 'A Quiet Evening', 'duration': 20}]}})
            if path and path.startswith('/api/items/book-') and not path.endswith('/cover'):
                try:
                    return self.respond(200, items[int(path.rsplit('-', 1)[1])])
                except (ValueError, IndexError):
                    return self.respond(404, {})
            if path and path.endswith('/cover'):
                if configuration['mode'] == 'edge-metadata':
                    return self.respond(404, {})
                image = Path(__file__).resolve().parents[1] / 'static/book_placeholder.jpg'
                return self.respond(200, image.read_bytes(), 'image/jpeg')
            if path in ('/audio/0', '/audio/1'):
                if configuration['mode'] == 'slow-audio':
                    time.sleep(2)
                data = tracks[int(path[-1])]
                start, end = 0, len(data) - 1
                if self.headers.get('Range'):
                    value = re.fullmatch(r'bytes=([0-9]*)-([0-9]*)', self.headers['Range'])
                    valid = value is not None and any(value.groups())
                    if valid:
                        first, last = value.groups()
                        if not first:
                            length = int(last)
                            start = max(0, len(data) - length)
                            valid = length > 0
                        else:
                            start = int(first)
                            end = min(int(last) if last else end, end)
                        valid = valid and 0 <= start <= end < len(data)
                    if not valid:
                        self.send_response(416)
                        self.send_header('Content-Range', f'bytes */{len(data)}')
                        self.headers_for('audio/wav', 0)
                        self.end_headers()
                        return
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
            if path == '/__fixture__/configure':
                mode = data.get('mode')
                if mode not in ('baseline', 'empty', 'catalog-error', 'page-error', 'edge-metadata', 'slow-audio', 'slow-session', 'no-audio'):
                    return self.respond(400, {})
                configuration.update(mode=mode, failed=False)
                items[0]['media']['metadata']['title'] = 'A Very Long Story Title About Finding Your Way Home Through A City Of Unexpected Doors And Forgotten Libraries' if mode == 'edge-metadata' else 'Stories for Tomorrow 01'
                items[0]['media']['duration'] = 1e30 if mode == 'edge-metadata' else 20
                if mode in ('baseline', 'slow-audio', 'slow-session', 'no-audio'):
                    reports.clear()
                    progress[('book-0', None)].update(currentTime=6, duration=20, progress=0.3, isFinished=False)
                    user['mediaProgress'] = list(progress.values())
                return self.respond(200, {})
            if path == '/login':
                login_outcomes.append({'accepted': data == {'username': 'qa', 'password': 'qa'}, 'usernameMatches': data.get('username') == 'qa', 'passwordMatches': data.get('password') == 'qa'})
                if data != {'username': 'qa', 'password': 'qa'}:
                    return self.respond(401, {})
                return self.respond(200, {'user': {**user, **({'token': 'fresh'} if auth_mode == 'legacy' else {'token': 'expired', 'accessToken': 'expired', 'refreshToken': 'refresh'})},
                    'serverSettings': {'version': '2.30.0-fixture', 'language': 'en-us'}, 'userDefaultLibraryId': 'books', 'ereaderDevices': []})
            if path == '/auth/refresh':
                if self.headers.get('x-refresh-token') != 'refresh':
                    return self.respond(401, {})
                return self.respond(200, {'user': {**user, 'token': 'fresh', 'accessToken': 'fresh', 'refreshToken': 'refresh'}})
            if not self.authorized():
                return self.respond(401, {})
            play = re.fullmatch(r'/api/items/(book-[0-9]+|podcast)/play(?:/(episode))?', path or '')
            if play:
                if configuration['mode'] == 'slow-session':
                    time.sleep(4)
                item_id, episode_id = play.groups()
                if item_id == 'podcast':
                    if episode_id != 'episode':
                        return self.respond(404, {})
                    title = 'A Quiet Evening'
                else:
                    index = int(item_id.removeprefix('book-'))
                    if index >= len(items) or episode_id is not None:
                        return self.respond(404, {})
                    title = items[index]['media']['metadata']['title']
                session_id = f'session-{len(sessions) + 1}'
                result = {'id': session_id, 'libraryItemId': item_id, 'episodeId': episode_id, 'currentTime': progress.get((item_id, episode_id), {}).get('currentTime', 6), 'duration': 20, 'playMethod': 0,
                    'displayTitle': title, 'displayAuthor': 'QA Studio', 'audioTracks': [
                        {'contentUrl': '/audio/0', 'startOffset': 0, 'duration': 8, 'mimeType': 'audio/wav'},
                        {'contentUrl': '/audio/1', 'startOffset': 8, 'duration': 12, 'mimeType': 'audio/wav'}], 'chapters': chapters}
                sessions[session_id] = result
                if configuration['mode'] == 'no-audio':
                    result['audioTracks'] = []
                return self.respond(200, result)
            report = re.fullmatch(r'/api/session/([^/]+)/(sync|close)', path or '')
            if report and report.group(1) in sessions:
                session = sessions[report.group(1)]
                key = (session['libraryItemId'], session['episodeId'])
                progress[key] = {'libraryItemId': key[0], 'episodeId': key[1], **data}
                position = float(data.get('currentTime', 0))
                duration = float(data.get('duration', session['duration']))
                progress[key]['progress'] = min(max(position / duration, 0), 1) if duration > 0 else 0
                progress[key]['isFinished'] = duration > 0 and position >= duration
                user['mediaProgress'] = list(progress.values())
                reports.append({'path': path, **data})
                return self.respond(200, {})
            self.respond(404, {})

    return ThreadingHTTPServer((bind, port), Handler), prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=18765)
    parser.add_argument('--prefix', default='/abs')
    parser.add_argument('--scenario', choices=['baseline', 'library-schema-change'], default='baseline')
    parser.add_argument('--auth-mode', choices=['legacy', 'modern'], default='modern')
    parser.add_argument('--bind', default='127.0.0.1', help='Explicit private IPv4 address for a LAN-device fixture; loopback by default')
    parser.add_argument('--tls-cert')
    parser.add_argument('--tls-key')
    args = parser.parse_args()
    if bool(args.tls_cert) != bool(args.tls_key):
        parser.error('TLS requires both the synthetic certificate and its key.')
    import ipaddress
    address = ipaddress.IPv4Address(args.bind)
    if not address.is_private or address.is_unspecified or address.is_multicast:
        parser.error('The synthetic fixture must bind to an explicit loopback or private LAN IPv4 address.')
    server, prefix = make_server(args.port, args.prefix, args.scenario, args.auth_mode, args.bind)
    if args.tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.tls_cert, args.tls_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    scheme = 'https' if args.tls_cert else 'http'
    print(f'{scheme}://{args.bind}:{server.server_port}{prefix}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
