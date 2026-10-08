import urllib.request,json,sys,datetime
from pathlib import Path
mode=sys.argv[1];variant=sys.argv[2] if len(sys.argv)>2 else ""
r=urllib.request.Request("http://127.0.0.1:25769/abs/__fixture__/configure",data=json.dumps({"mode":mode}).encode(),headers={"Content-Type":"application/json"},method="POST")
with urllib.request.urlopen(r) as response: assert response.status==200
Path("/tmp/native236-capture-mode").write_text(mode)
Path("/tmp/native236-capture-state").write_text(variant)
with Path("/tmp/236-mode-history.jsonl").open("a") as f: f.write(json.dumps({"mode":mode,"variant":variant,"at":datetime.datetime.now(datetime.timezone.utc).isoformat()})+"\n")
print(mode,variant)
