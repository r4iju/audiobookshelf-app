"""Synthetic Audiobookshelf 2.30 progress reset routes on top of verification/fixture.py.

Shapes follow the 2.30 server source (MeController):
- GET /api/me/progress/:libraryItemId/:episodeId? returns the user's MediaProgress with its row id, or 404 when there is none.
- DELETE /api/me/progress/:id removes the row by its id and answers 200, also for an unknown id.
- POST /api/items/:id/play[/:episodeId] starts at 0 when the user has no progress row, as the server does.
Progress belongs to the synthetic qa user only. Rows live in the fixture's memory.
"""
import argparse
import json
import re
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verification.fixture import make_server  # noqa: E402

SEEDED = [('book-0', None), ('book-1', None), ('podcast', 'episode'), ('podcast', 'episode-morning')]


def make_progress_reset_server(port, prefix='/abs', bind='127.0.0.1'):
    server, prefix = make_server(port, prefix, bind=bind)
    base = server.RequestHandlerClass
    state = {'fail': None, 'requests': [], 'deleted': [], 'sessions': []}

    class ProgressResetHandler(base):
        def seed(self, fail):
            self.progress.clear()
            now = int(time.time() * 1000)
            for item_id, episode_id in SEEDED:
                self.progress[(item_id, episode_id)] = {
                    'id': str(uuid.uuid4()), 'userId': self.account['id'], 'libraryItemId': item_id, 'episodeId': episode_id,
                    'mediaItemType': 'podcastEpisode' if episode_id else 'book', 'duration': 20, 'currentTime': 6, 'progress': 0.3,
                    'isFinished': False, 'hideFromContinueListening': False, 'ebookLocation': None, 'ebookProgress': 0,
                    'lastUpdate': now, 'startedAt': now, 'finishedAt': None}
            self.account['mediaProgress'] = list(self.progress.values())
            state.update(fail=fail, requests=[], deleted=[], sessions=[])

        def body(self):
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length) if length else b''
            try:
                return json.loads(raw) if raw else {}
            except ValueError:
                return {}

        def local_path(self):
            path = urlparse(self.path).path
            return path[len(prefix):] if path.startswith(prefix + '/') else None

        def respond(self, status, value, kind='application/json', headers=None):
            if getattr(self, 'starts_without_row', False) and status == 200 and isinstance(value, dict) and 'audioTracks' in value:
                value = {**value, 'currentTime': 0}
            if getattr(self, 'observes_session', False) and status == 200 and isinstance(value, dict) and 'audioTracks' in value:
                state['sessions'].append({'libraryItemId': value['libraryItemId'], 'episodeId': value['episodeId'], 'currentTime': value['currentTime']})
            super().respond(status, value, kind, headers)

        def do_GET(self):
            path = self.local_path()
            if path and re.fullmatch(r'/api/items/[^/]+', path):
                state['requests'].append({'method': 'GET', 'path': path})
            if path == '/__reset__/observations':
                progress = [{key: entry.get(key) for key in ('id', 'libraryItemId', 'episodeId', 'currentTime', 'progress')}
                            for entry in self.progress.values()]
                return self.respond(200, {'requests': state['requests'], 'deleted': state['deleted'], 'progress': progress, 'sessions': state['sessions']})
            lookup = re.fullmatch(r'/api/me/progress/([^/]+)(?:/([^/]+))?', path or '')
            if lookup:
                state['requests'].append({'method': 'GET', 'path': path})
                if not self.authorized():
                    return self.respond(401, {})
                entry = self.progress.get((lookup.group(1), lookup.group(2)))
                return self.respond(200, entry) if entry else self.respond(404, {})
            super().do_GET()

        def do_POST(self):
            path = self.local_path()
            if path == '/__reset__/configure':
                options = self.body()
                self.seed(options.get('fail'))
                return self.respond(200, {})
            play = re.fullmatch(r'/api/items/([^/]+)/play(?:/([^/]+))?', path or '')
            if play and self.authorized():
                state['requests'].append({'method': 'POST', 'path': path})
                self.observes_session = True
                self.starts_without_row = (play.group(1), play.group(2)) not in self.progress
            super().do_POST()

        def do_DELETE(self):
            path = self.local_path()
            removal = re.fullmatch(r'/api/me/progress/([^/]+)', path or '')
            if not removal:
                return super().do_DELETE()
            state['requests'].append({'method': 'DELETE', 'path': path})
            if not self.authorized():
                return self.respond(401, {})
            if state['fail'] == 'delete':
                state['fail'] = None
                return self.respond(500, {})
            key = next((key for key, entry in self.progress.items() if entry.get('id') == removal.group(1)), None)
            if key is not None:
                del self.progress[key]
                self.account['mediaProgress'] = list(self.progress.values())
                state['deleted'].append({'id': removal.group(1), 'libraryItemId': key[0], 'episodeId': key[1]})
            self.respond(200, {})

    server.RequestHandlerClass = ProgressResetHandler
    return server, prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--prefix', default='/abs')
    args = parser.parse_args()
    server, prefix = make_progress_reset_server(args.port, args.prefix)
    print(f'http://127.0.0.1:{server.server_port}{prefix}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
