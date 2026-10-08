#!/bin/bash
set -euo pipefail
fail() { echo "error: Native SDK capability contract: $*" >&2; exit 1; }
case "${PLATFORM_NAME:-}" in
  iphoneos|iphonesimulator|appletvos|appletvsimulator) ;;
  *) fail 'unexpected Apple app platform' ;;
esac
[[ "${SDK_VERSION:-}" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]] || fail 'invalid SDK version'
major=$((10#${BASH_REMATCH[1]}))
minor=$((10#${BASH_REMATCH[2]}))
[[ "${SDK_VERSION_MAJOR:-}" == "$((major * 10000))" ]] || fail 'unknown SDK major encoding'
[[ "${SDK_VERSION_MINOR:-}" == "$((major * 10000 + minor * 100))" ]] || fail 'unknown SDK minor encoding'
selected_version="$(/usr/bin/xcrun --sdk "${SDKROOT:?SDKROOT missing}" --show-sdk-version)"
[[ "$selected_version" == "$SDK_VERSION" ]] || fail 'SDK version does not match selected SDKROOT'
[[ "${ABS_SELECTED_SDK_KNOWN:-}" == YES ]] || fail 'SDK family missing from reviewed matrix'
conditions=" $(printf '%s' "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}" | tr '\t\n' '  ') "
[[ "$conditions" == *' ABS_SDK_CONTRACT '* ]] || fail 'shared xcconfig missing or overridden'
for capability in ABS_SDK_18 ABS_SDK_26 ABS_SDK_26_1; do
  expected=0
  case "$capability" in
    ABS_SDK_18) if (( major >= 18 )); then expected=1; fi ;;
    ABS_SDK_26) if (( major >= 26 )); then expected=1; fi ;;
    ABS_SDK_26_1) if (( major > 26 || (major == 26 && minor >= 1) )); then expected=1; fi ;;
  esac
  actual=0
  if [[ "$conditions" == *" $capability "* ]]; then actual=1; fi
  [[ "$expected" == "$actual" ]] || fail "incorrect $capability for SDK${SDK_VERSION}"
done
printf 'Native SDK contract: SDKROOT=%s SDK_VERSION=%s SDK_VERSION_ACTUAL=%s capabilities=%s\n' \
  "$SDKROOT" "$SDK_VERSION" "$SDK_VERSION_ACTUAL" "$ABS_SELECTED_SDK_CAPABILITIES"
