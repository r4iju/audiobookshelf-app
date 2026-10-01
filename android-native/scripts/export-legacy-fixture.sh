#!/bin/sh
# Rebuilds core/src/test/resources/migration/legacy-export.absmigration with the legacy app's own
# exporter on the QA emulator. Synthetic data only; never point this at a device holding real data.
set -eu
serial="${ANDROID_SERIAL:-emulator-5584}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
legacy_jdk="${LEGACY_JAVA_HOME:-$HOME/Library/Java/JavaVirtualMachines/jdk-21.0.12.1+1/Contents/Home}"
cd "$repo_root"
NUXT_TELEMETRY_DISABLED=1 npx --offline nuxt generate
npx --offline cap sync android
(cd android && JAVA_HOME="$legacy_jdk" ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest -q)
adb -s "$serial" install -r -t android/app/build/outputs/apk/debug/app-debug.apk
adb -s "$serial" install -r -t android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s "$serial" shell am instrument -w -e class com.audiobookshelf.app.migration.LegacyMigrationExportTest \
  com.audiobookshelf.app.debug.test/androidx.test.runner.AndroidJUnitRunner | tee /tmp/legacy-export.log
grep -q "^OK (1 test)" /tmp/legacy-export.log
adb -s "$serial" pull /sdcard/Android/data/com.audiobookshelf.app.debug/files/legacy-export.absmigration \
  android-native/core/src/test/resources/migration/legacy-export.absmigration
