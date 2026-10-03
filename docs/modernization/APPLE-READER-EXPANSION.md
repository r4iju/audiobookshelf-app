# Apple reader expansion, October 3

The Oct 3 reader amendment requires EPUB, MOBI/AZW3 and CBZ/CBR on iPhone/iPad. Merged PR #145 (`d306de24`, reviewed source `83fc39c1`) extends the existing EPUB host and retains PDFKit. The owner checkout, installed legacy identity and production server are unchanged.

## Behavior

Primary and supplementary server/downloaded files open through the existing native controls. EPUB uses the retained EPUB.js renderer; MOBI/KF8 uses pinned MIT foliate-js; CBZ uses retained JSZip; actual RAR CBR uses locally bundled libarchive WASM. Parser sources, version hashes and upstream license notices are retained under `apple/ReaderEngine` and `ReaderAssets`. No runtime CDN, conversion service or DRM removal is used. Encrypted MOBI and RAR entries are rejected.

Contents, text search, typography/themes and comic page/width fit use native sheets. ComicInfo metadata is optional. Panels must decode before location publication. MOBI locations use the browser-compatible `mobi:1:section:block` contract; comics retain numeric pages. ReadingStore and migration adoption now accept all six formats. Unknown or malformed locations remain saved until explicit reading navigation, including PDF and EPUB. Account ownership, pending listening and original source/export files remain preserved.

## Scoped validation

Private retained evidence: `/Volumes/ai-ssd/code/audiobookshelf-delivery/2026-10-03/reader-expansion/apple/`.

- Meaningful RED: missing format opening controls; unknown EPUB navigation; missing reader migration positions; malformed EPUB/PDF positions; unknown PDF overwritten without warning. Logs: `red-formats.log`, `red-unknown-location.log`, `red-migration.log`, `red-invalid-migration.log`, `red-pdf-unknown.log`.
- iPhone `iphone-final.log`: eight journeys passed, actual MOBI/AZW3 authored chapter content, decoded ZIP/RAR panels, chapter/page navigation, settings, saved location, downloaded offline relaunch, existing EPUB and PDF/audio paths. A shell edit during that run caused a trailing harness parse error after all eight passed; later focused runs used the final valid harness.
- iPhone `green-pdf-unknown.log`: unknown PDF preservation and existing PDF/audio passed. EPUB unknown-location RED was fixed by clearing its native warning after relocation, avoiding an EPUB.js viewport-resize reset; `green-unknown-location.log` passed.
- iPad `ipad-final.log`: four journeys passed, MOBI, AZW3, CBR and unknown EPUB. Shared CBZ container presentation and existing unchanged iPad evidence are retained rather than broadly repeated.
- Migration `green-invalid-migration.log`: all six formats, malformed locations, adoption/reopen, export/source digests and previous PDF/EPUB/CBZ association expectations passed. `green-migration-final.log` also retains progress-reset isolation.
- Localization: 18 package tests passed; generated tables are current and every supported language has entries. New translations are machine drafted, without native-speaker certification.
- Manual supplementary CBZ opened decoded Panel 1 while synthetic audio advanced from 42 to 50 seconds; next page decoded Panel 2. Native fit-width selection and ComicInfo Title/Writer appeared. `cbz-supplementary-with-audio.png` retained.

## Bounded readiness checks

The native Files picker displayed our production-shaped synthetic `Acceptance.absmigration` as one package. Selecting it initially dismissed without preflight twice. Removing the SwiftUI onDismiss cancellation fixed the delegate race; the non-dismissable picker delegate now owns selection/cancellation. Preflight showed four accounts and 13 available files. Moving only our selected source out of reach caused a recoverable incomplete-export message. Restoring and reselecting completed import, retaining seven reading positions and unsent records. Screenshots: `picker-preflight.png`, `picker-unavailable.png`, `picker-imported.png`. This simulates unavailable access, not iCloud/provider revocation certification.

One post-sign-in Arabic catalog/details/player/settings walk completed at `accessibility-extra-extra-extra-large` on the leased iPhone. RTL controls, scrolling, seek and play worked; observed elapsed advanced 33 to 34 seconds with Pause available. Screenshots `arabic-*-large.png`. English book metadata/library names come from the fixture. Long titles truncate in the catalog and full details remain reachable. No product sign-in failure reproduced with the correctly ad hoc signed build; an unsigned manual build caused genuine Keychain -34018 and was replaced with the required entitled build. This is simulator software evidence, not physical assistive-technology or native-speaker approval.

## Delivery limits

Local signed internal preview retains its separate bundle identity and existing profile. Fresh independent review cleared the source before merge. Root signed and delivered the reviewed package (SHA-256 `55edc3e95e000ad783b3adfbb305441b15aa33c1652f524e93bf37b6762068da`) and installed it on both paired iPhone and iPad without launch or reset. Apple/tvOS inputs are unchanged between reviewed and merged source. See [Final readiness](FINAL-READINESS.md). Real-owner migration/cutover, hardware audio routes and iCloud/provider behavior remain unverified physical evidence. iOS 14 runtime remains unavailable; Xcode 27 uses the existing build-only iOS 15 override. Legacy retirement or identity replacement is not authorized by these results.

Reproduce scoped reader journeys with `apple/scripts/run-expanded-readers.sh`; fixture generation uses locally installed calibre and rar. Do not target owner production as a mutation fixture.
