#!/usr/bin/env python3
"""Inventory the selected independent Android release graph and preserve its packaged license notices.

Run :app:writeRuntimeInventory with -Pleafwake=true first; add
-PleafwakeCast=true and --cast together for the Cast candidate. This validates known
license metadata, not every copyright or store requirement. Unknown licenses fail.
"""
import argparse
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
                            'LICENSE.MD', 'COPYRIGHT', 'COPYRIGHT.TXT', 'AL2.0', 'LGPL2.1',
                            'THIRD_PARTY_LICENSES.TXT', 'THIRD_PARTY_LICENSES.JSON'):
                result.append((prefix + name, z.read(name).decode('utf-8')))
            elif name == 'classes.jar' or (name.startswith('libs/') and name.endswith('.jar')):
                result.extend(embedded_notices(io.BytesIO(z.read(name)), prefix + name + '!'))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('inventory', nargs='?', type=Path, default=ROOT / 'android-native/app/build/reports/release-runtime.tsv')
    parser.add_argument('--cast', action='store_true', help='Use the reviewed independent Cast graph and Cast privacy disclosure')
    args = parser.parse_args()
    inventory = args.inventory
    inventory_lines = inventory.read_text().splitlines()
    has_cast = any(line.startswith('androidx.media3:media3-cast:') for line in inventory_lines)
    if has_cast != args.cast:
        raise ValueError('Selected notice variant does not match the resolved Cast dependency graph')
    assets = ROOT / f'android-native/app/src/{"withCast" if args.cast else "noCast"}/assets/leafwake'
    rows = []
    notices = {}
    for line in inventory_lines:
        coordinate, local = line.split('\t')
        group, artifact, version = coordinate.split(':')
        if not args.cast and (group == 'com.google.android.gms' or artifact == 'media3-cast'):
            raise ValueError(f'Cast/Play Services prohibited in Cast-free candidate: {coordinate}')
        path = Path(local)
        if coordinate == 'AudiobookshelfNativeAndroid:core:unspecified':
            declared = [{'name': 'MIT (scoped independent native code)', 'url': 'https://opensource.org/license/mit'}]
        elif coordinate == 'javax.inject:javax.inject:1':
            declared = [{'name': 'Apache-2.0 (JSR-330 source header)', 'url': 'https://github.com/javax-inject/javax-inject/blob/master/src/javax/inject/Inject.java'}]
        elif group == 'com.google.android.gms' and args.cast:
            approved = {'play-services-cast-framework': '22.3.1', 'play-services-cast': '22.3.1',
                        'play-services-base': '18.7.2', 'play-services-basement': '18.9.0',
                        'play-services-flags': '18.1.0', 'play-services-tasks': '18.3.2'}
            if approved.get(artifact) != version:
                raise ValueError(f'Unreviewed proprietary SDK: {coordinate}')
            declared = [{'name': 'Google SDK terms (proprietary)', 'url': 'https://developer.android.com/studio/terms'},
                        {'name': 'Google Cast additional terms', 'url': 'https://developers.google.com/cast/docs/terms'}]
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
    parts = ['Audiobook Loft, independently implemented native Android client, 2026.\n'
             'Origin: independent Audiobookshelf fork, not affiliated with upstream.\n'
             'Source is available using the Source code button.\n\n'
             + (ROOT / 'android-native/LICENSE').read_text(),
             'Resolved release dependencies (coordinates and declared licenses):\n' +
             '\n'.join(f"{r['coordinate']}: {', '.join(x['name'] for x in r['licenses'])}" for r in rows),
             'Apache License 2.0:\n' + (ROOT / 'releases/leafwake/dependency-licenses/Apache-2.0.txt').read_text()]
    parts.append('Mozilla Public License 2.0 (OkHttp public suffix data):\n' +
                 (ROOT / 'releases/leafwake/dependency-licenses/MPL-2.0.txt').read_text())
    parts.append('Material notification vector ic_small.xml: Copyright Google LLC, Apache-2.0.\n'
                 'JSR-330 javax.inject: Copyright (C) 2009 The JSR-330 Expert Group, Apache-2.0.\n'
                 'Source license header: https://github.com/javax-inject/javax-inject/blob/master/src/javax/inject/Inject.java')
    for filename in ('socket.io-client.txt', 'engine.io-client.txt'):
        parts.append(filename + '\n' + (ROOT / 'releases/leafwake/dependency-licenses' / filename).read_text())
    for content, origins in notices.items():
        parts.append('Embedded notices from:\n' + '\n'.join(origins) + '\n\n' + content)
    assets.mkdir(parents=True, exist_ok=True)
    (assets / 'licenses.txt').write_text('\n\n' + '\n\n'.join(parts))
    (assets / 'runtime-inventory.json').write_text(json.dumps(rows, indent=2) + '\n')
    (assets / 'privacy.txt').write_text((ROOT / f'releases/leafwake/{"ANDROID-CAST-PRIVACY.md" if args.cast else "PRIVACY.md"}').read_text())
    print(f'Generated notices for {len(rows)} artifacts; retained {len(notices)} distinct embedded notice texts.')


if __name__ == '__main__':
    main()
