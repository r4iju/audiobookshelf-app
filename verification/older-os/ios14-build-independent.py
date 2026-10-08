#!/usr/bin/env python3
"""Original-minimum binary evidence only; no runtime, device, fixture or install."""
import json
import os
from pathlib import Path
from ci_support import Evidence

os.environ['DEVELOPER_DIR'] = '/Applications/Xcode_15.0.1.app/Contents/Developer'
e = Evidence('ios14-build')
e.source()
_, sdk = e.run('sdk', ['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'])
if sdk.strip() != '17.0':
    raise RuntimeError('Expected actual selected Xcode15.0.1 SDK17.0, no substituted toolchain')
e.run('xcodegen-version', ['xcodegen', '--version'])
free = os.statvfs(e.root).f_bavail * os.statvfs(e.root).f_frsize
(e.root / 'free-bytes.txt').write_text(str(free))
if free < 4 * 1024 ** 3:
    raise RuntimeError('Less than4 GiB free for bounded isolated build; do not delete unrelated tools')
# Generation from the current pinned spec includes239's config, guards and phases.
# No source/project minimum is rewritten; an explicit build minimum is verified below.
e.run('generate', ['xcodegen', 'generate', '--spec', 'apple/project.yml'])
project = ['xcodebuild', '-project', 'apple/AudiobookshelfNative.xcodeproj',
    '-scheme', 'AudiobookshelfNative', '-configuration', 'Debug',
    '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator',
    '-derivedDataPath', str(e.root / 'build'),
    'CODE_SIGNING_ALLOWED=NO', 'IPHONEOS_DEPLOYMENT_TARGET=14.0']
# Store only relevant resolved target settings, not an unrelated environment dump.
_, raw = e.run('settings-raw', project + ['-showBuildSettings', '-json'], seconds=120)
settings = json.loads(raw)
allowed = ['SDKROOT', 'SDK_VERSION', 'SDK_VERSION_ACTUAL', 'SDK_VERSION_MAJOR',
    'SDK_VERSION_MINOR', 'IPHONEOS_DEPLOYMENT_TARGET', 'PRODUCT_BUNDLE_IDENTIFIER',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS', 'ABS_SELECTED_SDK_KNOWN',
    'ABS_SELECTED_SDK_CAPABILITIES', 'CODE_SIGNING_ALLOWED']
(e.root / 'resolved-settings.json').write_text(json.dumps([
    {'target': item['target'], 'settings': {key: item['buildSettings'].get(key) for key in allowed}}
    for item in settings], indent=2))
# Raw settings contain no runtime evidence and need not be uploaded.
(e.root / 'settings-raw.log').unlink()
errors = []
bundle = e.root / 'build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app'
try:
    e.run('original-minimum-build', project + ['build'], seconds=900)
except Exception as error:
    errors.append(str(error))
try:
    e.app(bundle, 'com.forkzed.audiobookshelf.native.preview', '14.0')
    code, _ = e.run('signature-inspection', ['codesign', '-d', '-vvv', str(bundle)], required=False)
    (e.root / 'signature-scope.json').write_text(json.dumps({
        'buildSetting': 'CODE_SIGNING_ALLOWED=NO', 'inspectionExit': code,
        'scope': 'Unsigned simulator build requested. Inspect actual signature log; no private signing or runtime claim.'}, indent=2))
except Exception as error:
    errors.append(str(error))
(e.root / 'acceptance-scope.txt').write_text(
    'Original-minimum14.0 source-pinned generic simulator binary build only. '
    'No simulator boot, install, UI journey, hardware behavior or signed candidate acceptance.\n')
e.failures(errors)
