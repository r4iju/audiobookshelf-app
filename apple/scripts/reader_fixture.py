"""Reader expansion fixture, synthetic media only, using the retained API fixture contract."""
import argparse
import copy
import io
import json
import re
import time
from pathlib import Path
from urllib.parse import urlparse
from verification.fixture import make_server

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=19769)
parser.add_argument('--media', type=Path, required=True)
args = parser.parse_args()
server, _ = make_server(args.port, '/abs', 'baseline', 'modern')
Base = server.RequestHandlerClass
state = {'format': None, 'unknown': False, 'offline': False}

class ReaderFixture(Base):
    def do_POST(self):
        if urlparse(self.path).path == '/abs/__fixture__/configure':
            data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            mode = data.get('mode', '')
            match = re.fullmatch(r'(cbz|cbr|mobi|azw3)-reader', mode)
            state.update(format=match[1] if match else None, unknown=mode in ('epub-unknown', 'pdf-unknown'), updated=time.time() * 1000, offline=mode == 'offline-library')
            if match or mode in ('epub-unknown', 'pdf-unknown'):
                data['mode'] = 'pdf-audio' if match else 'pdf-reader' if mode == 'pdf-unknown' else 'epub-reader'
            raw = json.dumps(data).encode()
            self.rfile = io.BytesIO(raw)
            self.headers.replace_header('Content-Length', str(len(raw)))
        return super().do_POST()

    def do_GET(self):
        path = urlparse(self.path).path
        fmt = state['format']
        if fmt and path in (f'/abs/api/items/book-0/file/{fmt}', f'/abs/api/items/book-0/file/{fmt}/download', f'/abs/api/items/book-0/file/extra-{fmt}', f'/abs/api/items/book-0/file/extra-{fmt}/download'):
            if state['offline']:
                return self.respond(503, {})
            return self.respond(200, (args.media / ('stories.' + fmt)).read_bytes(), {'cbz':'application/x-cbz', 'cbr':'application/x-cbr', 'mobi':'application/x-mobipocket-ebook', 'azw3':'application/vnd.amazon.ebook'}[fmt])
        return super().do_GET()

    def respond(self, status, body, *rest):
        def expand(value):
            if isinstance(value, dict):
                value = {key: expand(child) for key, child in value.items()}
                fmt = state['format']
                if state['unknown'] and 'mediaProgress' in value:
                    value['mediaProgress'] = [{'id':'unknown-place', 'libraryItemId':'book-0', 'ebookLocation':'legacy-unknown-location', 'ebookProgress':0.4, 'lastUpdate':state['updated']}]
                if value.get('id') == 'book-0' and 'media' in value and fmt:
                    metadata = {'filename':'stories.' + fmt, 'ext':'.' + fmt, 'size':(args.media / ('stories.' + fmt)).stat().st_size}
                    value['media']['ebookFile'] = {'ino':fmt, 'ebookFormat':fmt, 'metadata':metadata}
                    value['libraryFiles'] = [{'ino':'extra-' + fmt, 'fileType':'ebook', 'metadata':metadata}]
                return value
            if isinstance(value, list):
                return [expand(child) for child in value]
            return value
        return super().respond(status, expand(body), *rest)

server.RequestHandlerClass = ReaderFixture
try:
    server.serve_forever()
finally:
    server.server_close()
