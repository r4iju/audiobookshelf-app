#!/bin/bash
# Run from the repository root: bash docs/modernization/evidence/apple-real-server/exit-status/fail-demo.sh <output-dir>
# Bounded fake of a passing run: the stub writes a passing test log and exits 0.
export ABS_RS_OUT="$1"
source docs/modernization/evidence/apple-real-server/common.sh
xcodebuild() { echo "Test Case '-[NativeJourneyTests.RealServerProbe testFake]' passed (0.1 seconds)."; return 0; }
RS_PHONE=fake-device
step phone fake testFake
RS_TV_RUNNER=true step tv fake testFake
finish
