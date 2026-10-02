#!/bin/bash
# Real-server phone probe: leased pool iPhone, isolated abs-apple-qa (19890). Stops/starts only that container.
set -uo pipefail
cd "$(dirname "$0")/../../.."
E=apple/build-qa/real-server
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
udid="$(sim acquire iphone --no-boot --for 'audiobookshelf apple real-server probe' | tail -1)"
trap 'sim release "$udid" >/dev/null 2>&1; git checkout -q -- apple/AudiobookshelfNative.xcodeproj/project.pbxproj' EXIT
echo "lease=$udid"
xcodegen generate --quiet --spec apple/project.yml
run() { name=$1; shift
  xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme AudiobookshelfNative -destination "id=$udid" \
    -derivedDataPath apple/build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    -collect-test-diagnostics never -resultBundlePath "$PWD/$E/phone-$name.xcresult" "$@" test > "$E/phone-$name.log" 2>&1
  echo "$name exit=$?"; grep -E "Test Case .*(passed|failed)|error: -\[" "$E/phone-$name.log"; }
P=NativeJourneyTests/RealServerProbe
run online -only-testing:$P/test1SignInBrowseAndStreamAcrossFiles -only-testing:$P/test2PDFPageSavedToServerAndRestored -only-testing:$P/test3PodcastEpisodeProgress
run download -only-testing:$P/test4aDownloadForOffline
docker stop abs-apple-qa >/dev/null && echo "server stopped $(date +%T)"
run offline -only-testing:$P/test4bPlayOfflineWithServerStopped
docker start abs-apple-qa >/dev/null && echo "server started $(date +%T)"
for i in $(seq 1 60); do curl -sf http://127.0.0.1:19890/status >/dev/null && break; sleep 1; done
run reconnect -only-testing:$P/test4cReconnectPublishesOfflineListening
