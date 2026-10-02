# Bounded web finishing pass, October 2, 2026

Candidate software: `7b2a916c61c87a3533ca819d8b29c09bc7a7059e`, based on `d3152a5d`.
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
- One root source review covered shared primary/companion rendering, authored rotation addition, viewport
  link/text alignment, schema-checked persisted orientation, cancellation, exact translation mapping and
  language-loader fallback. No blocking finding remains. Frontend bars opened: state, types, components;
  `useEffect` hits at PDF lines 37, 139, 150 name the pdf.js/ResizeObserver external systems.

Logs, failure traces and the local standalone `/web` package are retained privately for root. No screenshots,
credentials, private hosts or package artifacts are committed to this public repository. Deployment acceptance
of this candidate has not occurred.

## Current remaining rows

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
