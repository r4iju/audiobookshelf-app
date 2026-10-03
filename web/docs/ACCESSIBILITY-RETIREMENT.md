# Bounded browser accessibility and legacy entrypoint retirement

October 3, 2026. Base: merged `bbac469a`, live image `9cde1a07`.
Merged PR #144 (`de59fc53`, reviewed source `99ce105d`) is deployed as image
`sha256:38bb9ab2b28737ac4d1e1b09c8c961182b1ad15b3964bcf8c58c606dbb21effc`.
Root verified unchanged web inputs, healthy deployment, HTTP/HTTPS 4/4 smoke, initial German/Arabic/invalid-language rendering and live sign-in contrast. See [Final readiness](../../docs/modernization/FINAL-READINESS.md). SPEC's amendments #141/#142 apply: physical setup may be deferred, while
software migration, translation quality and safe cutover remain required.

## Measured failure and correction

Before changing product code, the actual deployed image in a uniquely named, local synthetic
fixture showed dark primary-button text at **4.448:1**, below 4.5:1.
Form boundaries were **1.458:1**, below 3:1. These measured failures are retained as RED.
No new implementation tests or backfilled green tests were added.

The candidate dark primary fill is darker; hover has a separate darker token. Danger-filled
confirmation buttons use a dark fill while danger text retains its existing palette.
Fields, choices, switches, checkboxes, reader page inputs and the podcast textarea use the
existing muted color for discernible boundaries. No settings/state/location/auth contracts change.

The bounded candidate measurements cover Connect, incorrect-password error, library, details,
full player, EPUB reader and reader settings in dark/light/black:

| Observation | Outcome |
| --- | --- |
| 846 rendered interface text samples | Zero failures against 4.5:1 normal / 3:1 large text |
| 105 enabled form-boundary samples | Zero failures against 3:1 |
| Dark primary normal/hover | 5.439:1 / 6.609:1 against white |
| Enabled visible control names | No unnamed controls in sampled screens |
| 320 CSS pixel reflow, all eight screen states | Document width stays within viewport |
| 200% root text at 1280px and 640px, all eight states | Document width stays within viewport |
| Keyboard | Named controls, visible 3px focus, skip link reaches main; reader dialog Tab/Escape returns to settings |
| Reduced motion | Actual Settings switch survives reload; transition is 0.00001s without measurement overrides |
| EPUB | Actual chapter passages; light/black/dark text palette is 21:1 / 21:1 / approximately 15.7:1; font scale accepts 200%, next page reports location 7/330 |
| Audio | Decoded native audio reaches readyState 4; player controls remain alongside reading |

Text contrast uses computed sRGB colors and alpha-composited ancestor backgrounds. Transitions
are disabled **only for stable color measurement**; this is not motion evidence. Disabled
controls and background images are excluded, recorded in the raw output. Reader iframe
passage colors are observed separately. These samples are not an exhaustive contrast audit
of every artwork, document, popup or error variation.

T3 preview was used first, including actual Tab/Enter/Escape. It then explicitly reported no
automation host and instructed a headless fallback. The remaining bounded measurements used
local Chromium. Browser-menu zoom key attempts did not change the preview's viewport/DPR:
320px reflow is the layout equivalent of 400% desktop zoom, **not a claimed native zoom-menu
operation**. A combined CSS page-zoom and text-scale experiment is excluded because CSS zoom
does not reproduce browser media-query behavior. Native browser-menu zoom, physical Safari/
VoiceOver, forced-colors mode and native-speaker approval remain unverified. This does not
waive inspectable accessibility, translation quality or migration correctness.

Private evidence:
`/Volumes/ai-ssd/code/audiobookshelf-delivery/2026-10-03/web-accessibility-retirement/`:
`contrast-red.json`, `measure-expression.js`, `bounded-browser.json`,
`focus-motion-reader.json`, `reader-candidate.png`, build logs and reproduction scripts.
Early route/loading, strict-locator and wrong-runtime-base-path setup failures are excluded.
The corrected root build/start dispatch ran locally with `ABS_WEB_BASE_PATH=/web`.
Lint and typecheck passed. No unchanged broad unit/journey suite was repeated.

## Retained acceptance and current source

The retained main-use checks on unchanged `d2d7543b` cover real `/abs` password/media/API,
genuine 401 → refresh 200 → retry 200 during decoded playback, and injected autoplay denial
followed by visible/native play retry. See the private `web-main-gates/RESULTS.md`.
Prior reader/playback/progress evidence remains in [WEB-HANDOFF](../../docs/modernization/WEB-HANDOFF.md).

PR #143's corrected merged head includes `c11909a7`: default-English OAuth metadata fallback,
localized sign-in/error copy, language-aware initial SSR and reader dialog focus restoration.
Root recorded actual HTTPS language/title and HTTP/HTTPS 4/4 against live `9cde1a07`.
The prior local signed provider callback reached stock 2.30.0 through `/abs`, created a synthetic
account, removed the code from the URL and survived signed-in reload. Wildcard redirect
configuration was needed for the port-bearing fixture; strict production whitelist callback,
external-provider consent/key rotation/logout and owner sign-in are not claimed.
Translation drafts still require quality review; source coverage and simulation do not confer
native-speaker approval. Historical parity statements are dated history, not current gaps.

Scope review permits #55/#57/#58/#62 to close from their retained software criteria.
#56 receives this shared accessibility evidence. #64/#65 remain open for root's final review.
No reader error/placeholder/conversion-only result is counted as actual reading.

## Legacy recovery

Default root commands dispatch to `web/`. Legacy hosted builds are disabled and archived,
with source/dependencies/export tools/native shells/artifacts preserved.
The protected annotated tag and recovery/import/reauthentication/rollback instructions are in
[LEGACY-RECOVERY](../../docs/modernization/LEGACY-RECOVERY.md). Server Vue admin is unchanged.
This retirement does not authorize installing over upstream apps or clearing owner data.
The owner's dirty checkout and central delivery manifest remain untouched.
