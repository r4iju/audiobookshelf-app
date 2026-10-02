#!/bin/bash
# Download storage tests (DownloadStorageTests) on a small disk image mounted at apple/build-remaining-qa/full-volume,
# so a transfer can meet a genuinely full volume, on the dedicated simulator ("ABS Remaining QA iPhone" unless
# ABS_REMAINING_QA_SIMULATOR names another). Builds the same generated, git-ignored project as verify-remaining-qa.sh.
# Results: apple/build-remaining-qa/results/storage-<time>.xcresult. Extra arguments pass to xcodebuild.
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
simulator_name="${ABS_REMAINING_QA_SIMULATOR:-ABS Remaining QA iPhone}"
qa_root="$apple_root/build-remaining-qa"
image="$qa_root/full-volume.dmg"
mountpoint="$qa_root/full-volume"
label="storage-$(echo "$simulator_name" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$qa_root/results"
if mount | grep -q " on $mountpoint "; then
    echo "$mountpoint is already mounted; refusing to share it." >&2
    exit 2
fi
simulator="$(xcrun simctl list devices available | sed -n "s/^ *$simulator_name (\([0-9A-F-]*\)).*/\1/p" | head -1)"
[[ -n "$simulator" ]] || { echo "Create the simulator \"$simulator_name\" first (see docs/modernization/APPLE-REMAINING-QA.md)." >&2; exit 2; }
rm -f "$image"
hdiutil create -quiet -size 8m -fs HFS+ -volname ABSFullVolume "$image"
mkdir -p "$mountpoint"
hdiutil attach -quiet -nobrowse -mountpoint "$mountpoint" "$image"
trap 'hdiutil detach -quiet "$mountpoint" || hdiutil detach -quiet -force "$mountpoint"; rm -f "$image"' EXIT
python3 - "$apple_root/project.yml" "$qa_root/project.yml" <<'PY'
import sys
source, target = sys.argv[1:]
text = open(source).read()
assert text.startswith('name: AudiobookshelfNative\n')
open(target, 'w').write(text.replace('name: AudiobookshelfNative\n', 'name: build-remaining-qa\n', 1))
PY
xcodegen generate --quiet --spec "$qa_root/project.yml" --project-root "$apple_root" --project "$apple_root"
echo "simulator: $simulator_name ($simulator); volume: $mountpoint; results: $qa_root/results/$label.xcresult"
TEST_RUNNER_ABS_FULL_VOLUME="$mountpoint" xcodebuild -project "$apple_root/build-remaining-qa.xcodeproj" -scheme NativeTests \
    -destination "id=$simulator" -derivedDataPath "$qa_root/derived" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 -resultBundlePath "$qa_root/results/$label.xcresult" \
    -collect-test-diagnostics never "${@:--only-testing:NativeTests/DownloadStorageTests}" test
