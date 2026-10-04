#!/usr/bin/env python3
"""Create Leafwake's local Android signing identity without overwriting existing keys."""
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile


def main():
    directory = Path(sys.argv[1]).expanduser() if len(sys.argv) == 2 else Path.home() / ".local/share/leafwake/signing"
    if len(sys.argv) > 2:
        raise SystemExit("Usage: init-signing.py [private signing directory]")
    directory.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    config = directory / "signing.json"
    keystore = directory / "leafwake-release.p12"
    if directory.exists():
        raise SystemExit("Signing material already exists. Preserve it; this command never replaces it.")
    keytool = shutil.which("keytool")
    if not keytool:
        raise SystemExit("keytool is required; configure Java 17 before creating the key.")
    lock = directory.parent / ("." + directory.name + ".init-lock")
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError:
        raise SystemExit("Another signing initialization holds the lock: " + str(lock)) from None
    stage = None
    old_mask = os.umask(0o077)
    try:
        if directory.exists():
            raise SystemExit("Signing directory appeared; refusing to replace it.")
        stage = Path(tempfile.mkdtemp(prefix=".leafwake-signing-", dir=directory.parent))
        password = secrets.token_urlsafe(48)
        env = os.environ | {"LEAFWAKE_KEY_PASSWORD": password}
        # Persist the password before keytool can create a private key. If interrupted,
        # the private staging directory retains both the key and its recovery information.
        with (stage / "signing.json").open("x") as handle:
            json.dump({"keystore": str(keystore.resolve()), "storePassword": password,
                       "keyAlias": "leafwake", "keyPassword": password}, handle)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        subprocess.run([
            keytool, "-genkeypair", "-noprompt", "-keystore", str(stage / keystore.name),
            "-storetype", "PKCS12", "-alias", "leafwake", "-keyalg", "RSA",
            "-keysize", "4096", "-validity", "10000",
            "-dname", "CN=Leafwake Android Release, O=Emanuel Franzen",
            "-storepass:env", "LEAFWAKE_KEY_PASSWORD", "-keypass:env", "LEAFWAKE_KEY_PASSWORD",
        ], env=env, check=True)
        if directory.exists():
            raise SystemExit("Signing directory appeared; recovery files remain in " + str(stage))
        stage.rename(directory)
        stage = None
        print("Created Leafwake signing files in", directory)
        print("Back up both files securely before distribution. Private values were not printed.")
    finally:
        os.umask(old_mask)
        lock.rmdir()
        if stage is not None:
            print("Incomplete signing initialization retained for recovery:", stage, file=sys.stderr)


if __name__ == "__main__":
    main()
