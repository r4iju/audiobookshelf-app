"""Synthetic local Audiobookshelf reference server; loopback by default, never uses live credentials."""
import argparse
import base64
import copy
import hashlib
import html
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
from urllib.parse import parse_qs, urlencode, urlparse


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
    podcast = {'id': 'podcast', 'mediaType': 'podcast', 'media': {'metadata': {'title': 'Evening Stories', 'author': 'QA Studio'}, 'episodes': [{'id': 'episode', 'title': 'A Quiet Evening', 'duration': 20}]}}
    sessions = {}
    progress = {('book-0', None): {'libraryItemId': 'book-0', 'episodeId': None, 'currentTime': 6, 'duration': 20, 'progress': 0.3, 'isFinished': False}, ('book-60', None): {'libraryItemId': 'book-60', 'episodeId': None, 'currentTime': 6, 'duration': 20, 'progress': 0.3, 'isFinished': False}}
    user['mediaProgress'] = list(progress.values())
    other_user = {**copy.deepcopy(user), 'id': '00000000-0000-4000-8000-000000000002', 'username': 'qa-other'}
    users = {'qa': user, 'qa-other': other_user}
    progress_by_user = {user['id']: progress, other_user['id']: copy.deepcopy(progress)}
    progress_by_user[other_user['id']][('book-0', None)].update(currentTime=2, progress=0.1)
    other_user['mediaProgress'] = list(progress_by_user[other_user['id']].values())
    reports = []
    local_sessions = {}
    openid_sessions = {}
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

        def respond(self, status, value, kind='application/json', headers=None):
            data = value if isinstance(value, bytes) else json.dumps(value).encode()
            self.send_response(status)
            self.headers_for(kind, len(data))
            for name, value in (headers or {}).items():
                self.send_header(name, value)
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
            return self.headers.get('Authorization') in ('Bearer fresh', 'Bearer fresh-other')

        @property
        def account(self):
            return other_user if self.headers.get('Authorization') == 'Bearer fresh-other' else user

        @property
        def progress(self):
            return progress_by_user[self.account['id']]

        def do_GET(self):
            path, query = self.route()
            if path == '/status':
                return self.respond(200, {'isInit': True, 'version': '2.30.0-fixture', 'authMethods': ['local', 'openid'] if configuration['mode'].startswith('openid') else ['local'], 'language': 'en-us', 'serverSettings': {}})
            if path == '/auth/openid' and configuration['mode'].startswith('openid'):
                state = query.get('state', [''])[0]
                challenge = query.get('code_challenge', [''])[0]
                callback = query.get('redirect_uri', [''])[0]
                if not state or not challenge or callback != 'audiobookshelf-native-preview://oauth' or query.get('code_challenge_method') != ['S256']:
                    return self.respond(400, {})
                openid_sessions[state] = {'challenge': challenge, 'callback': callback}
                if configuration['mode'] == 'openid-invalid-provider-state':
                    state = 'changed-provider-state'
                    openid_sessions[state] = {'challenge': challenge, 'callback': callback}
                provider_query = urlencode({'state': state, 'client_id': 'local-fixture', 'scope': 'openid profile', 'code_challenge': challenge, 'code_challenge_method': 'S256', 'redirect_uri': f'http://{self.headers["Host"]}{prefix}/auth/openid/mobile-redirect'})
                return self.respond(302, {}, headers={'Location': f'http://{self.headers["Host"]}{prefix}/__fixture__/provider?{provider_query}', 'Set-Cookie': f'abs_oidc={state}; Path={prefix or "/"}; HttpOnly; SameSite=Lax'})
            if path == '/__fixture__/provider':
                state = query.get('state', [''])[0]
                if state not in openid_sessions:
                    return self.respond(400, {})
                link = prefix + '/auth/openid/mobile-redirect?' + urlencode({'state': state, 'code': 'fixture-code'})
                page = '<!doctype html><meta name="viewport" content="width=device-width"><h1>Local OpenID</h1><p>Synthetic local sign-in. No external provider.</p><a href="' + html.escape(link, quote=True) + '">Approve sign-in</a>'
                return self.respond(200, page.encode(), 'text/html')
            if path == '/auth/openid/mobile-redirect':
                state = query.get('state', [''])[0]
                if state not in openid_sessions or query.get('code') != ['fixture-code']:
                    return self.respond(400, {})
                callback_state = 'wrong-state' if configuration['mode'] == 'openid-invalid-state' else state
                callback = openid_sessions[state]['callback'] + '?' + urlencode({'state': callback_state, 'code': 'fixture-code'})
                return self.respond(302, {}, headers={'Location': callback})
            if path == '/auth/openid/callback':
                state = query.get('state', [''])[0]
                session = openid_sessions.pop(state, None)
                verifier = query.get('code_verifier', [''])[0]
                challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
                if not session or challenge != session['challenge'] or query.get('code') != ['fixture-code'] or f'abs_oidc={state}' not in self.headers.get('Cookie', ''):
                    return self.respond(401, {})
                return self.respond(200, {'user': {**user, 'accessToken': 'expired', 'refreshToken': 'refresh'}})
            if path == '/__fixture__/observations':
                return self.respond(200, {'reports': reports, 'requests': requests, 'loginOutcomes': login_outcomes, 'localSessions': list(local_sessions.values())})
            if not self.authorized():
                return self.respond(401, {'error': 'Unauthorized'})
            if path == '/api/libraries':
                return self.respond(200, {'libraries': [{'id': 'books', 'name': 'Audiobooks', 'mediaType': 'book'}, {'id': 'podcasts', 'name': 'Podcasts', 'mediaType': 'podcast'}]})
            if path == '/api/libraries/podcasts/items':
                return self.respond(200, {'results': [podcast], 'total': 1})
            if path == '/api/libraries/podcasts/personalized':
                return self.respond(200, [])
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
                return self.respond(200, [{'id': 'continue-listening', 'label': 'Continue Listening', 'type': 'book', 'entities': [items[int(key[0].removeprefix('book-'))] for key, value in self.progress.items() if key[0].startswith('book-') and value.get('currentTime', 0) > 0 and not value.get('isFinished')], 'total': len(self.progress)}, {'id': 'recently-added', 'label': 'Recently Added', 'type': 'book', 'entities': items[:10], 'total': 61}])
            if path == '/api/me':
                return self.respond(200, {**self.account, 'permissions': {'download': False, 'update': False, 'delete': False, 'upload': False}} if configuration['mode'] == 'edge-metadata' else self.account)
            if path == '/api/items/podcast':
                return self.respond(200, podcast)
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
                if configuration['mode'] == 'broken-audio':
                    return self.respond(503, {})
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
                if mode not in ('baseline', 'empty', 'catalog-error', 'page-error', 'edge-metadata', 'slow-audio', 'slow-session', 'slow-close', 'broken-audio', 'no-audio', 'offline-progress', 'lost-ack', 'newer-remote', 'openid', 'openid-invalid-state', 'openid-invalid-provider-state'):
                    return self.respond(400, {})
                configuration.update(mode=mode, failed=False)
                items[0]['media']['metadata']['title'] = 'A Very Long Story Title About Finding Your Way Home Through A City Of Unexpected Doors And Forgotten Libraries' if mode == 'edge-metadata' else 'Stories for Tomorrow 01'
                items[0]['media']['duration'] = 1e30 if mode == 'edge-metadata' else 20
                if mode in ('baseline', 'slow-audio', 'slow-session', 'slow-close', 'broken-audio', 'no-audio', 'offline-progress'):
                    reports.clear()
                    local_sessions.clear()
                    for account in users.values():
                        position = 6 if account['username'] == 'qa' else 2
                        progress_by_user[account['id']][('book-0', None)].update(currentTime=position, duration=20, progress=position / 20, isFinished=False, lastUpdate=0)
                        account['mediaProgress'] = list(progress_by_user[account['id']].values())
                if mode == 'newer-remote':
                    progress[('book-0', None)].update(currentTime=19, duration=20, progress=0.95, isFinished=False, lastUpdate=time.time() * 1000)
                    user['mediaProgress'] = list(progress.values())
                return self.respond(200, {})
            if path == '/login':
                accepted = data.get('username') in users and data.get('password') == 'qa'
                login_outcomes.append({'accepted': accepted, 'usernameMatches': data.get('username') in users, 'passwordMatches': data.get('password') == 'qa'})
                if not accepted:
                    return self.respond(401, {})
                suffix = '-other' if data['username'] == 'qa-other' else ''
                return self.respond(200, {'user': {**users[data['username']], **({'token': 'fresh' + suffix} if auth_mode == 'legacy' else {'token': 'expired' + suffix, 'accessToken': 'expired' + suffix, 'refreshToken': 'refresh' + suffix})},
                    'serverSettings': {'version': '2.30.0-fixture', 'language': 'en-us'}, 'userDefaultLibraryId': 'books', 'ereaderDevices': []})
            if path == '/auth/refresh':
                token = self.headers.get('x-refresh-token')
                if token not in ('refresh', 'refresh-other'):
                    return self.respond(401, {})
                suffix = '-other' if token == 'refresh-other' else ''
                account = other_user if suffix else user
                return self.respond(200, {'user': {**account, 'token': 'fresh' + suffix, 'accessToken': 'fresh' + suffix, 'refreshToken': 'refresh' + suffix}})
            if not self.authorized():
                return self.respond(401, {})
            if path == '/api/session/local-all':
                if configuration['mode'] == 'offline-progress':
                    return self.respond(503, {})
                results = []
                for record in data.get('sessions', []):
                    key = (record['libraryItemId'], record.get('episodeId'))
                    local_sessions[record['id']] = record.copy()
                    current = self.progress.get(key, {})
                    newer_remote = current.get('lastUpdate', 0) > record['updatedAt']
                    if not newer_remote:
                        duration = record['duration']
                        position = record['currentTime']
                        self.progress[key] = {'libraryItemId': key[0], 'episodeId': key[1], 'duration': duration, 'currentTime': position,
                                         'progress': min(max(position / duration, 0), 1), 'isFinished': position >= duration, 'lastUpdate': record['updatedAt']}
                    reports.append({'path': path, 'currentTime': record['currentTime'], 'timeListened': record['timeListening'], 'sessionId': record['id'], 'userId': self.account['id']})
                    results.append({'id': record['id'], 'success': True, 'progressSynced': not newer_remote})
                self.account['mediaProgress'] = list(self.progress.values())
                if configuration['mode'] == 'lost-ack' and not configuration['failed']:
                    configuration['failed'] = True
                    return self.respond(503, {})
                return self.respond(200, {'results': results})
            play = re.fullmatch(r'/api/items/(book-[0-9]+|podcast)/play(?:/(episode))?', path or '')
            if play:
                delay_response = configuration['mode'] == 'slow-session'
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
                result = {'id': session_id, 'userId': self.account['id'], 'libraryItemId': item_id, 'episodeId': episode_id, 'currentTime': self.progress.get((item_id, episode_id), {}).get('currentTime', 6), 'duration': 20, 'playMethod': 0,
                    'displayTitle': title, 'displayAuthor': 'QA Studio', 'audioTracks': [
                        {'contentUrl': '/audio/0', 'startOffset': 0, 'duration': 8, 'mimeType': 'audio/wav'},
                        {'contentUrl': '/audio/1', 'startOffset': 8, 'duration': 12, 'mimeType': 'audio/wav'}], 'chapters': chapters}
                sessions[session_id] = result
                if configuration['mode'] == 'no-audio':
                    result['audioTracks'] = []
                if delay_response:
                    time.sleep(8)
                return self.respond(200, result)
            report = re.fullmatch(r'/api/session/([^/]+)/(sync|close)', path or '')
            if report and report.group(1) in sessions:
                if configuration['mode'] == 'offline-progress':
                    return self.respond(503, {})
                if configuration['mode'] == 'slow-close' and report.group(2) == 'close':
                    time.sleep(8)
                session = sessions[report.group(1)]
                if session['userId'] != self.account['id']:
                    return self.respond(403, {})
                if not data:
                    return self.respond(200, {})
                key = (session['libraryItemId'], session['episodeId'])
                self.progress[key] = {'libraryItemId': key[0], 'episodeId': key[1], **data}
                position = float(data.get('currentTime', 0))
                duration = float(data.get('duration', session['duration']))
                self.progress[key]['progress'] = min(max(position / duration, 0), 1) if duration > 0 else 0
                self.progress[key]['isFinished'] = duration > 0 and position >= duration
                self.account['mediaProgress'] = list(self.progress.values())
                reports.append({'path': path, 'userId': self.account['id'], **data})
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
