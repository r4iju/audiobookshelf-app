import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import time
import zipfile

class Evidence:
    def __init__(self, name):
        self.root = Path(os.environ['RUNNER_TEMP']) / name
        self.root.mkdir(parents=True, exist_ok=True)
        self.commands = []

    def run(self, label, command, seconds=120, required=True):
        path = self.root / (label + '.log')
        with path.open('w') as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=seconds)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = 124
        self.commands.append({'label': label, 'command': command, 'exit': code})
        (self.root / 'commands.json').write_text(json.dumps(self.commands, indent=2))
        print(label, code, flush=True)
        if required and code:
            raise RuntimeError(f'{label} failed ({code}); original log preserved')
        return code, path.read_text()

    def source(self):
        _, sha = self.run('source', ['git', 'rev-parse', 'HEAD'])
        if sha.strip() != os.environ.get('GITHUB_SHA'):
            raise RuntimeError('Checkout must match exact triggering GITHUB_SHA')
        _, status = self.run('source-clean', ['git', 'status', '--porcelain'])
        if status.strip():
            raise RuntimeError('Checkout must be clean before build; do not erase changes')
        self.run('host', ['sw_vers'])
        _, arch = self.run('architecture', ['uname', '-m'])
        if arch.strip() != 'arm64':
            raise RuntimeError('Expected arm64 runner; no Rosetta substitution')
        self.run('xcode', ['xcodebuild', '-version'])

    def app(self, bundle, identity, minimum):
        if not bundle.is_dir():
            raise RuntimeError(f'Expected app bundle missing: {bundle}')
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        (self.root / 'app-contract.json').write_text(json.dumps({k: info.get(k) for k in ['CFBundleIdentifier', 'MinimumOSVersion', 'CFBundleExecutable']}, indent=2))
        self.run('app-info', ['plutil', '-p', str(bundle / 'Info.plist')])
        _, build = self.run('binary-minimum', ['xcrun', 'vtool', '-show-build', str(bundle / info['CFBundleExecutable'])])
        hashes = {str(f.relative_to(bundle)): hashlib.sha256(f.read_bytes()).hexdigest() for f in bundle.rglob('*') if f.is_file() and not f.is_symlink()}
        (self.root / 'binary-sha256.json').write_text(json.dumps(hashes, indent=2))
        if info.get('CFBundleIdentifier') != identity or info.get('MinimumOSVersion') != minimum or not re.search(r'\bminos\s+' + re.escape(minimum) + r'(?:\s|$)', build):
            raise RuntimeError('Stable identity or actual deployment minimum mismatch')

    def results(self, result):
        if not result.is_dir():
            raise RuntimeError('Original xcresult missing; acceptance remains pending')
        # Preserve raw evidence before any derived-object/export failure can occur.
        original_files = [f for f in result.rglob('*') if f.is_file()]
        original_size = sum(f.stat().st_size for f in original_files)
        if original_size > 250 * 1024 ** 2:
            (self.root / 'artifact-overflow.txt').write_text(f'Original xcresult is {original_size} bytes, exceeds250 MiB. Not truncated; evidence pending.')
            raise RuntimeError('Original xcresult exceeds bounded250 MiB')
        with zipfile.ZipFile(self.root / 'original-results.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
            for f in original_files:
                archive.write(f, f.relative_to(self.root))
        (self.root / 'capture-policy.txt').write_text('User explicitly stopped screenshots October8. Attachment-only helpers suppressed in disposable test instrumentation; raw xcresult retained. No image export or screenshot gate.')

    def failures(self, errors):
        (self.root / 'failures.json').write_text(json.dumps(errors, indent=2))
        if errors:
            raise RuntimeError('; '.join(errors))
