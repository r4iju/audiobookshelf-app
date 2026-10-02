# Current bounded web candidate, October 3, 2026

This increment starts from merged PR #124, `32c8316fd21f8c4c164b9fd656c64174cd814d1f`.
It finishes the two concrete software gaps recorded below: bookmark creation/current-time marking and missing
in-use translation-table entries. Root inspected the bookmark and source-generator changes without blockers;
**final loader and pinned-PR review remains pending**. Root owns the sole consolidated client-only deployment.
No deployment, image build or new delivery package is performed by this increment.

## Bookmark main flow

The list marks the bookmark at the current whole playback second with a visible check and `aria-current`.
An inline Title field creates a named bookmark directly through the existing server mutation. Blank titles
use the existing chapter/time default; the fast player creation button remains available. Pending and duplicate
current-second creation are disabled. Failed writes retain the typed title and show the existing translated
error; successful writes invalidate the account query, show confirmation and reset the form.

Two production journeys reached playback and failed on the missing current marker and Title field before the
fix. Setup-only failures are retained separately and do not count as RED. The affected four journeys cover
current marking, typed creation/failure/retry with server observation, fast creation/persisted speed, and
list selection/rename/removal. Initial GREEN passed three, then the typed case passed after using deterministic
whole-second seeking (the displayed slider rounds while server bookmarks floor). No mirrored component tests
were added. Fixtures use the existing isolated, unmodified Audiobookshelf 2.30.0 image.

## Maintained translation fallback tables

The catalog is the union of literal in-use `webStrings` and inherited `en-us` keys, including implicit `_one`
variants: **347 entries**, comprising 180 web and 167 inherited entries. Inherited keys are appended so the
web inventory order remains stable. The original 121-unmatched report below remains historical.

Across 29 non-English languages (10,063 language/key slots), 6,271 usable carried values are preserved,
50 exact source-gap values are copied, and 3,742 missing or placeholder-invalid values are machine-drafted.
The inherited gaps total 90 across ca17/he6/ko6/lt34/tr8/vi-vn19. The 50 copies consist of 44 native-table
values and 6 legacy equivalents, including English-identical usable source values. They are distinct from
the existing 26-key native-equivalent allowlist and from the machine drafts. Nine new Apple-key mappings and
seven Android-key mappings are allowlisted, but a mapping is not a copied translation in every language.
No incorrect semantic mapping or distinct-translation count is inferred from coverage.

`web/src/i18n/drafts` contains only actual remaining holes, not replacements for usable originals.
Thirty-eight machine-drafted entries are English-identical (including the product name), reported separately;
they are valid entries, not distinct translated wording. `source-fallbacks/provenance.json` records input/output
SHA-256 hashes and each copy's source/key; `drafts/provenance.json` records the English snapshot and draft
hashes plus per-language coverage. Runtime precedence is draft, exact source gap, then usable legacy/server/native.
Empty or placeholder-invalid carried values cannot hide a usable fallback; originals themselves are unchanged.

`python3 web/scripts/import-web-gap-sources.py` regenerates exact copies. `npm --prefix web run i18n:validate`
checks source hashes, the reviewed English snapshot, exact needed/stale key sets, placeholder multisets and
newline counts, then updates draft provenance. All 29 catalogs have no missing entries under these structural
checks. This is machine-draft coverage, **not native-speaker approval or complete localization acceptance**.
English connection/OIDC page titles, client error copy and initial server-rendered language remain explicit
limitations; there is no SSR/i18n redesign in this increment.

## Final evidence and remaining criteria

Final verification is limited to the four affected Chromium bookmark journeys, translation integrity,
Biome, TypeScript, the existing unit suite and one local `/web` static build. Results and their exact checked
commit are reported on the PR. Logs and failure evidence remain private for root; no private artifacts or
screenshots are published. PDF/control/reader/full-browser and multi-engine suites are not repeated.
Frontend bars opened by grep: state (`useState` at bookmarks39/40 and player-dock78), types
(`z.string` at bookmarks17), components (`"use client"` at both line1; exported components at20/53).
No effect was added. Dialog/rename/remove are event-owned; time is derived, title is a DOM form draft,
server bookmarks and mutation lifecycle remain query-owned.

| Issue | Current software / criteria | Remaining gate |
| --- | --- | --- |
| #57 | Bookmark current-time and inline-title gaps implemented; existing playback evidence retained | Root review/deployment, explicit pending playback criteria, physical audio/Safari/Media Session and real-network/owner acceptance |
| #59, #60, #63 | Root reconciled and closed against their own criteria | Do not reopen from blanket physical-readiness gates |
| #61 | Reviewed rotation implementation merged in #124 | Root serves reviewed final rotation build, then root can reconcile/close |
| #64 | All 347 in-use catalog entries covered in 29 non-English tables; usable originals preserved | English page/error/initial-render limitations, native-speaker quality, touch/AT/scalable-text/contrast acceptance and original pending criteria |
| #65 | Bounded software increment ready for final checks/review | Root pinned review, consolidated internal deployment/acceptance and legacy retirement criteria |

Original SPEC and ticket acceptance criteria remain unchanged. Hardware/native-speaker/owner limits are
tracked separately from software gaps; closed feature tickets are not reopened. This pass stops at PR handoff.

---

# Bounded web finishing pass, October 2, 2026

Candidate software was checked at `7b2a916c61c87a3533ca819d8b29c09bc7a7059e`, originally based on `d3152a5d`.
The PR is now rebased onto `f63b7906` (Android #123). Native provenance was regenerated against its actual merged
tables: all 29 generated locale files are byte-identical to the checked candidate, coverage is unchanged, and
30 source-table hashes changed. Only provenance changed under the implementation files. The existing package
is retained; no second package or unit/build/browser repeat was performed for this update.
No deployment or owner-library check was performed in this pass. Root owns merging and client-only promotion.
The original acceptance criteria in SPEC.md and issues #55–65 remain in force. Native EPUB/MOBI/comics deferral
applies to mobile; browser readers remain in scope.

## Concrete software work

The inventory's `reader-pdf` requirement explicitly includes rotation. The browser lacked a control.
Rotate page now adds quarter turns to the PDF's authored orientation, fits the rotated page to available width,
and uses the same viewport for canvas, selectable text and annotation links. The choice survives reload in
this browser, separately for each document path. It does not change the shared page location or audio position.
Primary and supplementary PDFs use the same component. Separate zoom/fit buttons were not established as a
baseline requirement; automatic width fitting already existed.

Translation reuse is bounded to exact English wording with the same meaning: 19 Apple equivalents (including
Rotate page) and 7 Android equivalents. `web/src/i18n/native-equivalents.json` is the reviewed allowlist;
`web/scripts/import-native-strings.py` checks exact source English and placeholder multisets before copying.
`web/src/i18n/native-strings/provenance.json` records SHA-256 hashes of every source table and per-language counts.
Run `python3 web/scripts/import-native-strings.py` to regenerate. Nothing calls a translation service.

The current literal-key scan of production TS/TSX (excluding i18n tables and unit tests) finds 176 in-use web keys:
29 with server equivalents, 26 with native equivalents, and **121 without a verified equivalent**, listed in
[WEB-ENGLISH-FALLBACK.json](WEB-ENGLISH-FALLBACK.json). This supersedes the historical 172/143 counts without
erasing those reports. Native tables provide 19–26 distinct translated values per language across all 29
non-English web languages, including Korean. Missing or English-identical values retain the English fallback.
The scan is a literal-reference inventory, not proof of runtime translation coverage. English connection/OIDC
page titles, client error messages and the initial server-rendered language remain limitations. “Remove {0}”
and Android's auto-continue wording were excluded because their source uses differ in meaning. Native-speaker
acceptance remains open for reused text as well as future translations.

## Evidence and fresh review

- The reported releasecheck at live `b1abbd68` (115 unit tests, Chromium 42 journeys, static/build pass) is
  historical evidence supplied by root, not a rerun or a check of this candidate. Its `web/` tree is
  `56f11c01c566d065ad04a5c23eaa54d3521daa6b`, exactly equal to the `web/` tree at base `d3152a5d`.
- Both targeted PDF journeys reached the document and failed on the missing Rotate page button before the fix.
  An earlier attempt used a dev port outside the fixture's allowed origins and failed at connection; it is
  retained separately and does not count as RED. Intermediate implementation failures are retained too.
- GREEN: Chromium 2/2, primary rotation/link click at the printed words, saved page/orientation after reload,
  four quarter turns, and a supplementary PDF while audio keeps playing and both positions reach the server.
  Synthetic Audiobookshelf 2.30.0 at the existing pinned image digest. No owner accounts/data were used.
  Reader blob: `e05915d5832a030890faec78f7167113dc6ff2d2`; GREEN journey blob:
  `44585e27d5be12da87934a8da67d836b605d657f`. The final journey blob
  `1fec660635735c4bbcb66a815b1a06a09f1f8009` only adds HTMLCanvasElement type guards and formatting.
- Final on `7b2a916c`: Biome clean apart from the existing deprecated-config info; TypeScript clean;
  115/115 unit tests across 17 files; `ABS_WEB_BASE_PATH=/web npm run build` passed. An initial final-check
  attempt stopped at TypeScript's canvas element narrowing errors before units/build; corrected before the
  successful candidate check. No broad browser repeat or extra engine sweep.
- The delivery root explicitly reported its fresh source review after the initial candidate, with no blocking
  runtime issue. It covered shared primary/companion rendering, authored rotation addition, viewport
  link/text alignment, schema-checked persisted orientation, cancellation, exact translation mapping and
  language-loader fallback. No blocking finding remains. Frontend bars opened: state, types, components;
  `useEffect` hits at PDF lines 37, 139, 150 name the pdf.js/ResizeObserver external systems.

Logs, failure traces and the local standalone `/web` package are retained privately for root. No screenshots,
credentials, private hosts or package artifacts are committed to this public repository. Deployment acceptance
of this candidate has not occurred.

## Remaining rows at the prior pass (historical)

| Issues | Main software flow | Remaining acceptance / limits |
| --- | --- | --- |
| #55–56 | Connection, authentication, browse/search and discovery delivered in the base | Owner acceptance and real identity provider; earlier fixture evidence retained in WEB-HANDOFF |
| #57–59 | Playback, bookmarks, progress recovery, podcasts and lists delivered in the base | Physical audio, Safari/Media Session, long real-network sessions, owner feeds; bookmark list still lacks current-time marking and an inline typed-title creation form (create then rename is available) |
| #60, #62–63 | Web EPUB, MOBI/AZW3 and comics remain implemented and in scope | Physical Safari, touch, selection/AT; WebKit external links inside MOBI/AZW3 remain unverified |
| #61 | PDF rotation software gap closed by this candidate | Physical Safari/touch/AT, real documents and owner acceptance; orientation is local, page progress retains the existing shared notation |
| #64 | 26 exact native equivalents reused, English fallback retained | 121 unmatched in-use web keys, per-language table gaps, English page/error copy and native-speaker review; no full-localization completion claim |
| #65 | Local `/web` standalone candidate packaged | Root merge/promotion, read-only deployment smoke and owner acceptance; legacy retirement remains gated |

No acceptance checkbox is waived or closed by these results. Hardware/native-speaker/owner gates are separate
from the completed rotation change and the remaining translation debt. This pass stops here; it does not start
another parity audit.
