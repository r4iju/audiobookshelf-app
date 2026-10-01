"""Android journey fixture: the shared synthetic server plus server 2.30 routes only Android journeys use.

The shared fixture belongs to the cross-platform verification suite, so Android-only routes are layered
here instead of edited into it.
"""
import argparse
import io
import json
import re
import ssl
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verification.fixture import make_server  # noqa: E402


def android_server(port, prefix, bind='127.0.0.1'):
    server, prefix = make_server(port, prefix, 'baseline', 'modern', bind)
    base = server.RequestHandlerClass
    # Listening sync can be refused on its own, whatever the shared mode, so reading and listening
    # ordering is observable with a document present. Any reconfiguration accepts listening again.
    refusal = {'listening': False}

    class AndroidHandler(base):
        def own_path(self):
            path = urlparse(self.path).path
            return path[len(prefix):] if path.startswith(prefix + '/') else None

        def identify_progress(self):
            # Server 2.30 progress records carry an id that discarding progress addresses.
            for entry in self.progress.values():
                entry.setdefault('id', 'progress-' + entry['libraryItemId'] + ('-' + entry['episodeId'] if entry.get('episodeId') else ''))

        def do_GET(self):
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
                self.rfile = io.BytesIO(body)
            super().do_PATCH()

        def do_POST(self):
            path = self.own_path()
            if path == '/__android__/refuse-listening':
                data = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
                refusal['listening'] = bool(data.get('refuse'))
                self.route()
                return self.respond(200, refusal)
            if path == '/__fixture__/configure':
                refusal['listening'] = False
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
                key = next((key for key, entry in self.progress.items() if entry['id'] == discard[1]), None)
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
