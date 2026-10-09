#!/usr/bin/env python3
"""Reuse or create distribution profiles for the independent Apple beta."""
import base64
import importlib.util
import json
from pathlib import Path
import subprocess
from urllib.parse import quote

spec = importlib.util.spec_from_file_location('appstore_api', Path(__file__).with_name('appstore-api.py'))
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)

def main():
    bundle = api.request('bundleIds?filter[identifier]=com.forkzed.leafwake')['data']
    if len(bundle) != 1:
        raise RuntimeError('Expected the existing independent app bundle registration')
    certificate = subprocess.check_output(['security', 'find-certificate', '-c', 'Apple Distribution: Emanuel Franzen', '-p'])
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
    der = x509.load_pem_x509_certificate(certificate).public_bytes(serialization.Encoding.DER)
    certificates = api.request('certificates?limit=200')['data']
    matches = [c for c in certificates if 'DISTRIBUTION' in c['attributes']['certificateType'] and base64.b64decode(c['attributes']['certificateContent']) == der]
    if len(matches) != 1:
        raise RuntimeError('Installed distribution certificate must match one active Apple certificate')
    profiles = {}
    for platform, profile_type in [('ios', 'IOS_APP_STORE'), ('tv', 'TVOS_APP_STORE')]:
        name = 'Audiobook Loft ' + profile_type + ' ' + matches[0]['id']
        existing = api.request('profiles?filter[name]=' + quote(name) + '&include=bundleId,certificates')['data']
        valid = [p for p in existing if p['attributes']['profileState'] == 'ACTIVE' and p['attributes']['profileType'] == profile_type and p['relationships']['bundleId']['data']['id'] == bundle[0]['id'] and any(c['id'] == matches[0]['id'] for c in p['relationships']['certificates']['data'])]
        profile = valid[0] if valid else api.request('profiles', 'POST', {'data': {'type': 'profiles', 'attributes': {'name': name, 'profileType': profile_type}, 'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bundle[0]['id']}}, 'certificates': {'data': [{'type': 'certificates', 'id': matches[0]['id']}]}}}})['data']
        a = profile['attributes']
        destination = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
        destination.mkdir(parents=True, exist_ok=True)
        (destination / (a['uuid'] + '.mobileprovision')).write_bytes(base64.b64decode(a['profileContent']))
        profiles[platform] = {'uuid': a['uuid'], 'name': a['name'], 'type': a['profileType'], 'expiration': a['expirationDate']}
    output = Path('/tmp/loft-independent-apple/distribution-profiles.json')
    output.write_text(json.dumps(profiles, indent=2) + '\n')
    print('Verified independent iOS/tvOS distribution profiles; metadata saved privately.')

if __name__ == '__main__':
    main()
