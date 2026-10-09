#!/usr/bin/env python3
"""Measure native focused-row continuity without images or owner media."""
import argparse,json,os,shutil,subprocess,tarfile
from pathlib import Path
root=Path(__file__).resolve().parents[2];here=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--source',default='HEAD');p.add_argument('--simulator',required=True);p.add_argument('--output',required=True,type=Path);p.add_argument('--menu',choices=['speed','sleep','settings','sort'],default='speed');a=p.parse_args()
out=a.output.resolve();out.mkdir(mode=0o700,parents=True,exist_ok=False)
sha=subprocess.check_output(['git','rev-parse',a.source+'^{commit}'],cwd=root,text=True).strip();(out/'SOURCE_SHA').write_text(sha+'\n')
with (out/'source.tar').open('wb') as f:subprocess.run(['git','archive',sha],cwd=root,stdout=f,check=True)
source=out/'source';source.mkdir()
with tarfile.open(out/'source.tar') as f:f.extractall(source,filter='data')
shutil.copyfile(here/'probe.swift',source/'apple/Presentation/MenuFocusProbe.swift');shutil.copyfile(here/'journey.swift',source/'tvos/UITests/MenuFocusJourney.swift')
app=source/'tvos/App/AudiobookshelfTVApp.swift';text=app.read_text();assert text.count('NativeStrings.installCoreText()')==1;app.write_text(text.replace('NativeStrings.installCoreText()','NativeStrings.installCoreText()\n        MenuFocusProbe.install()'))
(source/'verification/realtime/node_modules').symlink_to(root/'verification/realtime/node_modules',target_is_directory=True)
env=dict(os.environ,ABS_TV_QA_SIMULATOR=a.simulator,ABS_TV_DERIVED_DATA=str(out/'build'),ABS_TV_RESULT_BUNDLE=str(out/'run.xcresult'),TEST_RUNNER_LOFT_MENU_KIND=a.menu)
with (out/'run.log').open('w') as log:subprocess.run(['tvos/scripts/verify-ui.sh','-only-testing:TVJourneyTests/MenuFocusJourney'],cwd=source,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',a.simulator,'com.forkzed.audiobookshelf.tv','data'],text=True).strip());shutil.copyfile(container/'tmp/menu-focus.json',out/'focus.json')
records=json.loads((out/'focus.json').read_text());menu=[x for x in records if x['classes'][0]=='_UIContextMenuCell'];assert menu and menu[-1]['time']-menu[0]['time']>=19,'Menu was not held through the measurement interval'
# Exclude navigation and dismissal, leaving a stationary interval wholly inside the 20-second hold.
held=[x for x in menu if menu[-1]['time']-18<=x['time']<=menu[-1]['time']-.5];assert len(held)>=200 and held[-1]['time']-held[0]['time']>=17
replacements=sum(x['id']!=y['id'] for x,y in zip(held,held[1:]));report={'source':sha,'menu':a.menu,'seconds':held[-1]['time']-held[0]['time'],'samples':len(held),'focused_row_replacements':replacements};(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));assert replacements==0,'Stationary focused native menu row was reconstructed'
