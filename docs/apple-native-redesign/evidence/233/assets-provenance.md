# Native233 Assets.car provenance (read-only)

Observed checkout HEAD: `d82e2e28ded94c9cdc773bdb4cadb350b05a3a28`; final captured runtime source: `8739a7b49b43a11950981eae7ffeb162c43d1ce0`. No source/docs/index/commits/signatures/apps/devices/fixtures were changed by this investigation. Both leased devices are now Shutdown; `simctl get_app_container` returned error405, so inspection uses the exact installed paths recorded during capture, which still exist on disk.

## Finding

The phone/current product contain a phone-thinned Assets.car produced at02:45:09 UTC, after the tablet-source8739 app signing at02:43:10 UTC. Both retain the identical signature manifest from that earlier signing. The manifest seals the tablet Assets.car, not the later phone archive. The final phone test build explicitly compiles/links that thinned archive and has no app CodeSign task. The installed phone archive exactly matches this intermediate/product archive; this is evidence of stale incremental resource sealing when changing simulator destinations in shared DerivedData, not a simulator-install-only thinning discrepancy. No concurrent compile/sign race is established by the recorded logs; the visible tasks/timestamps are sequential. The precise Xcode dependency/signing scheduling cause is not proven.

## Exact files

| Bundle | File | SHA256 | Bytes | mtimeUTC |
| --- | --- | --- | --- | --- |
| phone | Assets.car | `8e417ab3363232345a9e00358274a3c1e66fd4aa949c37c182a0c14d9e9cad5c` | 28184 | 2026-10-08T02:45:09.953917+00:00 |
| phone | _CodeSignature/CodeResources | `aef7681b71991cbd3570c6b4a10d04757d58ed8b4d32f5dacd763b7e3938e833` | 15597 | 2026-10-08T02:43:10.967554+00:00 |
| phone | AudiobookshelfNative | `776ba0e107b88c845d66af87a9f979f45f01c481714d2d0976955a64594ba2ea` | 40512 | 2026-10-08T02:43:10.968361+00:00 |
| phone | AudiobookshelfNative.debug.dylib | `0554dc289b4c372ea0ed21b4a0729ab6cddd3a154ec905ec095dc93faa13a490` | 21645104 | 2026-10-08T02:43:10.918396+00:00 |
| tablet | Assets.car | `d996c2b3e811be30afce3be7de015bca172ee6b634d40c13bf8f6a20e0053b2a` | 29096 | 2026-10-08T02:40:07.380017+00:00 |
| tablet | _CodeSignature/CodeResources | `aef7681b71991cbd3570c6b4a10d04757d58ed8b4d32f5dacd763b7e3938e833` | 15597 | 2026-10-08T02:43:10.967554+00:00 |
| tablet | AudiobookshelfNative | `776ba0e107b88c845d66af87a9f979f45f01c481714d2d0976955a64594ba2ea` | 40512 | 2026-10-08T02:43:10.968361+00:00 |
| tablet | AudiobookshelfNative.debug.dylib | `0554dc289b4c372ea0ed21b4a0729ab6cddd3a154ec905ec095dc93faa13a490` | 21645104 | 2026-10-08T02:43:10.918396+00:00 |
| build | Assets.car | `8e417ab3363232345a9e00358274a3c1e66fd4aa949c37c182a0c14d9e9cad5c` | 28184 | 2026-10-08T02:45:09.953917+00:00 |
| build | _CodeSignature/CodeResources | `aef7681b71991cbd3570c6b4a10d04757d58ed8b4d32f5dacd763b7e3938e833` | 15597 | 2026-10-08T02:43:10.967554+00:00 |
| build | AudiobookshelfNative | `776ba0e107b88c845d66af87a9f979f45f01c481714d2d0976955a64594ba2ea` | 40512 | 2026-10-08T02:43:10.968361+00:00 |
| build | AudiobookshelfNative.debug.dylib | `0554dc289b4c372ea0ed21b4a0729ab6cddd3a154ec905ec095dc93faa13a490` | 21645104 | 2026-10-08T02:43:10.918396+00:00 |

phone exact path: `/Users/emanuel/Library/Developer/CoreSimulator/Devices/75FA9768-B15C-40B6-ACC7-790D7FCAD29C/data/Containers/Bundle/Application/46CCB928-E135-4C1C-9FE0-C85A87F3FFB9/AudiobookshelfNative.app`
Manifest Assets.car hash2 `d996c2b3e811be30afce3be7de015bca172ee6b634d40c13bf8f6a20e0053b2a`; legacySHA1 `a06fb2d5b450ccf409bca7965cabc87b7b0d6f2d`. ActualSHA1 `9e13a5057b28b35190d4102232a5989dd3dce984`.
files2 hash2 verification mismatches: ['Assets.car']
`codesign --verify --verbose=4` exit1:
```
file modified: /Users/emanuel/Library/Developer/CoreSimulator/Devices/75FA9768-B15C-40B6-ACC7-790D7FCAD29C/data/Containers/Bundle/Application/46CCB928-E135-4C1C-9FE0-C85A87F3FFB9/AudiobookshelfNative.app/Assets.car
/Users/emanuel/Library/Developer/CoreSimulator/Devices/75FA9768-B15C-40B6-ACC7-790D7FCAD29C/data/Containers/Bundle/Application/46CCB928-E135-4C1C-9FE0-C85A87F3FFB9/AudiobookshelfNative.app: a sealed resource is missing or invalid
```


tablet exact path: `/Users/emanuel/Library/Developer/CoreSimulator/Devices/CDFFEB30-07F5-4A50-AB64-57A46709335B/data/Containers/Bundle/Application/442BE845-116D-4B49-88CB-63395477F284/AudiobookshelfNative.app`
Manifest Assets.car hash2 `d996c2b3e811be30afce3be7de015bca172ee6b634d40c13bf8f6a20e0053b2a`; legacySHA1 `a06fb2d5b450ccf409bca7965cabc87b7b0d6f2d`. ActualSHA1 `a06fb2d5b450ccf409bca7965cabc87b7b0d6f2d`.
files2 hash2 verification mismatches: []
`codesign --verify --verbose=4` exit0:
```

/Users/emanuel/Library/Developer/CoreSimulator/Devices/CDFFEB30-07F5-4A50-AB64-57A46709335B/data/Containers/Bundle/Application/442BE845-116D-4B49-88CB-63395477F284/AudiobookshelfNative.app: valid on disk
/Users/emanuel/Library/Developer/CoreSimulator/Devices/CDFFEB30-07F5-4A50-AB64-57A46709335B/data/Containers/Bundle/Application/442BE845-116D-4B49-88CB-63395477F284/AudiobookshelfNative.app: satisfies its Designated Requirement
```


build exact path: `/Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app`
Manifest Assets.car hash2 `d996c2b3e811be30afce3be7de015bca172ee6b634d40c13bf8f6a20e0053b2a`; legacySHA1 `a06fb2d5b450ccf409bca7965cabc87b7b0d6f2d`. ActualSHA1 `9e13a5057b28b35190d4102232a5989dd3dce984`.
files2 hash2 verification mismatches: ['Assets.car']
`codesign --verify --verbose=4` exit1:
```
file modified: /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app/Assets.car
/Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app: a sealed resource is missing or invalid
```


phone assetutil metadata:
```json
{
  "Appearances": {
    "UIAppearanceAny": 0,
    "UIAppearanceDark": 1
  },
  "AssetStorageVersion": "Xcode 27.0 (27A266a) via AssetCatalogAgent-AssetRuntime",
  "Authoring Tool": "@(#)PROGRAM:CoreThemeDefinition  PROJECT:CoreThemeDefinition-664 [LAR] [IIO-2851][LAR] AppleJPEG[1][32]  CMPhoto[1][219]] [IR-120(hw)]",
  "CoreUIVersion": 1010,
  "DumpToolVersion": 1010,
  "Key Format": [
    "kCRThemeAppearanceName",
    "kCRThemeLocalizationName",
    "kCRThemeScaleName",
    "kCRThemeIdiomName",
    "kCRThemeSubtypeName",
    "kCRThemeDimension2Name",
    "kCRThemeDimension1Name",
    "kCRThemeIdentifierName",
    "kCRThemeElementName",
    "kCRThemePartName"
  ],
  "MainVersion": "@(#)PROGRAM:CoreUI  PROJECT:CoreUI-1010 [LAR]",
  "Platform": "ios",
  "PlatformVersion": "15.0",
  "SchemaVersion": 2,
  "StorageVersion": 17,
  "Thinning With CoreUI Version": 2147483647,
  "ThinningParameters": "optimized <idiom 1> <subtype 2622> <scale 3> <gamut 1> <graphics 11> <graphicsfallback (10,9,8,7,6,5,4,3,2,1,0)> <memory 8> <deployment 13> <hostedIdioms (4)>",
  "Timestamp": 1791427509
}
```
Rendition names/types: [('AccentColor', 'Color', 'universal', 1), ('AccentColor', 'Color', 'universal', 1), ('AppIcon', 'Icon Image', 'phone', 3), ('AppIcon', 'Icon Image', 'phone', 3), ('AppIcon', 'Icon Image', 'phone', 3), ('AppIcon', 'Icon Image', 'phone', 3), ('AppIcon', 'MultiSized Image', 'phone', 1), ('ZZZZPackedAsset-3.1.0-gamut0', 'PackedImage', 'phone', 3), ('ZZZZPackedAsset-3.1.0-gamut0', 'PackedImage', 'phone', 3)]

tablet assetutil metadata:
```json
{
  "Appearances": {
    "UIAppearanceAny": 0,
    "UIAppearanceDark": 1
  },
  "AssetStorageVersion": "Xcode 27.0 (27A266a) via AssetCatalogAgent-AssetRuntime",
  "Authoring Tool": "@(#)PROGRAM:CoreThemeDefinition  PROJECT:CoreThemeDefinition-664 [LAR] [IIO-2851][LAR] AppleJPEG[1][32]  CMPhoto[1][219]] [IR-120(hw)]",
  "CoreUIVersion": 1010,
  "DumpToolVersion": 1010,
  "Key Format": [
    "kCRThemeAppearanceName",
    "kCRThemeLocalizationName",
    "kCRThemeScaleName",
    "kCRThemeIdiomName",
    "kCRThemeSubtypeName",
    "kCRThemeDimension2Name",
    "kCRThemeDimension1Name",
    "kCRThemeIdentifierName",
    "kCRThemeElementName",
    "kCRThemePartName"
  ],
  "MainVersion": "@(#)PROGRAM:CoreUI  PROJECT:CoreUI-1010 [LAR]",
  "Platform": "ios",
  "PlatformVersion": "15.0",
  "SchemaVersion": 2,
  "StorageVersion": 17,
  "Thinning With CoreUI Version": 2147483647,
  "ThinningParameters": "optimized <idiom 2> <subtype 2420> <scale 2> <gamut 1> <graphics 11> <graphicsfallback (10,9,8,7,6,5,4,3,2,1,0)> <memory 12> <deployment 12> <hostedIdioms *>",
  "Timestamp": 1791427207
}
```
Rendition names/types: [('AccentColor', 'Color', 'universal', 1), ('AccentColor', 'Color', 'universal', 1), ('AppIcon', 'Icon Image', 'pad', 2), ('AppIcon', 'Icon Image', 'pad', 2), ('AppIcon', 'Icon Image', 'pad', 2), ('AppIcon', 'Icon Image', 'pad', 2), ('AppIcon', 'Icon Image', 'pad', 2), ('AppIcon', 'MultiSized Image', 'pad', 1), ('ZZZZPackedAsset-2.1.0-gamut0', 'PackedImage', 'pad', 2), ('ZZZZPackedAsset-2.1.0-gamut0', 'PackedImage', 'pad', 2)]

AccentColor renditions are identical across phone/tablet: True. Differences are native phone/tablet icon thinning and packed-image renditions, not authored UI imagery or changed color values. This source catalog contains only AppIcon, AccentColor and Contents.json; the actual book art in the captures is the separately generated231 synthetic fixture artwork.

## Source asset identity

`git diff --name-status 23174ab0 8739a7b4 -- apple/App/Assets.xcassets` returned no changes. Every current tracked asset file equals its8739 Git blob:

| Source file | SHA256 | Equals8739 blob |
| --- | --- | --- |
| apple/App/Assets.xcassets/AccentColor.colorset/Contents.json | `4d661e607dfa5357ae831f9ea1b750a3ab5c408cb848be8b9799eb21ebcfe55f` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Contents.json | `8419bc1dcd969cef058247e3b03a6369a8c525d0b0893ad7bc2678f989c33e1e` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ios-marketing-1024-1x.png | `e6e50179e1df1358d5234da68ca00c09e879d27f7e98efbc1fc189a494f73b74` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-20-1x.png | `16a2123c57ffec8989ac571303e41c30b36f38dee922a00f1a95a6a300e3b198` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-20-2x.png | `6b50757f8287733f56d60faa95132a2a082738fbe23c61a6a09a6d2b0cd2f5b8` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-29-1x.png | `7527b214baf468060bf2e370f3dbfa79c676a92aeaeef57b1fd8cf2df388e1ac` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-29-2x.png | `31fa64bcfc37c53049c5f7010ce2e7fa826ab95770bdb861c810521f9b354ff4` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-40-1x.png | `6b50757f8287733f56d60faa95132a2a082738fbe23c61a6a09a6d2b0cd2f5b8` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-40-2x.png | `78bec65813ab462016759bf2a78ba987da66f299b06eadcd6c7ea3c1fa53fbbe` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-76-1x.png | `db9b63c9c9c2da8b9c7c9cdf06745130808122062d5e99e265e87f26bbee5ea2` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-76-2x.png | `54233622418e2aee6808054bf6a0d8bdcea3ca03f0fa6ad9e2414dce76c4389e` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-ipad-83.5-2x.png | `a24053d5231fddcd5cbe318daaacede395fbf960a99173eb25082942d10c4500` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-20-2x.png | `6b50757f8287733f56d60faa95132a2a082738fbe23c61a6a09a6d2b0cd2f5b8` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-20-3x.png | `3fd46eb7f8bf541577eafca90dca9349ccaf1f8179eab37a76a5f89774f965ec` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-29-1x.png | `7527b214baf468060bf2e370f3dbfa79c676a92aeaeef57b1fd8cf2df388e1ac` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-29-2x.png | `31fa64bcfc37c53049c5f7010ce2e7fa826ab95770bdb861c810521f9b354ff4` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-29-3x.png | `273cb3d4cbf6f912ef3afdd4befa37254d4c9f3f9ffcde239778cae874ad2ff7` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-40-2x.png | `78bec65813ab462016759bf2a78ba987da66f299b06eadcd6c7ea3c1fa53fbbe` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-40-3x.png | `15ab44025673faa562ccb81071562ba6131db7babcb52ee25b66e78e0c35c0a9` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-60-2x.png | `15ab44025673faa562ccb81071562ba6131db7babcb52ee25b66e78e0c35c0a9` | True |
| apple/App/Assets.xcassets/AppIcon.appiconset/Icon-iphone-60-3x.png | `537db21759e100cdb313bd9040eb93c15c4220fbd8878ec05cd5c5582d83c480` | True |
| apple/App/Assets.xcassets/Contents.json | `3068ae11b833a8ea03990d2ea2a2b5fe7b3c47fbda56de956a4b84888f6c6af8` | True |

Current thinned intermediate `/Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Intermediates.noindex/AudiobookshelfNative.build/Debug-iphonesimulator/AudiobookshelfNative.build/assetcatalog_output/thinned/Assets.car` SHA256 `8e417ab3363232345a9e00358274a3c1e66fd4aa949c37c182a0c14d9e9cad5c`, exactly equals phone/product.

## Build log provenance and commands

Read-only commands used: `git status --short`, `git rev-parse HEAD`, `git diff --name-status 23174ab0 8739a7b4 -- apple/App/Assets.xcassets`, `git ls-tree -r --name-only 8739a7b4 -- apple/App/Assets.xcassets`, `git show 8739a7b4:<eachasset>`, Python hashlib/plistlib/stat reads, `/usr/bin/assetutil --info <bundle>/Assets.car`, `codesign --verify --verbose=4 <bundle>`, and `rg`/line reads of existing logs. Initial read-only `simctl get_app_container` failed Shutdown405; no boot/install/re-sign attempted.

### /tmp/233-ipad-dismiss-green.log

Relevant exact lines:
```
121: CodeSign /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app/AudiobookshelfNative.debug.dylib (in target 'AudiobookshelfNative' from project 'AudiobookshelfNative')
128: CodeSign /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app/__preview.dylib (in target 'AudiobookshelfNative' from project 'AudiobookshelfNative')
136: CodeSign /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app (in target 'AudiobookshelfNative' from project 'AudiobookshelfNative')
380: 2026-10-08 11:43:49.726 xcodebuild[15518:49520477] [MT] IDETestOperationsObserverDebug: 38.704 elapsed -- Testing started completed.
387: ** TEST SUCCEEDED **
```
App CodeSign task count: 1.

### /tmp/233-phone-final-2.log

Relevant exact lines:
```
42: CompileAssetCatalogVariant thinned /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app /Volumes/ai-ssd/code/leafwake-fullstack/apple/App/Assets.xcassets (in target 'AudiobookshelfNative' from project 'AudiobookshelfNative')
44:     /Applications/Xcode.app/Contents/Developer/usr/bin/actool /Volumes/ai-ssd/code/leafwake-fullstack/apple/App/Assets.xcassets --compile /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Intermediates.noindex/AudiobookshelfNative.build/Debug-iphonesimulator/AudiobookshelfNative.build/assetcatalog_output/thinned --output-format human-readable-text --notices --warnings --export-dependency-info /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Intermediates.noindex/AudiobookshelfNative.build/Debug-iphonesimulator/AudiobookshelfNative.build/assetcatalog_dependencies_thinned --output-partial-info-plist /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Intermediates.noindex/AudiobookshelfNative.build/Debug-iphonesimulator/AudiobookshelfNative.build/assetcatalog_generated_info.plist_thinned --app-icon AppIcon --accent-color AccentColor --compress-pngs --enable-on-demand-resources YES --filter-for-thinning-device-configuration iPhone18,3 --filter-for-device-os-version 27.0 --development-region en --target-device iphone --target-device ipad --minimum-deployment-target 15.0 --platform iphonesimulator
57: note: Emplaced /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app/Assets.car (in target 'AudiobookshelfNative' from project 'AudiobookshelfNative')
58: note: Emplaced /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app/AppIcon60x60@2x.png (in target 'AudiobookshelfNative' from project 'AudiobookshelfNative')
59: note: Emplaced /Volumes/ai-ssd/code/leafwake-fullstack/apple/build/Build/Products/Debug-iphonesimulator/AudiobookshelfNative.app/AppIcon76x76@2x~ipad.png (in target 'AudiobookshelfNative' from project 'AudiobookshelfNative')
928: 2026-10-08 11:47:49.917 xcodebuild[24261:49543269] [MT] IDETestOperationsObserverDebug: 159.921 elapsed -- Testing started completed.
935: ** TEST SUCCEEDED **
```
App CodeSign task count: 0.

## Confidence, next action, and capture mapping

Runtime executable SHA256 and debug-library SHA256 are identical in the installed phone/tablet and current build product. The tablet bundle verifies against the same CodeResources manifest. Source8739 asset blobs remain unchanged, the phone compiler invocation points directly to those assets, the archive equals its thinned intermediate, and AccentColor renditions are identical. This establishes bounded source/runtime confidence for the13 actual captures; it does not make the phone resource seal valid or establish a fresh signed final candidate.

A clean isolated DerivedData build from committed8739, explicitly for the phone simulator with ad hoc signing, followed by bundle verification BEFORE installation, is the appropriate bounded follow-up to prove the stale-incremental diagnosis and produce a valid candidate. It is not necessary to identify the present exact hash mismatch; it IS needed if claiming a clean verified bundle from8739. Parent must sequence that work after the active independent review. No build/install or re-sign was performed here. Use distinct per-destination DerivedData to avoid cross-destination thinning reuse. Later240 still requires fresh final-candidate signature verification and required checks at its eventual source commit.

Preserve all13 captures as actual historical source8739 evidence with their recorded installed runtime hashes and resource-verification caveat. Do not relabel them as from a future clean signed binary, replace hashes, or claim the phone signature passed. If a later clean build is captured, record separate source/build/hash/time entries and label new images; app-code equality alone does not justify treating two whole bundles as identical.

No broad suite replay is indicated by this provenance-only investigation. The final phone6/6 and tablet Shell1/1 records remain their actual original executions, independent rendered round2 remains pending.
