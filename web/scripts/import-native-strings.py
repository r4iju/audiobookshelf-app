"""Carry only reviewed exact English/meaning equivalents from maintained native tables."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

web = Path(__file__).resolve().parents[1]
root = web.parent
mapping = json.loads((web / 'src/i18n/native-equivalents.json').read_text())
english = json.loads(subprocess.check_output(['node', '--input-type=module', '-e',
    "import {webStrings} from './src/i18n/web-strings.ts'; console.log(JSON.stringify(webStrings))"], cwd=web))
qualifiers = {'no': 'nb', 'pt-br': 'pt-rBR', 'zh-cn': 'zh-rCN', 'vi-vn': 'vi', 'he': 'iw'}
hashes = {}

def read(path):
    hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return path.read_text()

def android(code):
    path = root / 'android-native/app/src/main/res' / ('values' if code == 'en-us' else 'values-' + qualifiers.get(code, code)) / 'strings.xml'
    if not path.exists():
        return {}
    return {e.attrib['name']: ''.join(e.itertext()).replace("\\'", "'").replace('\\"', '"')
            for e in ET.fromstring(read(path)) if e.tag == 'string'}

def placeholders(value):
    return sorted(re.findall(r'\{\d+\}', value))

base_android = android('en-us')
output = web / 'src/i18n/native-strings'
output.mkdir(exist_ok=True)
coverage = {}
for path in sorted((root / 'apple/Localization/translations').glob('*.json')):
    code = path.stem
    apple = json.loads(read(path))
    droid = android(code)
    result = {}
    for key, match in mapping.items():
        source_key = match['key']
        source_english = source_key if match['source'] == 'apple' else base_android[source_key]
        if source_english != english[key]:
            raise ValueError(f'English changed: {key}')
        value = (apple if match['source'] == 'apple' else droid).get(source_key)
        if value and value != english[key] and placeholders(value) == placeholders(english[key]):
            result[key] = value
    (output / f'{code}.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    coverage[code] = len(result)
(output / 'provenance.json').write_text(json.dumps({'sourceSha256': hashes, 'coverage': coverage}, indent=2) + '\n')
print(json.dumps(coverage, indent=2))
