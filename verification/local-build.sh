#!/bin/bash
set -euo pipefail
leafwake_root="$(cd "$(dirname "$0")/.." && pwd)"
leafwake_output="$leafwake_root/verification/outputs"
mkdir -p "$leafwake_output"
cd "$leafwake_root"
leafwake_web() { npm --prefix web run build > "$leafwake_output/web.log" 2>&1; }
leafwake_core() { (cd tvos/Core && swift test) > "$leafwake_output/core.log" 2>&1; }
leafwake_tv() { ./tvos/scripts/deploy.sh --build-only > "$leafwake_output/tv.log" 2>&1; }
leafwake_android() {
  leafwake_java21="${ABS_JAVA21_HOME:-$(/usr/libexec/java_home -v 21)}"
  (cd android-native && JAVA_HOME="$leafwake_java21" ./gradlew -Pleafwake=true :app:assembleDebug) > "$leafwake_output/android.log" 2>&1
}
leafwake_apple() {
  xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$leafwake_output/apple-derived" CODE_SIGNING_ALLOWED=NO \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 build > "$leafwake_output/apple.log" 2>&1
}
case "${1:-all}" in
  web) leafwake_web ;;
  core) leafwake_core ;;
  tv) leafwake_tv ;;
  android) leafwake_android ;;
  apple) leafwake_apple ;;
  all) leafwake_web; leafwake_core; leafwake_tv; leafwake_android; leafwake_apple ;;
  *) echo 'Usage: local-build.sh [web|core|tv|android|apple|all]' >&2; exit 2 ;;
esac
echo "Local build succeeded; logs/artifacts: $leafwake_output"
