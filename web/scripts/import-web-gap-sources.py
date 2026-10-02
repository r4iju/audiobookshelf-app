"""Fill only gaps using the existing verified mappings and reviewed exact native equivalents."""
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

web = Path(__file__).resolve().parents[1]
root = web.parent
catalog = json.loads(subprocess.check_output(['node', '--input-type=module', '-e',
    "import {catalog} from './scripts/web-translation-catalog.mjs'; console.log(JSON.stringify(catalog))"], cwd=web))
qualifiers = {'no':'nb', 'pt-br':'pt-rBR', 'zh-cn':'zh-rCN', 'vi-vn':'vi', 'he':'iw'}
hashes = {}
reuse = {}

def read(path):
    hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return path.read_text()

def table(path):
    return json.loads(read(path)) if path.exists() else {}

def android(code):
    path = root/'android-native/app/src/main/res'/('values' if code=='en-us' else 'values-'+qualifiers.get(code, code))/'strings.xml'
    if not path.exists(): return {}
    return {e.attrib['name']: ''.join(e.itertext()).replace("\\'", "'").replace('\\"', '"') for e in ET.fromstring(read(path)) if e.tag=='string'}

def usable(value, english):
    import re
    return isinstance(value, str) and value.strip() and sorted(re.findall(r'\{\d+\}', value)) == sorted(re.findall(r'\{\d+\}', english)) and value.count('\n') == english.count('\n')

native = table(web/'src/i18n/native-equivalents.json')
native.update(table(web/'src/i18n/native-gap-equivalents.json'))
server = table(web/'src/i18n/server-equivalents.json')
english_android = android('en-us')
output = web/'src/i18n/source-fallbacks'
output.mkdir(exist_ok=True)
for path in sorted((web/'src/i18n/strings').glob('*.json')):
    code=path.stem
    if code=='en-us': continue
    legacy=table(path)
    carried={**legacy, **table(web/f'src/i18n/server-strings/{code}.json'), **table(web/f'src/i18n/native-strings/{code}.json')}
    apple=table(root/f'apple/Localization/translations/{code}.json')
    droid=android(code)
    result={}
    entry_sources={}
    for key, english in catalog.items():
        if usable(carried.get(key), english): continue
        if key in server and usable(legacy.get(server[key]), english):
            result[key]=legacy[server[key]]
            entry_sources[key]={'source':'legacy', 'key':server[key]}
        elif key in native:
            match=native[key]
            source_key=match['key']
            source_english=source_key if match['source']=='apple' else english_android[source_key]
            if source_english != english: raise ValueError(f'English changed: {key}')
            value=(apple if match['source']=='apple' else droid).get(source_key)
            if usable(value, english):
                result[key]=value
                entry_sources[key]=match
    (output/f'{code}.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    reuse[code]=entry_sources
(output/'provenance.json').write_text(json.dumps({'sourceSha256':hashes, 'entries':reuse, 'outputSha256':{p.stem:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.glob('*.json')) if p.stem!='provenance'}}, ensure_ascii=False, indent=2)+'\n')
print('Source fallback entries:', sum(len(entries) for entries in reuse.values()))
