#!/bin/sh
# Builds the internal release APK locally, verifies its signature and prints its identity and checksum.
# Signed with the local debug key unless ABS_ANDROID_KEYSTORE (and its _PASSWORD, ABS_ANDROID_KEY_ALIAS,
# ABS_ANDROID_KEY_PASSWORD) name an owner-provided keystore. Nothing is uploaded anywhere.
set -eu
cd "$(dirname "$0")/.."
: "${JAVA_HOME:=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}"
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
export JAVA_HOME ANDROID_HOME
./gradlew :core:test :app:testDebugUnitTest :app:assembleRelease -q
apk=app/build/outputs/apk/release/app-release.apk
tools="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)"
"$tools/apksigner" verify --print-certs "$apk" | grep -E "Signer #1 certificate (DN|SHA-256)"
"$tools/aapt2" dump badging "$apk" | grep -E "^package:|^application-label:"
shasum -a 256 "$apk"
