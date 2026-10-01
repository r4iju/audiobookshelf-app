#!/bin/bash
set -euo pipefail
abs_root="$(cd "$(dirname "$0")/.." && pwd)"
abs_output="$abs_root/verification/outputs"
mkdir -p "$abs_output"
cd "$abs_root"
abs_web() { npm run generate > "$abs_output/web.log" 2>&1; }
abs_core() { (cd tvos/Core && swift test) > "$abs_output/core.log" 2>&1; }
abs_tv() { ./tvos/scripts/deploy.sh --build-only > "$abs_output/tv.log" 2>&1; }
abs_android() {
  abs_java21="${ABS_JAVA21_HOME:-$(/usr/libexec/java_home -v 21)}"
  (cd android && JAVA_HOME="$abs_java21" ./gradlew :app:assembleDebug) > "$abs_output/android.log" 2>&1
}
abs_apple_legacy() {
  abs_copy="$(mktemp -d "${TMPDIR:-/tmp}/abs-legacy-build.XXXXXX")"
  trap 'rm -rf "$abs_copy"' EXIT
  rsync -a --exclude Pods --exclude build ios/ "$abs_copy/ios/"
  ln -s "$abs_root/node_modules" "$abs_copy/node_modules"
  pod install --project-directory="$abs_copy/ios/App" > "$abs_output/pods.log" 2>&1
  # SDK 27 cannot target iOS 14. This reference override does not change the app's minimum.
  xcodebuild -workspace "$abs_copy/ios/App/App.xcworkspace" -scheme App -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$abs_output/ios-derived" CODE_SIGNING_ALLOWED=NO \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 build > "$abs_output/ios.log" 2>&1
  ditto "$abs_output/ios-derived/Build/Products/Debug-iphonesimulator/Audiobookshelf.app" "$abs_output/Audiobookshelf-legacy.app"
}
case "${1:-all}" in
  web) abs_web ;;
  core) abs_core ;;
  tv) abs_tv ;;
  android-legacy) abs_android ;;
  apple-legacy) abs_apple_legacy ;;
  all) abs_web; abs_core; abs_tv; abs_android; abs_apple_legacy ;;
  *) echo 'Usage: local-build.sh [web|core|tv|android-legacy|apple-legacy|all]' >&2; exit 2 ;;
esac
echo "Local build succeeded; logs/artifacts: $abs_output"
