#!/usr/bin/env python3
"""Check existing Play service-account access without creating an edit or uploading."""
import base64
import json
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: check-play-access.py <private service-account JSON> <package ID>")
    credentials = json.loads(Path(sys.argv[1]).expanduser().read_text())
    package = sys.argv[2]
    if credentials.get("type") != "service_account":
        raise SystemExit("Expected service-account credentials.")
    # Credentials must not redirect a signed assertion to an arbitrary token endpoint.
    token_url = "https://oauth2.googleapis.com/token"
    now = int(time.time())
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
    header = encode(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    payload = encode(json.dumps({"iss": credentials["client_email"],
        "scope": "https://www.googleapis.com/auth/androidpublisher", "aud": token_url,
        "iat": now, "exp": now + 3600}).encode())
    message = header + b"." + payload
    key = serialization.load_pem_private_key(credentials["private_key"].encode(), None)
    signature = encode(key.sign(message, padding.PKCS1v15(), hashes.SHA256()))
    request = urllib.request.Request(token_url, data=urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": (message + b"." + signature).decode(),
    }).encode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            token = json.load(response)["access_token"]
        request = urllib.request.Request(
            "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
            + urllib.parse.quote(package, safe="") + "/reviews?maxResults=1",
            headers={"Authorization": "Bearer " + token})
        with urllib.request.urlopen(request, timeout=30) as response:
            print(package, "Play reviews read access verified:", response.status)
    except urllib.error.HTTPError as error:
        print(package, "Play access check returned HTTP", error.code)
        if error.code == 404:
            print("Register the app and its first artifact in Play Console, then grant this account app access.")
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
