#!/usr/bin/env python3
"""Disposable GitHub macos-14 capability probe. Does not build/install the app."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from ci_support import Evidence

root = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'ios145-capability'
root.mkdir(parents=True, exist_ok=True)
os.environ['DEVELOPER_DIR'] = '/Applications/Xcode_15.4.app/Contents/Developer'
os.environ['PATH'] = str(Path(__file__).resolve().parent) + ':' + os.environ['PATH']
e = Evidence('ios145-capability')
e.source(expected_xcode="15.4", expected_swift="5.10")
run = e.run
run('host', ['sw_vers'])
run('arch', ['uname', '-m'])
run('xcode', ['xcodebuild', '-version'])
run('before', ['xcrun', 'simctl', 'list', 'runtimes', '-j'])
free = os.statvfs(root).f_bavail * os.statvfs(root).f_frsize
(root / 'free-bytes.txt').write_text(str(free))
if free < 18 * 1024 ** 3:
    sys.exit('Less than 18 GiB free: stop before package download; do not delete unrelated runner tools.')

url = 'https://devimages-cdn.apple.com/downloads/xcode/simulators/com.apple.pkg.iPhoneSimulatorSDK14_5-14.5.1.1621461325.dmg'
dmg = root / 'iOS14.5-18E182.dmg'
run('download', ['curl', '--fail', '--location', '--retry', '2', '--max-time', '600', url, '-o', str(dmg)], seconds=650)
run('sha256', ['shasum', '-a', '256', str(dmg)])
run('image-verify', ['hdiutil', 'verify', str(dmg)], seconds=180)

# Try Apple's documented import API first. The legacy catalog calls this contentType=package.
# A format rejection is distinct from a runtime/host rejection; neither is suppressed.
run('documented-import', ['xcodebuild', '-importPlatform', str(dmg)], seconds=300, required=False)
run('after-import', ['xcrun', 'simctl', 'list', 'runtimes', '-j'])
current = json.loads((root / 'after-import.log').read_text())['runtimes']
if not any(r.get('version') == '14.5' for r in current):
    mount = root / 'mount'
    mount.mkdir(exist_ok=True)
    run('mount', ['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(dmg)])
    try:
        packages = list(mount.glob('*.pkg'))
        if len(packages) != 1:
            sys.exit('Expected exactly one original Apple installer package; stop without repackaging.')
        package = packages[0]
        _, signature = run('package-signature', ['pkgutil', '--check-signature', str(package)])
        if 'Apple' not in signature:
            sys.exit('Signature output does not identify Apple; do not install.')
        run('package-files', ['pkgutil', '--payload-files', str(package)], required=False)
        # Stock signed package installation only. No expansion/repacking, destination override,
        # OS-version override or signature bypass. Installer rejection is a probe result.
        run('stock-package-install', ['sudo', 'installer', '-pkg', str(package), '-target', '/'], seconds=300)
    finally:
        run('unmount', ['hdiutil', 'detach', str(mount)], required=False)

_, output = run('after-install', ['xcrun', 'simctl', 'list', 'runtimes', '-j'])
runtimes = json.loads(output)['runtimes']
runtime = next((r for r in runtimes if r.get('version') == '14.5' and r.get('buildversion') == '18E182'), None)
if runtime is None:
    sys.exit('Exact 14.5/18E182 runtime was not registered.')
(root / 'selected-runtime.json').write_text(json.dumps(runtime, indent=2))
if not runtime.get('isAvailable'):
    sys.exit('Runtime installed but unavailable; preserve availabilityError, do not patch metadata.')

bundle = Path(runtime['bundlePath'])
run('runtime-info', ['plutil', '-p', str(bundle / 'Contents/Info.plist')])
dyld = bundle / 'Contents/Resources/RuntimeRoot/usr/lib/dyld'
if dyld.exists():
    run('runtime-dyld-architectures', ['lipo', '-archs', str(dyld)], required=False)

# The copied normal pool helper provisions a shared Pool iPhone name, never a per-task name.
# No direct simctl create/clone, Rosetta installation, or existing-device erase occurs.
_, leased = run('pool-acquire', ['sim', 'acquire', 'iphone', '--os', '14.5', '--no-boot', '--for', '239 official runtime capability'], seconds=120)
udid = next(line for line in leased.splitlines() if re.fullmatch(r'[0-9A-Fa-f-]{36}', line))
try:
    run('boot', ['xcrun', 'simctl', 'bootstatus', udid, '-b'], seconds=180)
    _, actual = run('actual-runtime', ['xcrun', 'simctl', 'list', 'devices', '-j'], seconds=30)
    if not any(d['udid'] == udid and d['state'] == 'Booted' for d in json.loads(actual)['devices'].get(runtime['identifier'], [])):
        raise RuntimeError('Lease did not boot under exact14.5/18E182 runtime')
    (root / 'boot-confirmed.json').write_text(json.dumps({'udid': udid, 'runtime': runtime['identifier'], 'version': '14.5', 'build': '18E182', 'state': 'Booted'}, indent=2))
finally:
    run('pool-release', ['sim', 'release', udid], seconds=60, required=False)
