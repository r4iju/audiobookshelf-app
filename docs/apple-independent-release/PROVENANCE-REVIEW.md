# Independent Apple release provenance review

Reviewed checkout: `c7c8538924246050906efcd48dfcd70d57d3b05d`.
Local upstream reference: `upstream/master` at `7014e04e6febcc5fd326e816a57b1065817e85f5`.
Read-only review, no signing, uploading, license changes, device changes or external contact.

## Finding

The configured Apple applications are native rewrites, not the former Capacitor/Realm application. There is no evidence here that the backend must be rewritten again or that the complete native implementation must be replaced. However, the current release resources demonstrably retain inherited upstream translations. The independent-code release route cannot be represented as already complete merely because native Swift was introduced by a fork commit.

## Actual release inputs

`apple/project.yml` production target includes App (with ReaderAssets as resource folder), Presentation, Playback, Export/Sources/YearExport, Localization/Sources/NativeLocalization, Diagnostics/Sources/NativeDiagnostics, Adoption, ../tvos/Core/Sources/TVCore, and Migration/Sources/LegacyMigration.

`tvos/project.yml` includes App, ../apple/Presentation, ../apple/Playback, Core/Sources/TVCore, ../apple/Localization/Sources/NativeLocalization and ../apple/Diagnostics/Sources/NativeDiagnostics.

Across those unique roots there are 183 current source/resource files. Tests are separate targets. Neither production YAML declares a third-party package dependency. Generated application PBXNativeTarget packageProductDependencies are empty; no Realm/Capacitor/Google Cast/Socket.IO package import was found in those roots. Framework imports are Apple frameworks. Reader JavaScript is the explicit iOS exception described below.

### Legacy Realm exclusions

`apple/Migration/LegacyRealm/Tests/LegacyAppCompatibilityTests/LegacyAppModels/README.md` explicitly records that its models were copied unchanged from former `ios/App/Shared/models` at `4b9a6396`, GPLv3 retained. All of that test-model tree is outside both production source roots. Likewise `apple/Migration/LegacyRealm/Sources/LegacyRealmExport` and its RealmSwift10.54.6 package are not part of either production application. They are an isolated export/compatibility implementation. `Migration/Sources/LegacyMigration` IS included on iOS, but consists of the new Codable migration package/readers and filesystem machinery, not the copied Realm model declarations. Preserve GPL notices for the isolated historical fixtures; their presence elsewhere in the repository does not establish that they are linked into these apps.

## Native implementation history and comparisons

- Native TV source/Core was first introduced in `1a6734636352e64b885451f368220be23877ccab`, "Add native tvOS client and deployment tooling", October1.
- Native phone connection application was introduced in `58f627b6e3286d5e3d1a470190a4f70f41f6fe39`, "Add native Apple connection preview with secure session restoration", October1.
- Shared Playback/ApplePlayback began with `6b0d1c72`, "Share Apple playback service and preserve pending seek and pause intent".
- The local APIClient and models have subsequent feature/compatibility history, rather than upstream path continuity. Endpoint names, JSON field names and saved schema names are interoperability evidence, not by themselves evidence of copying executable expression.

Independent scanner checked every current production-root file blob against every file blob in upstream/master: zero byte-identical upstream files. It also checked every production Swift file against every upstream Swift file for exact sequences of eight nonblank, trimmed lines with aggregate length >200characters: zero matches. Proof data is `/tmp/apple-provenance-match-scan.json`. This bounded mechanical comparison DOES NOT prove clean-room authorship, catch translated/structurally adapted code, or establish ownership from Git author alone. Authorship/source records for the fork's newly created implementation remain relevant. I found no positive substantive copied-Swift match in this review.

## Confirmed inherited expression: localization

`apple/Localization/generate.py` lines4–8 explicitly says other languages carry legacy translations from `strings/<code>.json` and maintained translations are refused where a legacy translation exists. Lines163–177 load `legacy-equivalents.json`, root English legacy keys and each legacy locale file, then directly assign the legacy value to the native key. The generated .strings resources are compiled into BOTH apps. Commits `e8a7aff3`, `89cc6071`, and `01d91bc7` explicitly describe preserving legacy translations for native actions, themes/haptics, and podcast sorting.

`apple/Localization/COVERAGE.md` records740 native texts and171 mappings to legacy text per locale, with up to171 carried-over translations. An independent comparison of generated resource values with local upstream/master's root strings files found4,814 exact inherited translated entries across29 non-English locales (excluding identity English labels). This is not merely matching generic button names: for example, German carries the original long sentence explaining seeking through notification media controls; French carries the original progress-discard confirmation. Full counted proof and bounded examples are in `/tmp/apple-provenance-translation-scan.json`.

This is the concrete replacement scope for the independent-code route. Replace the legacy-backed mapped translations with independently produced text (or intentionally ship English for unavailable translations), cease importing root legacy strings for native resource generation, and record translation provenance. Existing maintained translations must also have their authoring provenance confirmed; their new path/commit alone is not conclusive. Do not silently relabel the existing inherited strings permissive.

## Assets

Native phone and TV asset catalogs first appear in fork history, not upstream/master. Programmatic generators `apple/scripts/generate-assets.swift` and `tvos/scripts/generate-assets.swift` draw the book-spine artwork using AppKit shapes and colors. Phone icon generator was added with `af7f8b84` and corrected to opaque images in `c8bfc20c`; TV generator begins with `1a673463`. None of the current production asset files is byte-identical to upstream files. This establishes a plausible independent construction path, not a visual/trademark-clearance opinion or proof that all resulting PNGs were generated unmodified by those scripts. I did not open/capture images under the current screenshot stop instruction. Retain an owner-controlled creation record for the generated artwork and avoid implying upstream endorsement.

## Reader dependencies

`apple/App/ReaderAssets/VENDOR-PROVENANCE.txt` explicitly discloses assets copied from checkout dependency distributions: EPUB.js0.3.88 and JSZip3.10.1. Copying permissively licensed third-party dependencies is not equivalent to copying Audiobookshelf GPL application code.

- EPUBJS-LICENSE is the supplied FuturePress two-clause BSD-style permission, NOT MIT. It permits binary redistribution with reproduced copyright, conditions and disclaimer.
- JSZIP-LICENSE and the distribution header offer MIT OR GPLv3. The independent route can choose MIT, retaining its copyright/license.
- THIRD-PARTY-NOTICES includes MIT, ISC and Apache2 notices for embedded core-js, event-emitter, localforage, lodash, marks-pane, path-webpack, pako, d and es5-ext.
- The provenance file candidly states that local notice-source versions can differ from actual embedded distribution versions. It is therefore not a complete version-resolved SBOM. Confirm the notices for the actual embedded versions from the vendor source-map/package provenance or repin from documented permissive distributions before making an exhaustive dependency assertion.
- Reader shell `reader.js`/`reader.html` begins in fork feature `fe399438`, independent adapter around ePub/WebKit according to history. No whole-file match against upstream/master. The current report does not claim a full cross-language expression comparison.

There is no corresponding bundled reader JavaScript in the TV target.

## Licensing declarations and practical ship scope

Repository root LICENSE is GPLv3; app UI currently says "Open source under GPLv3" in `apple/App/NativeSettings.swift` and `tvos/App/NoticesView.swift`. This is current declared licensing, separate from whether the owner can additionally license genuinely owner-controlled components. An owner-authorized scoped Apple grant can be added only for components whose rights they control, preserving inherited GPL elsewhere and permissive dependency notices. Moving files or replacing a label alone does not change third-party rights.

Suggested smallest concrete route:

1. Remove inherited localization expression from BOTH release resource sets and discontinue the generator's legacy source dependency; preserve supported labels/API compatibility independently.
2. Document owner-controlled native Swift/artwork/maintained-translation provenance and a scope-specific license grant. Do not claim Git authorship alone establishes this.
3. Resolve actual embedded reader-version notices and retain permissive licenses in the shipped package, selecting JSZip MIT explicitly.
4. Ensure all built/archive source/resource inputs match the scoped inventory and exclude legacy Realm fixtures/exporter.
5. Build the separate App Store distribution archive and perform internal TestFlight eligibility/signing checks. No upstream exception wait is necessary for independently owned/permissively licensed input once that separation is real. This review has not uploaded an archive or evaluated Apple account/build eligibility.

No confirmed inherited native playback/backend implementation blocker was discovered. The positive inherited-translation finding and provenance/notice gaps remain unresolved in the reviewed checkout. This is evidence of a bounded separation task, not a license-clearance certification.

## Focused follow-up on the proposed narrow route

The root's proposed elimination of the legacy loader and regeneration using independently maintained translations plus explicit English fallback addresses the confirmed inherited-translation mechanism. It must not preserve inherited translated values merely by copying them into a different maintained file. Partial beta translation can be honestly disclosed without claiming full redesign acceptance.

`ce341069565548ec6db4206c06482909cdf1f045` records maintained translations for native text without a same-meaning usable legacy translation, explicitly without native-speaker review. Current COVERAGE.md says the maintained translations are machine-drafted. The generation rule refuses maintained translations where usable legacy text exists; this is useful evidence that the maintained tree was prepared for new native wording rather than simply a wholesale copy of legacy translation tables. It is not by itself a formal author/rights certification.

English needs a focused expression review, not automatic condemnation: an independent check found zero mapped native English labels longer than55characters that exactly equal the corresponding upstream English values. The mapping documents semantic equivalence, but semantics alone does not establish copied copyright expression. A new fallback should use reviewed native English wording. No positive substantial exact-English copying finding arose from that check.

I additionally inspected original upstream `ios/App/Shared/player/AudioPlayer.swift`, `ios/App/Shared/util/ApiClient.swift` and `components/app/AudioPlayer.vue`. Original playback uses NSObject, Realm model state, a DispatchQueue/rate-manager architecture; original API uses Alamofire callbacks and static Store/SecureStorage. Native playback/client ownership uses MainActor AVPlayer and asynchronous URLSession credential/task generations, with a different architecture. A bounded inspection found no affirmative copied/adapted executable-algorithm sequence. Cross-language derivation cannot be ruled out categorically by a short source audit; I have not inferred a blocker from merely sharing endpoint names, session fields or ordinary AVPlayer behavior.

An explicit owner-code MIT grant scoped to the native compile roots, excluding vendor dependencies and the GPL LegacyRealm tree, with root GPL unchanged and vendor notices retained, is coherent after actual inherited resource removal and owner-authorized provenance documentation. It is not coherent if the exact inherited locale expressions remain in those roots. No evidence found here requires replacing the backend again.
