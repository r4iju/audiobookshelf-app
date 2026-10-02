#!/bin/bash
# Third phone podcast attempt (probe read the wrong label twice) and the TV resume case alone after its sign-in focus flake.
set -uo pipefail
cd "$(dirname "$0")/../../.."
E=apple/build-qa/real-server
trap 'git checkout -q -- apple/AudiobookshelfNative.xcodeproj/project.pbxproj tvos/AudiobookshelfTV.xcodeproj/project.pbxproj 2>/dev/null' EXIT
udid="$(sim acquire iphone --no-boot --for 'audiobookshelf apple real-server probe' | tail -1)"
xcodegen generate --quiet --spec apple/project.yml
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination "id=$udid" \
  -derivedDataPath apple/build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  -collect-test-diagnostics never -resultBundlePath "$PWD/$E/phone-podcast-rerun3.xcresult" \
  -only-testing:NativeJourneyTests/RealServerProbe/test3PodcastEpisodeProgress test > "$E/phone-podcast-rerun3.log" 2>&1
echo "podcast-rerun3 exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[" "$E/phone-podcast-rerun3.log"
sim release "$udid" >/dev/null 2>&1
ABS_TV_RESULT_BUNDLE="$PWD/$E/tv-resume-rerun3.xcresult" tvos/scripts/verify-ui.sh -only-testing:TVJourneyTests/RealServerProbe/test1ResumeAnotherClientsPositionAndCrossFiles > "$E/tv-resume-rerun3.log" 2>&1
echo "tv-resume-rerun3 exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[|TV_RESUME" "$E/tv-resume-rerun3.log"
