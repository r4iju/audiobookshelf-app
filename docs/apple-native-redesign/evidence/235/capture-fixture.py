"""Owned synthetic listening capture states; no runtime/domain overrides."""
import sys
from pathlib import Path
from urllib.parse import urlparse
sys.path.insert(0,str(Path.cwd()))
from verification.fixture import make_server
server,prefix=make_server(25769)
base=server.RequestHandlerClass
class CaptureHandler(base):
 def do_GET(self):
  mode=Path('/tmp/native235-capture-state').read_text().strip() if Path('/tmp/native235-capture-state').exists() else 'normal'
  path=urlparse(self.path).path
  if mode=='bookmark-error' and path==prefix+'/api/me': return self.respond(503,{'error':'Synthetic bookmark lookup unavailable. Retry when the connection returns.'})
  if mode=='no-art' and path.endswith('/cover'): return self.respond(404,{})
  return super().do_GET()
server.RequestHandlerClass=CaptureHandler
print('http://127.0.0.1:25769/abs',flush=True)
try:server.serve_forever()
finally:server.server_close()
