"""Owned TV capture-only text/state overrides. Never used by behavioral verification."""
import json, sys, time
from pathlib import Path
from urllib.parse import urlparse
sys.path.insert(0, str(Path('/Users/emanuel/code/leafwake-fullstack/tvos/scripts')))
import related_fixture
LONG = '\n\n'.join(f'Paragraph {i}: This synthetic story follows a reader through unexpected doors and quiet libraries. The complete account remains available for reading with the Siri Remote, including this paragraph and the passages that follow. ' * 2 for i in range(1, 13))
server, prefix = related_fixture.make_related_server(int(sys.argv[1]) if len(sys.argv) > 1 else 33765)
Base = server.RequestHandlerClass
state = {'mode': 'baseline'}
class CaptureHandler(Base):
    def do_POST(self):
        if urlparse(self.path).path == prefix + '/__presentation__/configure':
            state['mode'] = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))) or b'{}').get('mode', 'baseline')
            return self.respond(200, {})
        return super().do_POST()
    def respond(self, status, value, kind='application/json', headers=None):
        path = urlparse(self.path).path.removeprefix(prefix)
        mode = state['mode']
        if status == 200 and kind == 'application/json' and isinstance(value, dict):
            value = json.loads(json.dumps(value))
            if mode in ('long', 'unbroken'):
                long_text = LONG if mode == 'long' else 'Continuous metadata: ' + ('W' * 1400) + '. End of the complete synthetic description.'
                if path == '/api/authors/author': value['description'] = long_text
                if path == '/api/libraries/books/series/series-saga': value['description'] = long_text
                if path.startswith('/api/items/') and 'media' in value:
                    value['media']['metadata']['description'] = long_text
                    value['media']['metadata']['title'] = 'A Long Story About Finding Your Way Home Through Unexpected Doors and Forgotten Libraries'
                    for episode in value['media'].get('episodes', []): episode['description'] = long_text
            if mode == 'empty-podcast' and path.startswith('/api/items/') and 'media' in value:
                value['media']['episodes'] = []
            if mode == 'missing-art' and 'imagePath' in value: value['imagePath'] = None
        if mode == 'missing-art' and ('/cover' in path or path.endswith('/image')):
            return super().respond(404, {}, headers={'Cache-Control': 'no-store'})
        if mode == 'detail-error' and path.startswith('/api/items/') and path.count('/') == 3:
            return super().respond(503, {'error': 'Synthetic temporary detail failure'})
        if mode == 'loading' and (path.startswith('/api/items/') or '/libraries/' in path or path.startswith('/api/authors/')):
            time.sleep(4)
        return super().respond(status, value, kind, dict(headers or {}, **{'Cache-Control': 'no-store'}))
server.RequestHandlerClass = CaptureHandler
server.serve_forever()
