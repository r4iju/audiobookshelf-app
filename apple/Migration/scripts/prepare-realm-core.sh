#!/usr/bin/env bash
# Makes RealmSwift 10.54.6 buildable with SwiftPM on this Studio without compiling realm-core.
#
# realm-core 14.14.0 does not compile from source with Xcode 27's libc++, but the legacy app's
# CocoaPods install already uses Realm's official prebuilt core (the Realm pod's
# core/realm-monorepo.xcframework). This script wraps that same binary as a local `realm-core`
# package at tag 14.14.0 and mirrors the realm-core URL to it for the LegacyRealm package only.
#
# Source of the binary, in order:
#   1. REALM_CORE_XCFRAMEWORK, if set
#   2. the local CocoaPods cache of the Realm 10.54.6 pod
# No network fallback runs automatically. Set ABS_REALM_CORE_DOWNLOAD=1 to run Realm's own
# scripts/download-core.sh (the route `pod install` uses) explicitly.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
vendor="$here/Vendor"
package="$here/LegacyRealm"
mirror="$vendor/realm-core"

framework="${REALM_CORE_XCFRAMEWORK:-}"
if [ -z "$framework" ]; then
  framework="$(ls -d "$HOME"/Library/Caches/CocoaPods/Pods/Release/Realm/10.54.6-*/core/realm-monorepo.xcframework 2>/dev/null | head -1 || true)"
fi
if [ -z "$framework" ] || [ ! -d "$framework" ]; then
  if [ "${ABS_REALM_CORE_DOWNLOAD:-0}" = "1" ]; then
    work="$vendor/realm-swift-download"
    rm -rf "$work"
    git clone --depth 1 --branch v10.54.6 https://github.com/realm/realm-swift.git "$work"
    (cd "$work" && sh scripts/download-core.sh)
    framework="$work/core/realm-monorepo.xcframework"
  else
    echo "Prebuilt realm-core 14.14.0 not found. Set REALM_CORE_XCFRAMEWORK, or ABS_REALM_CORE_DOWNLOAD=1 to fetch it through Realm's own download script." >&2
    exit 1
  fi
fi

rm -rf "$mirror"
mkdir -p "$mirror/Sources/RealmCoreLinkage/include"
ln -s "$framework" "$mirror/realm-monorepo.xcframework"
cat > "$mirror/Package.swift" <<'MANIFEST'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RealmDatabase",
    products: [.library(name: "RealmCore", targets: ["RealmCoreBinary", "RealmCoreLinkage"])],
    targets: [
        .binaryTarget(name: "RealmCoreBinary", path: "realm-monorepo.xcframework"),
        .target(name: "RealmCoreLinkage", linkerSettings: [.linkedLibrary("z"), .linkedLibrary("compression"), .linkedLibrary("c++")]),
    ]
)
MANIFEST
echo 'void realm_core_linkage_anchor(void) {}' > "$mirror/Sources/RealmCoreLinkage/anchor.c"
echo 'void realm_core_linkage_anchor(void);' > "$mirror/Sources/RealmCoreLinkage/include/anchor.h"
(
  cd "$mirror"
  git init -q
  git add -A
  git -c user.name=local -c user.email=local@localhost -c commit.gpgSign=false commit -qm "Prebuilt realm-core 14.14.0"
  git -c tag.gpgSign=false tag 14.14.0
)
(
  cd "$package"
  swift package config unset-mirror --original https://github.com/realm/realm-core.git >/dev/null 2>&1 || true
  swift package config set-mirror --original https://github.com/realm/realm-core.git --mirror "file://$mirror"
)
echo "realm-core mirror ready: $mirror -> $framework"
