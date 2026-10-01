#!/bin/bash
set -euo pipefail
apple_root="$(cd "$(dirname "$0")/.." && pwd)"
repo_root="$(cd "$apple_root/.." && pwd)"
if [[ $# -ne 1 ]]; then
    echo 'Usage: apple/scripts/deploy.sh --build-only | <paired iPhone/iPad UDID>' >&2
    exit 2
fi
apple_target="$1"
profile_args=(--platform iOS --bundle com.forkzed.audiobookshelf.native.preview --name 'Audiobookshelf Native Preview')
if [[ "$apple_target" != '--build-only' ]]; then
    profile_args+=(--udid "$apple_target")
fi
apple_profile="$(python3 "$repo_root/tvos/scripts/provision.py" "${profile_args[@]}")"
xcodegen generate --spec "$apple_root/project.yml"
apple_actions=(build)
if [[ "${ABS_CLEAN_BUILD:-0}" == '1' ]]; then apple_actions=(clean build); fi
apple_build() {
xcodebuild -project "$apple_root/AudiobookshelfNative.xcodeproj" \
    -scheme AudiobookshelfNative -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$apple_root/build-release" IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' \
    PROVISIONING_PROFILE_SPECIFIER="$apple_profile" "$@"
}
apple_build "${apple_actions[@]}"
apple_app="$apple_root/build-release/Build/Products/Release-iphoneos/AudiobookshelfNative.app"
if ! codesign --verify --deep --strict "$apple_app"; then
    if [[ "${ABS_CLEAN_BUILD:-0}" == '1' ]]; then exit 1; fi
    echo 'Cached signature resources failed verification; rebuilding locally.'
    apple_build clean build
    codesign --verify --deep --strict "$apple_app"
fi
mkdir -p "$apple_root/build-release/package/Payload"
rm -rf "$apple_root/build-release/package/Payload/AudiobookshelfNative.app"
ditto "$apple_app" "$apple_root/build-release/package/Payload/AudiobookshelfNative.app"
codesign --verify --deep --strict "$apple_root/build-release/package/Payload/AudiobookshelfNative.app"
(cd "$apple_root/build-release/package" && ditto -c -k --keepParent Payload ../AudiobookshelfNative.ipa)
if [[ "$apple_target" == '--build-only' ]]; then
    echo "Signed internal preview: $apple_app"
else
    xcrun devicectl device install app --device "$apple_target" "$apple_app"
    xcrun devicectl device process launch --device "$apple_target" com.forkzed.audiobookshelf.native.preview
fi
