"""Owned synthetic catalog capture states; no app/backend source edits."""
import sys, time
from pathlib import Path
from urllib.parse import urlparse
sys.path.insert(0, str(Path.cwd()))
from tvos.scripts.related_fixture import make_related_server
server, prefix = make_related_server(25769)
base = server.RequestHandlerClass
class CaptureHandler(base):
    def respond(self, status, value, kind="application/json", headers=None):
        # The stock robustness fixture deliberately uses duration=1e30. The
        # long-title visual case needs valid audio duration, not that sentinel.
        def valid_metadata(node):
            if isinstance(node, dict): return {key: (20 if key == "duration" and isinstance(item, (int, float)) and item > 1e20 else valid_metadata(item)) for key, item in node.items()}
            if isinstance(node, list): return [valid_metadata(item) for item in node]
            return node
        mode = Path("/tmp/native234-capture-state").read_text().strip() if Path("/tmp/native234-capture-state").exists() else "normal"
        if mode == "valid-long-metadata" and kind == "application/json": value = valid_metadata(value)
        return super().respond(status, value, kind, headers)
    def do_GET(self):
        mode = Path("/tmp/native234-capture-state").read_text().strip() if Path("/tmp/native234-capture-state").exists() else "normal"
        path = urlparse(self.path).path
        if not self.headers.get("X-Related-Loopback"):
            if mode == "loading" and path == prefix + "/api/libraries/books/items": time.sleep(8)
            if mode == "search-failure" and path.endswith("/search"):
                return self.respond(503, {"error": "Synthetic search failure"})
        return super().do_GET()
server.RequestHandlerClass = CaptureHandler
print("http://127.0.0.1:25769/abs", flush=True)
try: server.serve_forever()
finally: server.server_close()
