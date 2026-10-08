import pathlib,json,hashlib,subprocess,shutil,datetime,sys
mfile=pathlib.Path('/tmp/238-builds.json');m=json.loads(mfile.read_text());role=sys.argv[1];phase=sys.argv[2];p=pathlib.Path(m['products'][role]['path'])
def hashes(p):return {str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(p.rglob('*')) if f.is_file()}
f=hashes(p)
for path in [p,pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container','9ACC6F5B-180D-44C3-823B-F8796813D69D','com.forkzed.audiobookshelf.tv','app'],text=True).strip())]:
 subprocess.run(['codesign','--verify','--deep','--strict',str(path)],check=True)
 assert hashes(path)==f,str(path)
live=path;snap=pathlib.Path('/tmp/native238-installed-'+phase+'.app');shutil.copytree(live,snap,dirs_exist_ok=True)
r={'path':str(snap),'original_installed_path':str(live),'phase':phase,'time':datetime.datetime.now(datetime.timezone.utc).isoformat(),'strict_exit':0,'files_match':True,'resources':len(f)}
row=m['products'][role];old=row['files'];row.setdefault('resource_history',[]).append({'phase':phase,'previous_files_match':old==f});row['files']=f;row.setdefault('installed_checks',[]).append(r)
row.setdefault('capture_checkpoints',[]).append({'phase':phase,'time':r['time'],'test_instrumentation':{pathlib.Path(a).name:hashlib.sha256(pathlib.Path(a).read_bytes()).hexdigest() for a in ['tvos/UITests/RenderJourney.swift','tvos/UITests/LongInspectionJourney.swift','tvos/UITests/CaptureRecoveryJourney.swift'] if pathlib.Path(a).exists()}})
mfile.write_text(json.dumps(m,indent=2)+'\n');print(phase,len(f),'old hashes same',old==f)
