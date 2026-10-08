#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
from ci_support import Evidence

os.environ['DEVELOPER_DIR'] = '/Applications/Xcode_16.2.app/Contents/Developer'
os.environ['PATH'] = str(Path(__file__).resolve().parent) + ':' + os.environ['PATH']
e = Evidence('tv17-replay')
e.source(expected_xcode="16.2", expected_swift="6.0")
import importlib.util
spec = importlib.util.spec_from_file_location("capture_suppression", Path(__file__).with_name("suppress-captures.py"))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
module.suppress(Path.cwd(), e.root)
_, sdk = e.run('sdk', ['xcrun', '--sdk', 'appletvsimulator', '--show-sdk-version'])
if sdk.strip() != '18.2':
    raise RuntimeError('Expected actual selected SDK18.2, no substituted SDK')
e.run('xcodegen', ['xcodegen', '--version'])
e.run('openssl', ['openssl', 'version'])
_, raw = e.run('runtimes-before', ['xcrun', 'simctl', 'list', 'runtimes', '-j'])
runtime = next((r for r in json.loads(raw)['runtimes'] if r.get('version') == '17.0' and 'tvOS' in r.get('identifier', '') and r.get('isAvailable')), None)
if runtime is None:
    raise RuntimeError('Exact available tvOS17.0 missing, no newer fallback')
(e.root / 'selected-runtime.json').write_text(json.dumps(runtime, indent=2))
result = e.root / 'TV17.xcresult'
os.environ['ABS_TV_RESULT_BUNDLE'] = str(result)
# Keep the original fixture harness while adapting only optional tool diagnostics.
harness_path = Path('tvos/scripts/verify-ui.sh')
original = harness_path.read_text()
harness = original
root_line = 'tvos_root="$(cd "$(dirname "$0")/.." && pwd)"'
if harness.count(root_line) != 1:
    raise RuntimeError('Harness root contract changed; review mapping')
harness = harness.replace(root_line, 'tvos_root=' + __import__('shlex').quote(str(Path('tvos').resolve())))
_, help_text = e.run('xcodebuild-help', ['xcodebuild', '-help'], required=False)
if '-collect-test-diagnostics' not in help_text:
    if harness.count('-collect-test-diagnostics never') != 1:
        raise RuntimeError('Optional diagnostics contract changed')
    harness = harness.replace('-collect-test-diagnostics never', '')
    (e.root / 'harness-diagnostics.txt').write_text('Selected toolchain lacks collect-test-diagnostics. Removed optional diagnostics flag only.')
# The first actual17 run rejected the synthetic chain before app launch. Preserve
# system trust and record the corrected owned certificate chain on this lease.
# Certificate metadata/chain verification are diagnostics, not a trust exception.
trust_line = 'xcrun simctl keychain "$simulator" add-root-cert "$fixture_dir/ca.pem"'
if harness.count(trust_line) != 1:
    raise RuntimeError('Synthetic root-install seam changed')
trust_diagnostics = trust_line + '\n' + '\n'.join([
    'openssl x509 -in "$fixture_dir/ca.pem" -noout -text',
    'openssl x509 -in "$fixture_dir/cert.pem" -noout -text',
    'openssl verify -CAfile "$fixture_dir/ca.pem" "$fixture_dir/cert.pem"',
])
harness = harness.replace(trust_line, trust_diagnostics)
(e.root / 'trust-diagnostic-scope.txt').write_text(
    'Prior sourcef635 actual17 setup: NSURLError-1202/-9814. Actuala363 diagnosed duplicate critical CA constraints. This retry logs corrected certificate metadata, '
    'verifies the owned chain with explicit minimal CA configuration and supported root installation. '
    'Hosted17 replay remains required; no app TLS exception or trust override.\n')
copy = e.root / 'fixture-harness.sh'
copy.write_text(harness)
(e.root / 'harness-provenance.json').write_text(__import__('json').dumps({'source': str(harness_path), 'sourceSHA256': __import__('hashlib').sha256(original.encode()).hexdigest(), 'executedSHA256': __import__('hashlib').sha256(harness.encode()).hexdigest()}, indent=2))
_, raw = e.run('pool-acquire', ['sim', 'acquire', 'tv', '--os', '17.0', '--no-boot', '--for', '239 official TV17 execution'])
udid = next(line for line in raw.splitlines() if re.fullmatch(r'[0-9A-Fa-f-]{36}', line))
os.environ['ABS_TV_QA_SIMULATOR'] = udid
errors = []
try:
    e.run('boot', ['xcrun', 'simctl', 'bootstatus', udid, '-b'], seconds=180)
    _, actual = e.run('actual-device', ['xcrun', 'simctl', 'list', 'devices', '-j'])
    if not any(d['udid'] == udid and d['state'] == 'Booted' for d in json.loads(actual)['devices'].get(runtime['identifier'], [])):
        raise RuntimeError('Lease did not boot under exact selected runtime')
    e.run('representative-journeys', ['bash', str(copy),
        'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-', 'TVOS_DEPLOYMENT_TARGET=17.0',
        '-only-testing:TVJourneyTests/ShellJourney/testManyLibrariesKeepTheShellBoundedAndRemainSelectable',
        '-only-testing:TVJourneyTests/CatalogJourney/testContinueListeningOpensDetailsAndBackRestoresFocus',
        '-only-testing:TVJourneyTests/CatalogJourney/testServerSearchFindsTitlesOutsideLoadedPage',
        '-only-testing:TVJourneyTests/PlaybackJourney/testResumeShowsChapterAndTotalProgressAndRemoteToggles',
        '-only-testing:TVJourneyTests/RelatedJourney/testBookDetailsLeadToItsSeriesAndAuthor',
        '-only-testing:TVJourneyTests/ReadinessJourney/testMainScreensPassTheAccessibilityAudit',
        '-only-testing:TVJourneyTests/RecoveryJourney/testSigningInAgainShowsTheWholeFormAndSendsTheHeldListeningWithoutPlaying'], seconds=1200)
except Exception as error:
    errors.append(str(error))
finally:
    code, _ = e.run('pool-release', ['sim', 'release', udid], required=False)
    if code:
        errors.append('Lease release failed')
# Diagnostic exceptions cannot prevent lease cleanup or erase the original test failure.
for action in [lambda: e.app(Path('tvos/build/Build/Products/Debug-appletvsimulator/AudiobookshelfTV.app'), 'com.forkzed.audiobookshelf.tv', '17.0'), lambda: e.simulator_signing(Path('tvos/build/Build/Products/Debug-appletvsimulator')), lambda: e.results(result)]:
    try:
        action()
    except Exception as error:
        errors.append(str(error))
e.failures(errors)
