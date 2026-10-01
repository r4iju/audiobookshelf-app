"""Synthetic local Audiobookshelf reference server; loopback by default, never uses live credentials."""
import argparse
import base64
import copy
import hashlib
import html
import io
import json
import math
import os
import re
import struct
import ssl
import time
import wave
import zipfile
import zlib
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


def pdf(pages=4, rotation=0, title='Stories for Tomorrow'):
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
               f'<< /Type /Pages /Kids [{" ".join(f"{4 + i * 2} 0 R" for i in range(pages))}] /Count {pages} >>'.encode(),
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    for index in range(pages):
        content = f'BT /F1 24 Tf 60 700 Td ({title} - Passage {index + 1}) Tj ET'.encode()
        objects.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Rotate {rotation} /Resources << /Font << /F1 3 0 R >> >> /Contents {5 + index * 2} 0 R >>'.encode())
        objects.append(f'<< /Length {len(content)} >>\nstream\n'.encode() + content + b'\nendstream')
    data = b'%PDF-1.4\n'
    offsets = [0]
    for index, value in enumerate(objects, 1):
        offsets.append(len(data)); data += f'{index} 0 obj\n'.encode() + value + b'\nendobj\n'
    xref = len(data)
    data += f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
    data += b''.join(f'{offset:010} 00000 n \n'.encode() for offset in offsets[1:])
    data += f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    return data


def epub(long=False, styled=False):
    data = io.BytesIO()
    with zipfile.ZipFile(data, 'w') as archive:
        archive.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        archive.writestr('META-INF/container.xml', '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        archive.writestr('OEBPS/book.opf', '<package version="3.0" unique-identifier="id" xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:uuid:abs-fixture</dc:identifier><dc:title>Tomorrow in Two Chapters</dc:title><dc:language>en</dc:language></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="first" href="first.xhtml" media-type="application/xhtml+xml"/><item id="second" href="second.xhtml" media-type="application/xhtml+xml"/><item id="css" href="style.css" media-type="text/css"/><item id="illustration" href="illustration.svg" media-type="image/svg+xml"/></manifest><spine><itemref idref="first"/><itemref idref="second"/></spine></package>')
        archive.writestr('OEBPS/nav.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="first.xhtml">First chapter</a></li><li><a href="second.xhtml">Second chapter</a></li></ol></nav></body></html>')
        archive.writestr('OEBPS/style.css', '.publisher-hidden { display: none !important; } img { width: 64px; height: 64px; }')
        archive.writestr('OEBPS/illustration.svg', '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#ed803f"/></svg>')
        for name, text in [('first' , 'First passage by the window.'), ('second', 'Second passage beneath the stars.')]:
            archive.writestr('OEBPS/' + name + '.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>' + name + '</title>' + ('<link rel="stylesheet" href="style.css"/>' if styled else '') + '</head><body>' + ('<p class="publisher-hidden">Publisher hidden text</p><img src="illustration.svg" alt="Illustration from the publisher"/>' if styled else '') + '<h1>' + text + '</h1>' + ('<p>A real packaged EPUB chapter for local reader acceptance.</p>' * (2000 if long else 1)) + '</body></html>')
    return data.getvalue()


def make_server(port=18765, prefix='/abs', scenario='baseline', auth_mode='modern', bind='127.0.0.1'):
    tracks = [audio(8), audio(12)]
    document = pdf()
    chapters = [{'id': 0, 'title': 'Opening', 'start': 0, 'end': 8}, {'id': 1, 'title': 'Next chapter', 'start': 8, 'end': 20}]
    items = [{'id': f'book-{i}', 'mediaType': 'book', 'media': {
        'metadata': {'title': f'Stories for Tomorrow {i + 1:02}', 'authorName': 'Audiobookshelf QA', 'authors': [{'id': 'author', 'name': 'Audiobookshelf QA'}],
                     'narrators': ['QA Narrator'], 'genres': ['Fiction' if i % 2 == 0 else 'Mystery'], 'description': '<p>Synthetic two-file audio. No live library data.</p>'},
        'duration': 20, 'numTracks': 2, 'chapters': chapters, 'tracks': [{'contentUrl': f'/api/items/book-{i}/file/{j}', 'startOffset': 0 if j == 0 else 8, 'duration': 8 if j == 0 else 12, 'mimeType': 'audio/wav'} for j in range(2)]}} for i in range(61)]
    user = {'id': '00000000-0000-4000-8000-000000000001', 'username': 'qa', 'type': 'user',
            'permissions': {'download': True, 'update': True, 'delete': False, 'upload': False},
            'mediaProgress': [], 'bookmarks': [], 'settings': {}}
    podcast = {'id': 'podcast', 'mediaType': 'podcast', 'media': {'metadata': {'title': 'Evening Stories', 'author': 'QA Studio'}, 'episodes': [{'id': 'episode', 'title': 'A Quiet Evening', 'duration': 20, 'publishedAt': 1000}, {'id': 'episode-morning', 'title': 'The Morning After', 'duration': 20, 'publishedAt': 2000}]}}
    for episode in podcast['media']['episodes']:
        episode['audioTrack'] = {'contentUrl': '/api/items/podcast/file/' + episode['id'], 'duration': 20, 'startOffset': 0, 'mimeType': 'audio/wav', 'metadata': {'filename': episode['id'] + '.wav', 'ext': '.wav'}}
        episode['audioFile'] = {'duration': 20, 'metadata': {'filename': episode['id'] + '.wav'}}
    sessions = {}
    created_podcasts = []
    pending_feed_downloads = []
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
    realtime_authentications = []
    configuration = {'mode': 'baseline', 'failed': False}
    collections = [{'id': 'collection-evening', 'libraryId': 'books', 'name': 'Evening shelf', 'description': 'An established listening order.', 'books': [items[2], items[1]]}]
    playlists = [{'id': 'playlist-evening', 'libraryId': 'books', 'userId': user['id'], 'name': 'Evening queue', 'description': 'Personal listening.', 'items': [{'libraryItemId': item['id'], 'libraryItem': item} for item in [items[1], items[2]]]}]
    playlists.append({'id': 'playlist-podcasts', 'libraryId': 'podcasts', 'userId': user['id'], 'name': 'Morning episodes', 'items': [{'libraryItemId': 'podcast', 'libraryItem': podcast, 'episodeId': 'episode-morning', 'episode': {**podcast['media']['episodes'][1], 'description': '<p>The episode selected from this playlist.</p>', 'audioFile': {'duration': 20}}}]})
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
            self.observed_request = observed
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

        def mutate_group(self, path, data):
            match = re.fullmatch(r'/api/(collections|playlists)(?:/([^/]+)(?:/batch/(add|remove))?)?', path or '')
            if not match:
                return False
            kind, identity, action = match.groups()
            entries = collections if kind == 'collections' else playlists
            entry = next((entry for entry in entries if entry['id'] == identity), None)
            if configuration['mode'] == 'group-forbidden' or kind == 'collections' and not self.account['permissions']['update']:
                self.respond(403, {}); return True
            if identity and entry is None:
                self.respond(404, {}); return True
            if entry and kind == 'playlists' and entry['userId'] != self.account['id']:
                self.respond(403, {}); return True
            if self.command == 'DELETE':
                if kind == 'collections' and not self.account['permissions']['delete']:
                    self.respond(403, {}); return True
                entries.remove(entry); self.respond(200, {}); return True
            key = 'books' if kind == 'collections' else 'items'
            supplied = data.get(key, [])
            references = [{'libraryItemId': value} for value in supplied] if kind == 'collections' else supplied
            for reference in references:
                if not any(item['id'] == reference.get('libraryItemId') for item in items):
                    self.respond(400, {}); return True
            def expanded(reference):
                item = next(item for item in items if item['id'] == reference['libraryItemId'])
                return item if kind == 'collections' else {'libraryItemId': item['id'], 'libraryItem': item}
            def member_id(member):
                return member['id'] if kind == 'collections' else member['libraryItemId']
            if identity is None:
                if not data.get('name') or not data.get('libraryId') or not references:
                    self.respond(400, {}); return True
                entry = {'id': kind[:-1] + '-created-' + str(len(entries)), 'libraryId': data['libraryId'], 'name': data['name'], 'description': data.get('description'), key: [expanded(value) for value in references]}
                if kind == 'playlists': entry['userId'] = self.account['id']
                entries.append(entry)
            elif action == 'add':
                for reference in references:
                    if not any(member_id(member) == reference['libraryItemId'] for member in entry[key]):
                        entry[key].append(expanded(reference))
            elif action == 'remove':
                removed = {reference['libraryItemId'] for reference in references}
                entry[key] = [member for member in entry[key] if member_id(member) not in removed]
                if kind == 'playlists' and not entry[key]: entries.remove(entry)
            else:
                if configuration['mode'] == 'group-partial-failure' and not configuration['failed']:
                    configuration['failed'] = True; self.respond(503, {}); return True
                for field in ['name', 'description']:
                    if field in data: entry[field] = data[field]
                if references:
                    ordered = [reference['libraryItemId'] for reference in references]
                    if set(ordered) != {member_id(member) for member in entry[key]}:
                        self.respond(400, {}); return True
                    entry[key].sort(key=lambda member: ordered.index(member_id(member)))
            self.respond(200, entry)
            return True

        def do_GET(self):
            path, query = self.route()
            if path == '/__fixture__/realtime-events':
                events = []
                for download in pending_feed_downloads:
                    if (configuration['mode'] in ('podcast-download-failure', 'podcast-held-download-failure') or configuration['mode'] == 'podcast-retry-delayed-failure' and download['id'] == 'download-1') and time.monotonic() >= download['readyAt'] and (not download.get('emitted') or configuration['mode'] == 'podcast-retry-delayed-failure' and len(pending_feed_downloads) > 1 and not download.get('duplicateEmitted')):
                        if download.get('emitted'): download['duplicateEmitted'] = True
                        download['emitted'] = True
                        events.append({'name': 'episode_download_finished', 'data': {'id': download['id'], 'libraryItemId': 'podcast', 'libraryId': 'podcasts', 'url': download['episode']['enclosure']['url'], 'episodeDisplayTitle': download['episode']['title'], 'isFinished': True, 'failed': True}})
                return self.respond(200, events)
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
                return self.respond(200, {'reports': reports, 'requests': requests, 'loginOutcomes': login_outcomes, 'localSessions': list(local_sessions.values()), 'readingProgress': [entry for entry in progress.values() if entry.get('ebookLocation') is not None], 'collections': collections, 'playlists': playlists, 'realtimeAuthentications': realtime_authentications})
            if not self.authorized():
                return self.respond(401, {'error': 'Unauthorized'})
            if configuration['mode'] == 'offline-library' and path and path.startswith('/api/'):
                return self.respond(503, {})
            if path == '/api/libraries':
                return self.respond(200, {'libraries': [{'id': 'books', 'name': 'Audiobooks', 'mediaType': 'book'}, {'id': 'podcasts', 'name': 'Podcasts', 'mediaType': 'podcast', 'folders': [{'id': 'podcast-folder', 'fullPath': '/fixtures/podcasts'}]}]})
            if path == '/api/libraries/books/collections':
                return self.respond(200, {'results': collections, 'total': len(collections)})
            playlist_library = re.fullmatch(r'/api/libraries/(books|podcasts)/playlists', path or '')
            if playlist_library:
                visible = [entry for entry in playlists if entry['userId'] == self.account['id'] and entry['libraryId'] == playlist_library[1]]
                return self.respond(200, {'results': visible, 'total': len(visible)})
            group = re.fullmatch(r'/api/(collections|playlists)/([^/]+)', path or '')
            if group:
                entries = collections if group[1] == 'collections' else playlists
                entry = next((entry for entry in entries if entry['id'] == group[2]), None)
                if entry is None:
                    return self.respond(404, {})
                if group[1] == 'playlists' and entry['userId'] != self.account['id']:
                    return self.respond(403, {})
                return self.respond(200, entry)
            if path == '/api/me/listening-stats':
                return self.respond(200, {'totalTime': 3660, 'days': {'2026-09-28': 1200, '2026-09-29': 1260, '2026-09-30': 1200}, 'dayOfWeek': {'Monday': 1200, 'Tuesday': 1260, 'Wednesday': 1200}, 'recentSessions': [{'id': 'stats-session', 'libraryItemId': 'book-2', 'mediaMetadata': {'title': 'Stories for Tomorrow 03', 'authorName': 'Mira Vale'}, 'timeListening': '1200', 'updatedAt': 1790784000000}]})
            annual = re.fullmatch(r'/api/me/stats/year/(\d{4})', path)
            if annual:
                current = int(annual[1]) == time.localtime().tm_year
                return self.respond(200, {'totalListeningSessions': 12 if current else 6, 'totalListeningTime': 7200 if current else 3600, 'totalBookListeningTime': 6000 if current else 3000, 'totalPodcastListeningTime': 1200 if current else 600, 'numBooksFinished': 5 if current else 2, 'numBooksListened': 9 if current else 4, 'topAuthors': [{'name': 'Mira Vale', 'time': 4000}], 'topGenres': [{'genre': 'Stories', 'time': 6000}], 'mostListenedNarrator': {'name': 'QA Narrator', 'time': 5000}, 'mostListenedMonth': {'month': 8, 'time': 4000}, 'longestAudiobookFinished': {'title': 'Stories for Tomorrow 03', 'duration': 36000}, 'booksWithCovers': ['book-2'], 'finishedBooksWithCovers': ['book-0']})
            if path == '/api/libraries/podcasts/items':
                if created_podcasts:
                    time.sleep(2)
                return self.respond(200, {'results': [podcast] + created_podcasts, 'total': 1 + len(created_podcasts)})
            if path == '/api/libraries/podcasts/personalized':
                return self.respond(200, [])
            if path == '/api/libraries/podcasts/search':
                episode = podcast['media']['episodes'][0]
                matches = [{'libraryItem': {**podcast, 'recentEpisode': episode}}] if query.get('q', [''])[0].lower() in episode['title'].lower() else []
                return self.respond(200, {'podcast': [], 'episodes': matches, 'tags': []})
            if path == '/api/libraries/books/items':
                page = max(0, int(query.get('page', ['0'])[0])); limit = min(100, max(1, int(query.get('limit', ['60'])[0])))
                mode = configuration['mode']
                if mode == 'empty':
                    return self.respond(200, {'results': [], 'total': 0})
                if not configuration['failed'] and (mode == 'catalog-error' or mode == 'page-error' and page == 1):
                    configuration['failed'] = True
                    return self.respond(503, {'error': 'Synthetic temporary failure'})
                filtered = list(items)
                selected_filter = query.get('filter', [''])[0]
                if selected_filter.startswith('genres.'):
                    genre = base64.b64decode(selected_filter.split('.', 1)[1]).decode()
                    filtered = [entry for entry in filtered if genre in entry['media']['metadata']['genres']]
                if selected_filter.startswith('progress.'):
                    value = base64.b64decode(selected_filter.split('.', 1)[1]).decode()
                    def matches(entry):
                        state = self.progress.get((entry['id'], None), {})
                        finished = bool(state.get('isFinished'))
                        started = state.get('currentTime', 0) > 0 or state.get('ebookProgress', 0) > 0
                        return finished if value == 'finished' else not finished if value == 'not-finished' else started and not finished if value == 'in-progress' else not started and not finished
                    filtered = [entry for entry in filtered if matches(entry)]
                if query.get('desc') == ['1']:
                    filtered.reverse()
                return self.respond(200, {'items' if scenario == 'library-schema-change' else 'results': filtered[page * limit:(page + 1) * limit], 'total': len(filtered), 'limit': limit, 'page': page})
            if path == '/api/libraries/books/filterdata':
                return self.respond(200, {'genres': ['Fiction', 'Mystery'], 'authors': [{'id': 'author', 'name': 'Audiobookshelf QA'}], 'series': [], 'tags': [], 'narrators': ['QA Narrator'], 'languages': []})
            if path == '/api/libraries/books/search':
                query_text = query.get('q', [''])[0].lower()
                limit = min(500, max(1, int(query.get('limit', ['12'])[0])))
                matches = [entry for entry in items if query_text in entry['media']['metadata']['title'].lower()]
                authors = [{'id': 'author', 'name': 'Audiobookshelf QA'}] if query_text in 'audiobookshelf qa' else []
                return self.respond(200, {'book': [{'libraryItem': entry} for entry in matches[:limit]], 'authors': authors, 'series': [], 'narrators': [], 'tags': []})
            if path == '/api/libraries/books/personalized':
                if configuration['mode'] == 'empty':
                    return self.respond(200, [])
                return self.respond(200, [{'id': 'continue-listening', 'label': 'Continue Listening', 'type': 'book', 'entities': [items[int(key[0].removeprefix('book-'))] for key, value in self.progress.items() if key[0].startswith('book-') and value.get('currentTime', 0) > 0 and not value.get('isFinished')], 'total': len(self.progress)}, {'id': 'recently-added', 'label': 'Recently Added', 'type': 'book', 'entities': items[:10], 'total': 61}])
            if path == '/api/me':
                return self.respond(200, {**self.account, 'permissions': {'download': False, 'update': False, 'delete': False, 'upload': False}} if configuration['mode'] == 'edge-metadata' else self.account)
            if path == '/api/items/podcast':
                if configuration['mode'] == 'podcast-slow-detail':
                    time.sleep(5)
                for download in list(pending_feed_downloads):
                    if (configuration['mode'] not in ('podcast-download-failure', 'podcast-held-download-failure', 'podcast-retry-delayed-failure') or configuration['mode'] == 'podcast-retry-delayed-failure' and download['id'] != 'download-1') and time.monotonic() >= download['readyAt']:
                        podcast['media']['episodes'].append(download['episode'])
                        pending_feed_downloads.remove(download)
                return self.respond(200, podcast)
            if path == '/api/podcasts/podcast/downloads':
                return self.respond(200, {'downloads': []})
            if path == '/api/search/podcast':
                return self.respond(200, [{'id': 42, 'title': 'New Voices Discovery', 'artistName': 'Fixture Studio', 'feedUrl': 'http://127.0.0.1:19765/feed.xml', 'genres': ['Stories']}])
            downloaded_file = re.fullmatch(r'/api/items/book-[0-9]+/file/([01]|pdf|epub)/download', path or '')
            if re.fullmatch(r'/api/items/podcast/file/(episode|episode-morning)/download', path or ''):
                return self.respond(200, audio(20), 'audio/wav')
            if path in ('/api/items/book-0/file/notes', '/api/items/book-0/file/notes/download'):
                return self.respond(200, pdf(pages=2, title='Listening notes'), 'application/pdf')
            if path == '/api/items/book-0/file/epub' or downloaded_file and downloaded_file[1] == 'epub':
                return self.respond(200, document, 'application/epub+zip')
            if path == '/api/items/book-0/file/pdf' or downloaded_file and downloaded_file[1] == 'pdf':
                return self.respond(200, document, 'application/pdf')
            if downloaded_file:
                if configuration['mode'] == 'download-error-page':
                    return self.respond(200, {'error': 'Synthetic proxy error page'})
                return self.respond(200, tracks[int(downloaded_file[1])], 'audio/wav')
            if path and path.startswith('/api/items/book-') and not path.endswith('/cover'):
                try:
                    return self.respond(200, items[int(path.rsplit('-', 1)[1])])
                except (ValueError, IndexError):
                    return self.respond(404, {})
            if path and path.endswith('/cover'):
                if configuration['mode'] == 'large-cover-art':
                    if directory := os.environ.get('ABS_QA_COVER_DIRECTORY'):
                        index = 0 if path.endswith('book-0/cover') else 1
                        return self.respond(200, (Path(directory) / f'{index}.jpg').read_bytes(), 'image/jpeg')
                    width, height = (1800, 1800) if path.endswith('book-0/cover') else (1200, 1800)
                    def chunk(kind, data):
                        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
                    pixels = b''.join(b'\x00' + bytes((25, 90 + y % 100, 160)) * width for y in range(height))
                    image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
                    return self.respond(200, image, 'image/png')
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
            nonlocal document
            path, _ = self.route()
            try:
                data = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
            except (ValueError, TypeError):
                return self.respond(400, {})
            if path == '/__fixture__/finish-downloads':
                for download in pending_feed_downloads:
                    download['readyAt'] = time.monotonic()
                return self.respond(200, {})
            if path == '/__fixture__/realtime-auth':
                token = data.get('token')
                if token not in ('fresh', 'fresh-other'):
                    return self.respond(401, {})
                identity = other_user['id'] if token == 'fresh-other' else user['id']
                realtime_authentications.append(identity)
                return self.respond(200, {'userId': identity})
            if path == '/__fixture__/configure':
                mode = data.get('mode')
                if mode not in ('baseline', 'empty', 'catalog-error', 'page-error', 'edge-metadata', 'slow-audio', 'slow-session', 'slow-close', 'broken-audio', 'no-audio', 'offline-progress', 'lost-ack', 'newer-remote', 'openid', 'openid-invalid-state', 'openid-invalid-provider-state', 'podcast-admin', 'podcast-slow-detail', 'offline-library', 'remote-rewind', 'download-error-page', 'pdf-reader', 'pdf-remote', 'pdf-rotated', 'pdf-invalid', 'pdf-long', 'pdf-audio', 'pdf-delayed', 'pdf-lost-ack', 'pdf-double-failure', 'pdf-supplementary', 'epub-reader', 'epub-invalid', 'epub-long', 'epub-styled', 'epub-zero-percentage', 'group-forbidden', 'group-partial-failure', 'group-remote-finish', 'podcast-download-failure', 'podcast-held-download-failure', 'podcast-retry-delayed-failure', 'large-cover-art'):
                    return self.respond(400, {})
                configuration.update(mode=mode, failed=False, reading_attempts=0, reading_rejected=False)
                if mode in ('pdf-reader', 'pdf-remote', 'pdf-rotated', 'pdf-invalid', 'pdf-long', 'pdf-audio', 'pdf-delayed', 'pdf-lost-ack', 'pdf-double-failure', 'pdf-supplementary'):
                    document = b'not a PDF' if mode == 'pdf-invalid' else pdf(pages=120 if mode == 'pdf-long' else 4, rotation=90 if mode == 'pdf-rotated' else 0)
                    items[0]['media']['ebookFile'] = {'ino': 'pdf', 'ebookFormat': 'pdf', 'metadata': {'filename': 'stories.pdf', 'ext': '.pdf', 'size': len(document)}}
                    if mode in ('pdf-reader', 'pdf-invalid', 'pdf-long', 'pdf-audio', 'pdf-rotated', 'pdf-delayed', 'pdf-lost-ack', 'pdf-double-failure'):
                        for account in users.values():
                            for entry in progress_by_user[account['id']].values():
                                entry.pop('ebookLocation', None); entry.pop('ebookProgress', None)
                            duration = 60 if mode == 'pdf-audio' else 20
                            progress_by_user[account['id']][('book-0', None)].update(currentTime=6, duration=duration, progress=6 / duration, isFinished=False, lastUpdate=0)
                elif mode in ('epub-reader', 'epub-invalid', 'epub-long', 'epub-styled', 'epub-zero-percentage'):
                    document = b'PKinvalid archive' if mode == 'epub-invalid' else epub(long=mode == 'epub-long', styled=mode == 'epub-styled')
                    items[0]['media']['ebookFile'] = {'ino': 'epub', 'ebookFormat': 'epub', 'metadata': {'filename': 'stories.epub', 'ext': '.epub', 'size': len(document)}}
                    for account in users.values():
                        for entry in progress_by_user[account['id']].values():
                            if mode == 'epub-zero-percentage':
                                entry['ebookProgress'] = 0
                            else:
                                entry.pop('ebookLocation', None); entry.pop('ebookProgress', None)
                            entry['lastUpdate'] = 0
                elif mode != 'offline-library':
                    items[0]['media'].pop('ebookFile', None)
                if mode == 'pdf-supplementary':
                    items[0]['libraryFiles'] = [{'ino': 'notes', 'fileType': 'ebook', 'isSupplementary': True, 'metadata': {'filename': 'Listening notes.pdf', 'ext': '.pdf'}}]
                elif mode != 'offline-library':
                    items[0].pop('libraryFiles', None)
                if mode != 'offline-library':
                    tracks[1] = audio(52 if mode == 'pdf-audio' else 12)
                    items[0]['media']['tracks'][1]['duration'] = 52 if mode == 'pdf-audio' else 12
                user['type'] = 'admin' if mode in ('podcast-admin', 'podcast-download-failure', 'podcast-held-download-failure', 'podcast-retry-delayed-failure') else 'user'
                created_podcasts.clear()
                pending_feed_downloads.clear()
                podcast['media']['metadata']['feedUrl'] = 'http://127.0.0.1/feed.xml'
                podcast['media']['episodes'] = [episode for episode in podcast['media']['episodes'] if episode['id'] != 'episode-new']
                items[0]['media']['metadata']['title'] = 'A Very Long Story Title About Finding Your Way Home Through A City Of Unexpected Doors And Forgotten Libraries' if mode == 'edge-metadata' else 'Stories for Tomorrow 01'
                for item in items[:2]: item['media']['metadata']['authorName'] = 'Audiobookshelf QA'
                items[1]['media']['metadata']['title'] = 'Stories for Tomorrow 02'
                if mode == 'large-cover-art':
                    items[0]['media']['metadata']['title'] = 'Tomorrow'
                    items[1]['media']['metadata'].update(title='A Longer Story About Finding Your Way Home', authorName='A narrator and author with a longer name')
                if mode == 'large-cover-art' and (directory := os.environ.get('ABS_QA_COVER_DIRECTORY')):
                    for item, display in zip(items, json.loads((Path(directory) / 'display.json').read_text())):
                        item['media']['metadata'].update(title=display['title'], authorName=display['author'])
                items[0]['media']['duration'] = 1e30 if mode == 'edge-metadata' else 60 if mode == 'pdf-audio' else 20
                if mode in ('baseline', 'slow-audio', 'slow-session', 'slow-close', 'broken-audio', 'no-audio', 'offline-progress'):
                    reports.clear()
                    local_sessions.clear()
                    for account in users.values():
                        for key in list(progress_by_user[account['id']]):
                            if key[0] == 'podcast':
                                del progress_by_user[account['id']][key]
                        account['bookmarks'] = []
                        if mode == 'baseline':
                            progress_by_user[account['id']].pop(('book-2', None), None)
                            for entry in progress_by_user[account['id']].values():
                                entry.pop('ebookLocation', None); entry.pop('ebookProgress', None)
                        position = 6 if account['username'] == 'qa' else 2
                        progress_by_user[account['id']][('book-0', None)].update(currentTime=position, duration=20, progress=position / 20, isFinished=False, lastUpdate=0)
                        account['mediaProgress'] = list(progress_by_user[account['id']].values())
                if mode == 'group-remote-finish':
                    progress[('book-2', None)] = {'libraryItemId': 'book-2', 'episodeId': None, 'currentTime': 20, 'duration': 20, 'progress': 1, 'isFinished': True, 'lastUpdate': time.time() * 1000}
                    user['mediaProgress'] = list(progress.values())
                if mode == 'pdf-remote':
                    progress[('book-0', None)].update(ebookLocation='4', ebookProgress=0.75, lastUpdate=time.time() * 1000)
                    user['mediaProgress'] = list(progress.values())
                if mode == 'remote-rewind':
                    progress[('book-0', None)].update(currentTime=2, duration=20, progress=0.1, isFinished=False, lastUpdate=time.time() * 1000)
                    user['mediaProgress'] = list(progress.values())
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
            if configuration['mode'] == 'offline-library' and path and path.startswith('/api/'):
                return self.respond(503, {})
            if self.mutate_group(path, data):
                return
            if path == '/api/podcasts/feed':
                if self.account['type'] not in ('root', 'admin'):
                    return self.respond(403, {})
                return self.respond(200, {'podcast': {'metadata': {'title': 'New Voices', 'author': 'Fixture Studio', 'descriptionPlain': 'A local feed', 'feedUrl': data.get('rssFeed'), 'categories': ['Stories']}, 'episodes': [{'title': 'The Next Story', 'guid': 'rss-next', 'publishedAt': 3000, 'enclosure': {'url': 'http://127.0.0.1/audio-next.mp3', 'type': 'audio/mpeg', 'length': '1234'}, 'customMetadata': {'retain': True}}]}})
            if path == '/api/podcasts/podcast/download-episodes':
                if self.account['type'] not in ('root', 'admin'):
                    return self.respond(403, {})
                if not isinstance(data, list) or len(data) != 1 or data[0].get('guid') != 'rss-next' or data[0].get('customMetadata') != {'retain': True} or data[0].get('enclosure', {}).get('url') != 'http://127.0.0.1/audio-next.mp3':
                    return self.respond(400, {})
                pending_feed_downloads.append({'id': 'download-' + str(len(pending_feed_downloads) + 1), 'readyAt': time.monotonic() + (10000 if configuration['mode'] in ('podcast-held-download-failure', 'podcast-retry-delayed-failure') else 5), 'episode': {'id': 'episode-new', 'title': data[0]['title'], 'duration': 20, 'publishedAt': data[0]['publishedAt'], 'enclosure': data[0]['enclosure']}})
                return self.respond(200, {})
            if path == '/api/podcasts':
                if self.account['type'] not in ('root', 'admin'):
                    return self.respond(403, {})
                if data.get('libraryId') != 'podcasts' or data.get('folderId') != 'podcast-folder' or data.get('path') not in ('/fixtures/podcasts/New Voices', '/fixtures/podcasts/New Voices Discovery'):
                    return self.respond(400, {'error': 'Invalid folder/path'})
                value = {'id': 'podcast-new', 'mediaType': 'podcast', 'media': {**data['media'], 'episodes': []}}
                created_podcasts.append(value)
                return self.respond(200, value)
            reading = re.fullmatch(r'/api/me/progress/(book-[0-9]+)', path or '')
            if reading and self.command == 'PATCH' and isinstance(data.get('ebookLocation'), str):
                self.observed_request['ebookLocation'] = data['ebookLocation']
                configuration['reading_attempts'] = configuration.get('reading_attempts', 0) + 1
                if configuration['mode'] == 'pdf-double-failure' and data['ebookLocation'] == '3' and not configuration['reading_rejected']:
                    configuration['reading_rejected'] = True
                    self.observed_request['applied'] = False
                    return self.respond(503, {})
                older_page = data['ebookLocation'] == '2'
                lost_reading_ack = configuration['mode'] in ('pdf-lost-ack', 'pdf-double-failure') and older_page and not configuration['failed']
                if configuration['mode'] in ('pdf-delayed', 'pdf-lost-ack', 'pdf-double-failure') and older_page and not configuration['failed']:
                    configuration['failed'] = True
                    time.sleep(3)
                key = (reading[1], None)
                current = self.progress.get(key, {})
                self.progress[key] = {**current, 'libraryItemId': key[0], 'ebookLocation': data['ebookLocation'], 'ebookProgress': data.get('ebookProgress', 0), 'lastUpdate': int(time.time() * 1000)}
                self.account['mediaProgress'] = list(self.progress.values())
                return self.respond(503 if lost_reading_ack else 200, {})
            completion = re.fullmatch(r'/api/me/progress/(book-[0-9]+|podcast)(?:/(episode|episode-morning))?', path or '')
            if completion and self.command == 'PATCH':
                if not isinstance(data.get('isFinished'), bool):
                    return self.respond(400, {})
                key = (completion.group(1), completion.group(2))
                current = self.progress.get(key, {})
                finished = data['isFinished']
                self.progress[key] = {**current, 'libraryItemId': key[0], 'episodeId': key[1], 'duration': 20,
                    'currentTime': 20 if finished else 0, 'progress': 1 if finished else 0, 'isFinished': finished, 'lastUpdate': int(time.time() * 1000)}
                self.account['mediaProgress'] = list(self.progress.values())
                return self.respond(200, self.progress[key])
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
                        self.progress[key] = {**current, 'libraryItemId': key[0], 'episodeId': key[1], 'duration': duration, 'currentTime': position,
                                         'progress': min(max(position / duration, 0), 1), 'isFinished': position >= duration, 'lastUpdate': record['updatedAt']}
                    reports.append({'path': path, 'currentTime': record['currentTime'], 'timeListened': record['timeListening'], 'sessionId': record['id'], 'userId': self.account['id']})
                    results.append({'id': record['id'], 'success': True, 'progressSynced': not newer_remote})
                self.account['mediaProgress'] = list(self.progress.values())
                if configuration['mode'] == 'lost-ack' and not configuration['failed']:
                    configuration['failed'] = True
                    return self.respond(503, {})
                return self.respond(200, {'results': results})
            if path == '/api/me/item/book-0/bookmark':
                title, position = data.get('title'), data.get('time')
                if not isinstance(title, str) or not title or not isinstance(position, (int, float)):
                    return self.respond(400, {})
                existing = next((bookmark for bookmark in self.account['bookmarks'] if bookmark['libraryItemId'] == 'book-0' and bookmark['time'] == position), None)
                if self.command == 'PATCH' and existing is None:
                    return self.respond(404, {})
                if existing is not None:
                    existing['title'] = title
                    return self.respond(200, existing)
                bookmark = {'libraryItemId': 'book-0', 'time': position, 'title': title, 'createdAt': int(time.time() * 1000)}
                self.account['bookmarks'].append(bookmark)
                return self.respond(200, bookmark)
            play = re.fullmatch(r'/api/items/(book-[0-9]+|podcast)/play(?:/(episode|episode-morning))?', path or '')
            if play:
                delay_response = configuration['mode'] == 'slow-session'
                item_id, episode_id = play.groups()
                if item_id == 'podcast':
                    selected_episode = next((episode for episode in podcast['media']['episodes'] if episode['id'] == episode_id), None)
                    if selected_episode is None:
                        return self.respond(404, {})
                    title = selected_episode['title']
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
                if configuration['mode'] == 'pdf-audio':
                    result['duration'] = 60
                    result['audioTracks'][1]['duration'] = 52
                    result['chapters'] = [chapters[0], {**chapters[1], 'end': 60}]
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
                current = self.progress.get(key, {})
                self.progress[key] = {**current, 'libraryItemId': key[0], 'episodeId': key[1], **data}
                position = float(data.get('currentTime', 0))
                duration = float(data.get('duration', session['duration']))
                self.progress[key]['progress'] = min(max(position / duration, 0), 1) if duration > 0 else 0
                self.progress[key]['isFinished'] = duration > 0 and position >= duration
                self.account['mediaProgress'] = list(self.progress.values())
                reports.append({'path': path, 'userId': self.account['id'], **data})
                return self.respond(200, {})
            self.respond(404, {})

        def do_PATCH(self):
            self.do_POST()

        def do_DELETE(self):
            path, _ = self.route()
            if not self.authorized():
                return self.respond(401, {})
            bookmark = re.fullmatch(r'/api/me/item/book-0/bookmark/([0-9]+(?:\.[0-9]+)?)', path or '')
            if self.mutate_group(path, {}):
                return
            if bookmark:
                position = float(bookmark.group(1))
                existing = next((entry for entry in self.account['bookmarks'] if entry['libraryItemId'] == 'book-0' and entry['time'] == position), None)
                if existing is None:
                    return self.respond(404, {})
                self.account['bookmarks'].remove(existing)
                return self.respond(200, {})
            return self.respond(404, {})

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
