#!/bin/bash
# Run from the repository root: bash docs/modernization/evidence/apple-real-server/exit-status/fail-demo.sh <output-dir>
# Bounded fake: xcodebuild is a stub that writes a failing test log and exits 65, as a real failed run does.
export ABS_RS_OUT="$1"
source docs/modernization/evidence/apple-real-server/common.sh
xcodebuild() { echo "Test Case '-[NativeJourneyTests.RealServerProbe testFake]' failed (0.1 seconds)."; return 65; }
verify-ui() { :; }
RS_PHONE=fake-device
phone fake testFake; echo "phone() returned $?"
step phone fake2 testFake
RS_TV_RUNNER=false step tv fake testFake
finish
