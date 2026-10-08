#!/usr/bin/env python3
"""Authenticated App Store Connect requests through the owner's fixed proxy."""
import base64
import json
import os
from pathlib import Path
import subprocess
import time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


def request(path, method='GET', data=None):
    if not path or path.startswith('/') or '\n' in path:
        raise ValueError('Expected an App Store Connect v1 relative path')
    key_path = Path(os.environ.get('ASC_KEY_PATH', '~/.appstoreconnect/private_keys/AuthKey_HK78P3V55N.p8')).expanduser()
    key = serialization.load_pem_private_key(key_path.read_bytes(), None)
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b'=')
    now = int(time.time())
    header = encode(json.dumps({'alg': 'ES256', 'kid': os.environ.get('ASC_KEY_ID', 'HK78P3V55N')}).encode())
    payload = encode(json.dumps({'iss': os.environ.get('ASC_ISSUER_ID', '69a6de96-923d-47e3-e053-5b8c7c11a4d1'), 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}).encode())
    message = header + b'.' + payload
    r, s = decode_dss_signature(key.sign(message, ec.ECDSA(hashes.SHA256())))
    token = (message + b'.' + encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))).decode()
    # Keep authorization off argv and logs; no alternate egress or mutation retries.
    config = 'header = "Authorization: Bearer ' + token + '"\nheader = "Content-Type: application/json"\n'
    if data is not None:
        config += 'data = ' + json.dumps(json.dumps(data)) + '\n'
    command = ['curl', '--silent', '--show-error', '--globoff', '--max-time', '45', '--proxy', 'socks5h://192.168.0.1:1082', '--config', '-', '--request', method, '--write-out', '\n%{http_code}', 'https://api.appstoreconnect.apple.com/v1/' + path]
    result = subprocess.run(command, input=config, text=True, capture_output=True, check=True)
    body, status = result.stdout.rsplit('\n', 1)
    response = json.loads(body) if body else {}
    if not 200 <= int(status) < 300:
        raise RuntimeError('App Store Connect HTTP ' + status + ': ' + '; '.join(e.get('detail', e.get('title', 'API error')) for e in response.get('errors', [])))
    return response
