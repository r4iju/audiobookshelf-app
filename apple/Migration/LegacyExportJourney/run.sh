#!/bin/zsh
# The legacy export journey on a dedicated simulator, with synthetic data only:
#  1. builds and launches the legacy app (scripts/legacy-app-launch-check.sh),
#  2. replaces its library with a synthetic one written by the app's own Realm models
#     (one connection with a synthetic token, a downloaded book with a real EPUB, progress,
#     an interrupted download and a log entry), and clears its WebView storage,
#  3. drives the app with a UI test: opens the EPUB in the app's reader (which writes its own
#     reader settings and location cache), exports from Settings, saves the package to
#     On My iPhone through the Files save dialog and removes the export,
#  4. checks the saved package: no credential or log, reader storage present, and it imports.
#
#   apple/Migration/LegacyExportJourney/run.sh
#
# ABS_LEGACY_SIMULATOR and ABS_LEGACY_SKIP_BUILD as for the launch check. Output: /tmp/abs-journey.
set -euo pipefail

here=${0:A:h}
migration=${here:h}
out=${ABS_LEGACY_JOURNEY_OUT:-/tmp/abs-journey}
device_name=${ABS_LEGACY_SIMULATOR:-ABS Legacy Export}
bundle=com.audiobookshelf.app.dev
mkdir -p "$out"

"$migration/scripts/legacy-app-launch-check.sh"
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"] == sys.argv[1]))' "$device_name")

python3 "$here/make-epub.py" "$out/book.epub"
(cd "$migration/LegacyRealm" && ABS_LEGACY_JOURNEY_FIXTURE=$out ABS_LEGACY_JOURNEY_EPUB=$out/book.epub \
  swift test --filter 'LegacyJourneyFixture/testWriteTheSimulatorJourneyLibrary' > "$out/fixture.log" 2>&1) \
  || { tail -20 "$out/fixture.log"; echo "FAIL: fixture"; exit 1; }

xcrun simctl terminate "$udid" "$bundle" > /dev/null 2>&1 || true
container=$(xcrun simctl get_app_container "$udid" "$bundle" data)
rm -rf "$container/Documents" "$container/Library/WebKit" "$container/tmp/LegacyMigrationExport"
cp -R "$out/Documents" "$container/Documents"
devices=${container%%/data/Containers/*}/data
find "$devices/Containers/Shared/AppGroup" -path '*File Provider Storage*' -name '*.absmigration' -prune -exec rm -rf {} + 2> /dev/null || true

mkdir -p "$out/runner"
xcodegen --spec "$here/project.yml" --project "$out/runner" --quiet
rm -rf "$out/journey.xcresult"
xcodebuild test -project "$out/runner/LegacyExportJourney.xcodeproj" -scheme LegacyExportJourneyUITests \
  -destination "id=$udid" -derivedDataPath "$out/dd" -resultBundlePath "$out/journey.xcresult" \
  -only-testing:LegacyExportJourneyUITests/LegacyExportJourneyUITests \
  -collect-test-diagnostics never > "$out/journey.log" 2>&1 \
  || { grep -E "error:" "$out/journey.log" | head; echo "FAIL: journey (log: $out/journey.log, results: $out/journey.xcresult)"; exit 1; }

saved=$(find "$devices/Containers/Shared/AppGroup" -path '*File Provider Storage*' -name '*.absmigration' -prune 2> /dev/null | head -1)
[[ -n $saved ]] || { echo "FAIL: no package in On My iPhone"; exit 1; }
rm -rf "$out/saved.absmigration"
cp -R "$saved" "$out/saved.absmigration"
(cd "$migration/LegacyRealm" && ABS_LEGACY_JOURNEY_PACKAGE=$out/saved.absmigration ABS_LEGACY_JOURNEY_EPUB=$out/book.epub \
  swift test --filter 'LegacyJourneyFixture/testTheSavedJourneyPackageCarriesTheLibraryWithoutCredentials' > "$out/verify.log" 2>&1) \
  || { grep -E "error:" "$out/verify.log" | head; echo "FAIL: saved package (log: $out/verify.log)"; exit 1; }
if [[ -e "$container/tmp/LegacyMigrationExport" ]] && [[ -n $(ls -A "$container/tmp/LegacyMigrationExport") ]]; then
  echo "FAIL: the removed export is still in the app's temporary storage"; exit 1
fi
echo "saved in On My iPhone: $saved"
echo "PASS: exported in the legacy app, saved through Files, checked and imported (copy: $out/saved.absmigration)"
