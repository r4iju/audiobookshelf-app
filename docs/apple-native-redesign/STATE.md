# Native Apple redesign integration state

Integration branch: `feature/apple-native-redesign`, based on `77c154b1` on `fork/native-tv`. [Draft integration PR #241](https://github.com/r4iju/audiobookshelf-app/pull/241). Spec #230 and historical spec #222 remain unchanged. Source, Android, web and backend scope boundaries follow SPEC.md. One shared source writer runs at a time.

| Ticket | Integration | Evidence / remaining work |
| --- | --- | --- |
| #231 | Source `0894eb04`, evidence `f1116e66`, verified integrated | [Actual phone/tablet slice and checks](evidence/231/RESULT.md). Functional final-source phone 3/3, iPad shell 1/1 and bookmark 1/1. Full design acceptance remains #233. |
| #232 | Source `cb8ebda8` + `5acca8c1`, evidence `5f48fdd0`, verified integrated | [Bounded TV shell, remote checks and focused/unfocused captures](evidence/232/RESULT.md). Final source 4/4; earlier 10/10. |
| #233 | Corrections integrated `da05a80a` + `8739a7b4`, evidence `a8e2e6d0`; independent round2 PASS | [Fresh rendered review](evidence/233/review-round-2.md) resolved D1–D3 and permits broad migration. [Actual corrected renders/checks](evidence/233/corrections-round-1/RESULT.md): final phone6/6 and wide-iPad Shell1/1. [TV portrait focus pair](evidence/233/corrections-round-1/tv-portrait/RESULT.md) captured. [Asset provenance](evidence/233/assets-provenance.md) identifies stale incremental resource sealing; clean separately verified candidates remain required. |
| #234 | Runtime `b7038ddc`, test locators `c04f6d97`, evidence `a5888ff3`, verified integrated | [Catalog/discovery result](evidence/234/RESULT.md): scoped phone15/15, iPad3/3, server actions4/4, progress reset4/4, related4/4 and group playback1/1. Final31 actual renders use separately built, strictly verified bundles. Historical test scopes are explicit; complete visual/accessibility acceptance remains239. |
| #235 | Runtime `0b4733e6`, evidence `ffa1ec59`, verified integrated | [Listening result](evidence/235/RESULT.md): phone14/14 and tablet4/4 retain explicit pre-freeze display-only scope; final-source auth1/1, fresh builds and37 renders pass. Both isolated products independently strictly verified; all capture/resource hashes match. Final adaptive/accessibility acceptance remains239. |
| #236 | Runtime `9093bdf9` + `ddad921f`, test locators `f32f43ca`, evidence `5c0e2d57`, verified integrated | [Readers, downloads, feeds and groups](evidence/236/RESULT.md). 111 original captures: 56 final, 53 explicitly unaffected earlier compositions and 2 historical corrections. Scoped reader/group/feed/offline checks retain their exact sources. Both final products and installed bundles independently strictly verified; all47 resources and111 capture hashes match. Final full acceptance remains239. |
| #237 | Ready frontier, next sole mobile writer | Accounts, utilities, authoritative preferences and complete localization. |
| #238 | Ready frontier, queued behind sole mobile writer | Complete TV screens and remote journeys. |
| #239 | Blocked by #237/#238 | Required adaptive, accessibility, fallback and full-screen acceptance. |
| #240 | Blocked by #239 | Final review, merge, merged-source QA and private device candidates. |

## Acceptance capability findings, October 8

- A real iPadOS26 native Windowed Apps resize and restore passed through device-only SpringBoard input. The actual window shrank from834x1210 to375x605. Native Back, keyboard typing/submission, Clear and wide restore were activated. `/tmp/native-compact-pad26/RESULT.md` preserves source `0b4733e6`, actual geometry/actions and originals. This supersedes the earlier locked-desktop probe. App-bound T3 accessibility frame clipping required screenshot-grounded global device input.
- That probe confirmed two ticket239 defects: fallback compact-player overlap with native tabs, and a Search drawer remaining on Library whose submitted query fetched results without presenting them. Full final-source compact journeys remain pending. One pause attempt was inconclusive, not a product failure or accepted pass.
- Physical iPhone VoiceOver was unavailable during the October8 locked-device capability check. Actual spoken traversal remains pending; snapshots/audits cannot substitute. A documented bounded recording route exists, but audio inclusion and speech assessment have not been verified. No owner device state was changed.
- Xcode27 rejects minimum-iOS14 builds before compilation. Full current Swift source typechecks targeting14, but that proves neither a supported binary nor execution. SDK27 minimum-tvOS17 builds likewise do not prove runtime17 behavior.
- The official macos14 arm64 runner inventory includes Xcode15.0.1 and tvOS17 runtimes. Revised source-pinned build/replay capability files under `/tmp/native-older-ci-preparation/` passed preparation schema, method and syntax checks, but have not been committed or run. Ticket239 must attempt the installed TV17 route and separate official iOS14.5 runtime experiment after newer-SDK compilation guards. Local Apple runtime authorization failures do not establish a final TV17 blocker.
- `/tmp/native-sdk-capability-contract.md` describes target-level SDK-derived compilation conditions, prebuild validation and source sentinels. It remains a proposal, not an implemented contract. Original platform minimums must remain intact.
- The iOS14 runtime catalog's host limit conflicts with the proposed Xcode15 runner host. Only an actual stock official import/boot attempt can resolve that capability. No runtime patch, mirror or unsupported bypass is authorized.

These are pending requirements, not accepted skips. Finish independent implementation and available verification before declaring any final blocker. Keep the integration PR draft until required gates pass. Public Apple uploads and Cast remain outside this work and rights-gated.

## Confirmed presentation follow-up

Ticket239 must remediate the malformed extreme-duration caption exposed by the stock `edge-metadata` fixture: saturation produces an enormous numeric caption rather than meaningful duration information. Ticket234's valid20s long-title captures do not waive that defect; the stock robustness test remains unchanged. No media/domain value was rewritten by the app.
