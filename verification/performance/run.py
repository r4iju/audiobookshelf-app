#!/usr/bin/env python3
"""Profile a committed app in a disposable source snapshot, never the owner's data."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['ios', 'tv'])
parser.add_argument('--source', default='HEAD')
parser.add_argument('--simulator', required=True, help='An already leased pooled simulator UDID')
parser.add_argument('--output', required=True, type=Path, help='New private output directory')
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(mode=0o700, parents=True, exist_ok=False)
sha = subprocess.check_output(['git', 'rev-parse', args.source + '^{commit}'], cwd=ROOT, text=True).strip()
(output / 'SOURCE_SHA').write_text(sha + '\n')
archive = output / 'source.tar'
with archive.open('wb') as stream:
    subprocess.run(['git', 'archive', sha], cwd=ROOT, stdout=stream, check=True)
source = output / 'source'
source.mkdir()
with tarfile.open(archive) as stream:
    stream.extractall(source, filter='data')
for original, target in [('PerformanceProbe.swift', 'apple/Presentation/PerformanceProbe.swift'),
                         ('iOSPerformanceJourney.swift', 'apple/UITests/PerformanceJourney.swift'),
                         ('TVPerformanceJourney.swift', 'tvos/UITests/PerformanceJourney.swift')]:
    shutil.copyfile(HERE / 'overlay' / original, source / target)
for target in ['apple/App/AudiobookshelfNativeApp.swift', 'tvos/App/AudiobookshelfTVApp.swift']:
    path = source / target
    text = path.read_text()
    anchor = 'NativeStrings.installCoreText()'
    assert text.count(anchor) == 1
    path.write_text(text.replace(anchor, anchor + '\n        #if DEBUG\n        PerformanceProbe.install()\n        #endif'))
deps = ROOT / 'verification/realtime/node_modules'
if not (deps / 'socket.io').exists():
    raise SystemExit('Install the committed realtime fixture dependencies with npm ci --prefix verification/realtime.')
(source / 'verification/realtime/node_modules').symlink_to(deps, target_is_directory=True)
covers = output / 'covers'
subprocess.run(['swift', str(HERE / 'generate-covers.swift'), str(covers)], check=True)
env = dict(os.environ, ABS_QA_COVER_DIRECTORY=str(covers))
result = output / 'run.xcresult'
if args.platform == 'ios':
    env.update(ABS_QA_SIMULATOR=args.simulator, ABS_QA_DERIVED_DATA=str(output / 'build'))
    command = ['apple/scripts/verify-ui.sh', '-configuration', 'Debug', 'SWIFT_OPTIMIZATION_LEVEL=-O',
               '-only-testing:NativeJourneyTests/PerformanceJourney', '-resultBundlePath', str(result)]
    bundle = 'com.forkzed.audiobookshelf.native.preview'
else:
    env.update(ABS_TV_QA_SIMULATOR=args.simulator, ABS_TV_DERIVED_DATA=str(output / 'build'), ABS_TV_RESULT_BUNDLE=str(result))
    command = ['tvos/scripts/verify-ui.sh', 'SWIFT_OPTIMIZATION_LEVEL=-O', '-only-testing:TVJourneyTests/PerformanceJourney']
    bundle = 'com.forkzed.audiobookshelf.tv'
with (output / 'run.log').open('w') as log:
    subprocess.run(command, cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.simulator, bundle, 'data'], text=True).strip())
shutil.copyfile(container / 'tmp/loft-performance.json', output / 'frames.json')
frames = json.loads((output / 'frames.json').read_text())
if args.platform == 'ios' and (frames['scroll_steps'] != 16 or frames['scroll_distance'] < 1000):
    raise SystemExit('The native scrolling driver did not complete the workload.')
subprocess.run(['xcrun', 'xcresulttool', 'export', 'metrics', '--path', str(result), '--output-path', str(output / 'metrics')], check=True)
print(json.dumps({'source': sha, 'frames': frames, 'result': str(result)}, indent=2))
