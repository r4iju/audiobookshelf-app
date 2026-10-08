"""Owned synthetic utility presentation states. Stock data/API contract is preserved outside explicit capture states."""
from pathlib import Path
from urllib.parse import urlparse
import sys,time,copy
sys.path.insert(0,str(Path.cwd()))
from verification.fixture import make_server
server,prefix=make_server(port=35769)
base=server.RequestHandlerClass
state_path=Path('/tmp/native237-capture-state')
class CaptureHandler(base):
 def do_GET(self):
  mode=state_path.read_text().strip() if state_path.exists() else 'baseline'
  path=urlparse(self.path).path
  if mode=='loading-library' and path==prefix+'/api/libraries':
   deadline=time.monotonic()+120
   while state_path.read_text().strip()=='loading-library' and time.monotonic()<deadline:time.sleep(0.1)
  if mode=='loading-statistics' and path==prefix+'/api/me/listening-stats':time.sleep(12)
  if mode=='loading-year' and '/api/me/stats/year/' in path:time.sleep(12)
  if mode=='failure-statistics' and path==prefix+'/api/me/listening-stats':return self.respond(503,{'error':'Synthetic statistics unavailable'})
  if mode=='failure-year' and '/api/me/stats/year/' in path:return self.respond(503,{'error':'Synthetic year unavailable'})
  if mode=='admin-year' and '/api/stats/year/' in path:return self.respond(200,{'numListeningSessions':120,'numBooksAdded':24,'numAuthorsAdded':8,'numBooks':61,'totalBooksAddedDuration':72000,'totalListeningTime':144000,'booksAddedWithCovers':['book-0','book-2'],'topAuthors':[{'name':'Mira Vale','time':4000}],'topNarrators':[{'name':'QA Narrator','time':5000}],'topGenres':[{'genre':'Stories','time':6000}]})
  return super().do_GET()
 def respond(self,status,value,kind='application/json',headers=None):
  mode=state_path.read_text().strip() if state_path.exists() else 'baseline'
  path=getattr(self,'observed_request',{}).get('path','')
  if mode=='admin-year' and path=='/api/me':value={**value,'type':'admin'}
  if mode=='empty-statistics' and path=='/api/me/listening-stats':value={'totalTime':0,'days':{},'dayOfWeek':{},'recentSessions':[]}
  if mode=='empty-year' and '/api/me/stats/year/' in path:
   value={'totalListeningSessions':0,'totalListeningTime':0,'totalBookListeningTime':0,'totalPodcastListeningTime':0,'numBooksFinished':0,'numBooksListened':0,'topAuthors':[],'topGenres':[],'booksWithCovers':[],'finishedBooksWithCovers':[]}
  return super().respond(status,value,kind,headers)
server.RequestHandlerClass=CaptureHandler
try:server.serve_forever()
finally:server.server_close()
