#!/usr/bin/env python3
"""Inventory the Cast-free release graph and preserve its packaged license notices.

Run :app:writeRuntimeInventory with -Pleafwake=true first. This validates known
license metadata, not every copyright or store requirement. Unknown licenses fail.
"""
import hashlib
import io
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path.home() / '.gradle/caches/modules-2/files-2.1'
NS = {'m': 'http://maven.apache.org/POM/4.0.0'}
ASSETS = ROOT / 'android-native/app/src/noCast/assets/leafwake'


def pom(coordinate):
    candidates = list((CACHE / '/'.join(coordinate.split(':'))).glob('*/*.pom'))
    if len(candidates) != 1:
        raise ValueError(f'Expected one cached POM for {coordinate}, got {len(candidates)}')
    return ET.parse(candidates[0]).getroot()


def licenses(coordinate, seen=None):
    seen = set() if seen is None else seen
    if coordinate in seen:
        raise ValueError(f'Cyclic POM parent at {coordinate}')
    seen.add(coordinate)
    root = pom(coordinate)
    result = [{'name': x.findtext('m:name', namespaces=NS),
               'url': x.findtext('m:url', namespaces=NS)}
              for x in root.findall('m:licenses/m:license', NS)]
    if result:
        return result
    parent = root.find('m:parent', NS)
    if parent is None:
        raise ValueError(f'No license metadata for {coordinate}')
    return licenses(':'.join(parent.findtext(f'm:{part}', namespaces=NS)
                             for part in ('groupId', 'artifactId', 'version')), seen)


def embedded_notices(archive, prefix=''):
    result = []
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            basename = Path(name).name.upper()
            if basename in ('NOTICE', 'NOTICE.TXT', 'LICENSE', 'LICENSE.TXT',
                            'LICENSE.MD', 'COPYRIGHT', 'COPYRIGHT.TXT', 'AL2.0', 'LGPL2.1'):
                result.append((prefix + name, z.read(name).decode('utf-8')))
            elif name == 'classes.jar' or (name.startswith('libs/') and name.endswith('.jar')):
                result.extend(embedded_notices(io.BytesIO(z.read(name)), prefix + name + '!'))
    return result


def main():
    inventory = Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT / 'android-native/app/build/reports/release-runtime.tsv'
    rows = []
    notices = {}
    for line in inventory.read_text().splitlines():
        coordinate, local = line.split('\t')
        group, artifact, version = coordinate.split(':')
        if group == 'com.google.android.gms' or artifact == 'media3-cast':
            raise ValueError(f'Cast/Play Services prohibited in public candidate: {coordinate}')
        path = Path(local)
        if coordinate == 'AudiobookshelfNativeAndroid:core:unspecified':
            declared = [{'name': 'GPL-3.0', 'url': 'https://github.com/r4iju/audiobookshelf-app'}]
        else:
            declared = licenses(coordinate)
            for entry in declared:
                reviewed = {
                    'Apache 2.0', 'Apache License, Version 2.0', 'Apache-2.0',
                    'The Apache License, Version 2.0', 'The Apache Software License, Version 2.0',
                    'The MIT License', 'The MIT License (MIT)',
                }
                allowed_urls = ({'http://opensource.org/licenses/MIT', 'http://opensource.org/licenses/mit-license'}
                                if entry['name'] in {'The MIT License', 'The MIT License (MIT)'}
                                else {'http://www.apache.org/licenses/LICENSE-2.0.txt', 'https://www.apache.org/licenses/LICENSE-2.0.txt'})
                if entry['name'] not in reviewed or entry['url'] not in allowed_urls:
                    raise ValueError(f'Unreviewed license for {coordinate}: {entry}')
        rows.append({'coordinate': coordinate, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'licenses': declared})
        for name, content in embedded_notices(path):
            notices.setdefault(content, []).append(f'{coordinate}: {name}')
    parts = ['Leafwake, modified independent Audiobookshelf client, 2026.\n'
             'Fork modifications by Emanuel Franzen and contributors.\n'
             'Upstream copyright notices and GPLv3 are retained. No warranty.\n'
             'Corresponding source is available using the Source code button.\n\n'
             'Application license (GPLv3):\n' + (ROOT / 'LICENSE').read_text(),
             'Resolved release dependencies (coordinates and declared licenses):\n' +
             '\n'.join(f"{r['coordinate']}: {', '.join(x['name'] for x in r['licenses'])}" for r in rows),
             'Apache License 2.0:\n' + (ROOT / 'releases/leafwake/dependency-licenses/Apache-2.0.txt').read_text()]
    parts.append('Mozilla Public License 2.0 (OkHttp public suffix data):\n' +
                 (ROOT / 'releases/leafwake/dependency-licenses/MPL-2.0.txt').read_text())
    for filename in ('socket.io-client.txt', 'engine.io-client.txt'):
        parts.append(filename + '\n' + (ROOT / 'releases/leafwake/dependency-licenses' / filename).read_text())
    for content, origins in notices.items():
        parts.append('Embedded notices from:\n' + '\n'.join(origins) + '\n\n' + content)
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / 'licenses.txt').write_text('\n\n' + '\n\n'.join(parts))
    (ASSETS / 'runtime-inventory.json').write_text(json.dumps(rows, indent=2) + '\n')
    (ASSETS / 'privacy.txt').write_text((ROOT / 'releases/leafwake/PRIVACY.md').read_text())
    print(f'Generated notices for {len(rows)} artifacts; retained {len(notices)} distinct embedded notice texts.')


if __name__ == '__main__':
    main()
