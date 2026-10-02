#!/bin/bash
# TV resume case after the chapter-step correction (Previous restarts a chapter more than 3 s in).
set -uo pipefail
cd "$(dirname "$0")/../../.."
E=apple/build-qa/real-server
trap 'git checkout -q -- apple/AudiobookshelfNative.xcodeproj/project.pbxproj tvos/AudiobookshelfTV.xcodeproj/project.pbxproj 2>/dev/null' EXIT
ABS_TV_RESULT_BUNDLE="$PWD/$E/tv-resume-rerun3.xcresult" tvos/scripts/verify-ui.sh -only-testing:TVJourneyTests/RealServerProbe/test1ResumeAnotherClientsPositionAndCrossFiles > "$E/tv-resume-rerun3.log" 2>&1
echo "tv-resume-rerun3 exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[|TV_RESUME" "$E/tv-resume-rerun3.log"
