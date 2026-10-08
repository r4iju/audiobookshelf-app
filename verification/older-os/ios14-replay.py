#!/usr/bin/env python3
"""Runs only after the exact stock runtime capability probe succeeded."""
import hashlib
import json
import os
from pathlib import Path
import re
from ci_support import Evidence

os.environ['DEVELOPER_DIR'] = '/Applications/Xcode_16.2.app/Contents/Developer'
os.environ['PATH'] = str(Path(__file__).resolve().parent) + ':' + os.environ['PATH']
e = Evidence('ios14-replay')
e.source(expected_xcode="16.2", expected_swift="6.0")
import importlib.util
spec = importlib.util.spec_from_file_location("capture_suppression", Path(__file__).with_name("suppress-captures.py"))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
module.suppress(Path.cwd(), e.root)
capability = Path(os.environ['RUNNER_TEMP']) / 'ios145-capability'
if not (capability / 'boot-confirmed.json').is_file():
    raise RuntimeError('Stock runtime boot capability did not succeed; do not claim app execution')
_, sdk = e.run('sdk', ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'])
if sdk.strip() != '18.2':
    raise RuntimeError('Expected actual selected SDK18.2, no substituted SDK')
e.run('xcodegen', ['xcodegen', '--version'])
e.run('node', ['node', '--version'])
_, raw = e.run('runtimes-before', ['xcrun', 'simctl', 'list', 'runtimes', '-j'])
runtime = next((r for r in json.loads(raw)['runtimes'] if r.get('version') == '14.5' and r.get('buildversion') == '18E182' and r.get('isAvailable')), None)
if runtime is None:
    raise RuntimeError('Exact available iOS14.5/18E182 missing')
(e.root / 'selected-runtime.json').write_text(json.dumps(runtime, indent=2))
# An explicit equivalent of the existing fixture harness: tests remain untouched.
# Rebase this audited copy if239 changes the source harness's selected-toolchain contract.
harness_path = Path('apple/scripts/verify-ui.sh')
original = harness_path.read_text()
harness = original
replacements = {
    'apple_root="$(cd "$(dirname "$0")/.." && pwd)"': 'apple_root=' + __import__('shlex').quote(str(Path('apple').resolve())),
    'IPHONEOS_DEPLOYMENT_TARGET=15.0': 'IPHONEOS_DEPLOYMENT_TARGET=14.0',
}
for before, after in replacements.items():
    if harness.count(before) != 1:
        raise RuntimeError('Harness contract changed; review mapping rather than guessing')
    harness = harness.replace(before, after)
# This optional diagnostics option is not a behavioral assertion. Keep it when the
# actual selected xcodebuild supports it; record removal when the older tool lacks it.
_, help_text = e.run('xcodebuild-help', ['xcodebuild', '-help'], required=False)
if '-collect-test-diagnostics' not in help_text:
    if harness.count('-collect-test-diagnostics never') != 1:
        raise RuntimeError('Optional diagnostics argument mapping changed')
    harness = harness.replace('-collect-test-diagnostics never', '')
    (e.root / 'harness-diagnostics.txt').write_text('Selected toolchain does not advertise collect-test-diagnostics. Removed optional diagnostics collection flag only.')
copy = e.root / 'fixture-harness.sh'
copy.write_text(harness)
(e.root / 'harness-provenance.json').write_text(json.dumps({'source': str(harness_path), 'sourceSHA256': hashlib.sha256(original.encode()).hexdigest(), 'executedSHA256': hashlib.sha256(harness.encode()).hexdigest(), 'minimumOverride': '14.0'}, indent=2))
_, raw = e.run('pool-acquire', ['sim', 'acquire', 'iphone', '--os', '14.5', '--no-boot', '--for', '239 source-pinned iOS14 fallback'])
udid = next(line for line in raw.splitlines() if re.fullmatch(r'[0-9A-Fa-f-]{36}', line))
os.environ['ABS_QA_SIMULATOR'] = udid
os.environ['ABS_QA_DERIVED_DATA'] = str(e.root / 'build')
result = e.root / 'iOS14.xcresult'
errors = []
try:
    e.run('boot', ['xcrun', 'simctl', 'bootstatus', udid, '-b'], seconds=180)
    _, actual = e.run('actual-device', ['xcrun', 'simctl', 'list', 'devices', '-j'])
    if not any(d['udid'] == udid and d['state'] == 'Booted' for d in json.loads(actual)['devices'].get(runtime['identifier'], [])):
        raise RuntimeError('Lease did not boot under exact selected runtime')
    e.run('representative-journeys', ['bash', str(copy), 'CODE_SIGNING_ALLOWED=NO', '-resultBundlePath', str(result),
        '-only-testing:NativeJourneyTests/ConnectionJourney/testConnectSelectLibraryAndRestoreAccountAfterRelaunch',
        '-only-testing:NativeJourneyTests/ShellJourney/testDestinationsKeepLibrarySelectionAndDetailsWhileBrowsing',
        '-only-testing:NativeJourneyTests/SearchJourney/testSearchFindsBookBeyondFirstPageAndReturnsFromDetails',
        '-only-testing:NativeJourneyTests/PlaybackJourney/testRealAudioCrossesFilesAndContinuesAfterLeavingDetails',
        '-only-testing:NativeJourneyTests/OfflineJourney/testDownloadedBookPlaysAcrossFilesOfflineAfterRelaunchAndSynchronizesOnReconnect',
        '-only-testing:NativeJourneyTests/ReaderJourney/testPDFPageRotationAndPositionSurviveDownloadedOfflineRelaunch'], seconds=1500)
except Exception as error:
    errors.append(str(error))
finally:
    code, _ = e.run('pool-release', ['sim', 'release', udid], required=False)
    if code:
        errors.append('Lease release failed')
for action in [lambda: e.app(e.root / 'build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app', 'com.forkzed.audiobookshelf.native.preview', '14.0'), lambda: e.results(result)]:
    try:
        action()
    except Exception as error:
        errors.append(str(error))
e.failures(errors)
