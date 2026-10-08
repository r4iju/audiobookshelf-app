#!/bin/bash
set -euo pipefail
build_number="${LEAFWAKE_APPLE_BUILD_NUMBER:-2}"
audience="${LEAFWAKE_APPLE_AUDIENCE:-internal}"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || { echo 'Expected a positive Apple build number.' >&2; exit 1; }
[[ "$audience" == internal || "$audience" == app-store ]] || { echo 'Expected internal or app-store audience.' >&2; exit 1; }
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  echo 'Commit the exact candidate source before archiving.' >&2
  exit 1
fi
candidate_root="$(mktemp -d /tmp/loft-testflight.XXXXXX)"
chmod 700 "$candidate_root"
git -C "$repo_root" rev-parse HEAD > "$candidate_root/SOURCE_SHA"
git -C "$repo_root" archive HEAD > "$candidate_root/source.tar"
mkdir "$candidate_root/source"
tar -xf "$candidate_root/source.tar" -C "$candidate_root/source"
python3 "$repo_root/apple/scripts/provision-distribution.py"
cp /tmp/loft-independent-apple/distribution-profiles.json "$candidate_root/distribution-profiles.json"
python3 - "$candidate_root" "$audience" <<'PY'
from pathlib import Path
import json,sys,plistlib
root=Path(sys.argv[1]);source=root/'source';profiles=json.loads((root/'distribution-profiles.json').read_text())
for product,folder in [('ios','apple'),('tv','tvos')]:
 # Keep the existing browser-auth callback identical to the runtime contract.
 # Public bundle/keychain identity is supplied explicitly to xcodebuild below.
 options={'method':'app-store-connect','teamID':'C7X9BCC7LP','signingStyle':'manual','signingCertificate':'Apple Distribution','provisioningProfiles':{'com.forkzed.leafwake':profiles[product]['uuid']},'uploadSymbols':True,'manageAppVersionAndBuildNumber':False,'testFlightInternalTestingOnly':sys.argv[2]=='internal'}
 (root/(product+'-export.plist')).write_bytes(plistlib.dumps(options))
PY
for product in ios tv; do
  if [[ "$product" == ios ]]; then
    project_folder=apple
    scheme=AudiobookshelfNative
    destination='generic/platform=iOS'
    minimum=(IPHONEOS_DEPLOYMENT_TARGET=15.0)
  else
    project_folder=tvos
    scheme=AudiobookshelfTV
    destination='generic/platform=tvOS'
    minimum=()
  fi
  profile="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]]["uuid"])' "$candidate_root/distribution-profiles.json" "$product")"
  xcodegen generate --spec "$candidate_root/source/$project_folder/project.yml" > "$candidate_root/$product-generate.log"
  xcodebuild -quiet -jobs 2 -project "$candidate_root/source/$project_folder/$scheme.xcodeproj" \
    -scheme "$scheme" -configuration Release -destination "$destination" \
    -archivePath "$candidate_root/$product.xcarchive" -derivedDataPath "$candidate_root/$product-build" \
    PRODUCT_BUNDLE_IDENTIFIER=com.forkzed.leafwake CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' \
    CODE_SIGN_ENTITLEMENTS="$candidate_root/source/apple/AppStore.entitlements" \
    PROVISIONING_PROFILE_SPECIFIER="$profile" ${minimum[@]+"${minimum[@]}"} archive > "$candidate_root/$product-archive.log" 2>&1
  env PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/xcodebuild -quiet -exportArchive -archivePath "$candidate_root/$product.xcarchive" \
    -exportPath "$candidate_root/$product-export" -exportOptionsPlist "$candidate_root/$product-export.plist" \
    > "$candidate_root/$product-export.log" 2>&1
  echo "Prepared $product archive and $audience distribution package."
done
printf '%s\n' "$candidate_root" > /tmp/loft-independent-apple/latest-candidate-path
printf 'Candidate: %s\n' "$candidate_root"
