#!/usr/bin/env python3
"""Create an internal Apple development profile using an existing App Store Connect key and certificate."""
import argparse
import base64
import json
import importlib.util
from pathlib import Path
import subprocess
import time

from cryptography.hazmat.primitives import serialization


BUNDLE = "com.forkzed.audiobookshelf.tv"


def api_client():
    spec = importlib.util.spec_from_file_location('appstore_api', Path(__file__).resolve().parents[2] / 'apple/scripts/appstore-api.py')
    api = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(api)
    return api.request


def provision(udid=None, inspect=False, platform="tvOS", bundle_identifier=BUNDLE, display_name="Audiobookshelf TV"):
    allowed_classes = {"APPLE_TV"} if platform == "tvOS" else {"IPHONE", "IPAD"}
    profile_type = "TVOS_APP_DEVELOPMENT" if platform == "tvOS" else "IOS_APP_DEVELOPMENT"
    api = api_client()
    devices = api("devices?limit=200")["data"]
    tvs = [device for device in devices if device["attributes"].get("deviceClass") in allowed_classes]
    if inspect:
        print(json.dumps([{"id": d["id"], **d["attributes"]} for d in tvs], indent=2))
        return
    if udid:
        matches = [d for d in devices if d["attributes"]["udid"] == udid]
        if matches:
            if matches[0]["attributes"].get("deviceClass") not in allowed_classes:
                raise RuntimeError("The supplied UDID does not match the requested device platform.")
            tvs = matches
        else:
            device = api("devices", "POST", {"data": {"type": "devices", "attributes": {"name": display_name, "udid": udid, "platform": "IOS"}}})["data"]
            if device["attributes"].get("deviceClass") not in allowed_classes:
                raise RuntimeError("Apple did not identify this UDID as the requested device platform.")
            tvs = [device]
    if not tvs:
        raise RuntimeError("No matching Apple device is registered. Pair it, then pass its UDID with --udid.")
    for device in tvs:
        if device["attributes"]["status"] == "DISABLED":
            api("devices/" + device["id"], "PATCH", {"data": {"type": "devices", "id": device["id"], "attributes": {"status": "ENABLED"}}})

    bundles = [bundle for bundle in api("bundleIds?filter[identifier]=" + bundle_identifier)["data"]
               if bundle["attributes"]["identifier"] == bundle_identifier]
    bundle = bundles[0] if bundles else api("bundleIds", "POST", {"data": {"type": "bundleIds", "attributes": {"identifier": bundle_identifier, "name": display_name, "platform": "IOS"}}})["data"]
    local_pem = subprocess.check_output(["security", "find-certificate", "-c", "Apple Development: Emanuel Franzen", "-p"])
    from cryptography import x509
    local_cert = x509.load_pem_x509_certificate(local_pem).public_bytes(serialization.Encoding.DER)
    certificates = api("certificates?limit=200")["data"]
    matches = [c for c in certificates if c["attributes"]["certificateType"] == "DEVELOPMENT" and base64.b64decode(c["attributes"]["certificateContent"]) == local_cert]
    if not matches:
        raise RuntimeError("The installed Apple Development certificate does not match an active developer certificate.")
    name = display_name + " Development " + time.strftime("%Y%m%d-%H%M%S")
    profile = api("profiles", "POST", {"data": {
        "type": "profiles", "attributes": {"name": name, "profileType": profile_type},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
            "certificates": {"data": [{"type": "certificates", "id": matches[0]["id"]}]},
            "devices": {"data": [{"type": "devices", "id": device["id"]} for device in tvs]},
        },
    }})["data"]["attributes"]
    directory = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / (profile["uuid"] + ".mobileprovision")
    path.write_bytes(base64.b64decode(profile["profileContent"]))
    # The deployment script consumes only the UUID on stdout.
    print(profile["uuid"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid")
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--platform", choices=["tvOS", "iOS"], default="tvOS")
    parser.add_argument("--bundle", default=BUNDLE)
    parser.add_argument("--name", default="Audiobookshelf TV")
    arguments = parser.parse_args()
    provision(arguments.udid, arguments.inspect, arguments.platform, arguments.bundle, arguments.name)
