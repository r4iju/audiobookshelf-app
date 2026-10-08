from pathlib import Path
import sys,time,copy
sys.path.insert(0,str(Path.cwd()))
from verification.fixture import make_server
server,state=make_server(port=25769)
handler=server.RequestHandlerClass
original=handler.respond
state_path=Path('/tmp/native236-capture-state')
def respond(self,status,value,kind='application/json',headers=None):
    path=getattr(self,'observed_request',{}).get('path') or ''
    state=state_path.read_text().strip() if state_path.exists() else ''
    if state=='slow-download' and '/api/items/book-0/file/' in path and path.endswith('/download'):
        time.sleep(20)
    if state=='partial-reader' and path=='/api/items/book-0/file/pdf/download':
        status,value,kind=503,{'error':'Synthetic ebook unavailable'},'application/json'
    if state=='feed-error' and path=='/api/podcasts/feed':
        status,value,kind=503,{'error':'Synthetic feed unavailable'},'application/json'
    if state=='reader-slow' and path in ('/api/items/book-0/file/pdf','/api/items/book-0/file/epub'):
        time.sleep(8)
    if state=='group-load-error' and path.endswith('/collections'):
        status,value,kind=503,{'error':'Synthetic groups unavailable'},'application/json'
    if path=='/api/podcasts/feed' and status==200 and isinstance(value,dict):
        value=copy.deepcopy(value)
        value['podcast']['episodes'].append({'title':'Transcript without audio','guid':'rss-no-audio','publishedAt':2000})
    return original(self,status,value,kind,headers)
handler.respond=respond
server.serve_forever()
