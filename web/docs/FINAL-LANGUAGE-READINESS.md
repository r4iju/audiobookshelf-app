# Initial language and sign-in readiness, October 3

The web client now mirrors its effective language into a validated, one-year, SameSite=Lax cookie scoped to its base path. Layout and sign-in metadata read it per request and load the carried translation bundle before rendering. No credentials or account fields enter this cookie. Local settings and the selected server language remain authoritative after hydration. An existing localStorage-only preference seeds the cookie on its first upgraded visit; subsequent reloads render it on the server. Invalid codes fall back to English. Routes now render dynamically because their initial language is request-specific.

Connect titles follow the translated heading, including changing servers. OpenID return has a translated heading/title. Invalid API responses show the existing translated retry message while the original diagnostic error remains available to callers.

## Scoped evidence

Private evidence: `/Volumes/ai-ssd/code/audiobookshelf-delivery/2026-10-03/reader-expansion/web/`.

- Meaningful RED before implementation: the public API client receiving malformed data exposed English schema text under German; the actual HTTP response with a German cookie rendered English HTML and metadata. `errors-red.log`, `ssr-red.log` retain both failures.
- GREEN: focused error and translation tests 3/3; Biome and TypeScript passed; `/web` production build passed. The HTTP assertion script verifies German, Arabic RTL and invalid-code fallback against the production server. No broad 115-unit/86-journey repeat.
- T3 preview: German Connect title, actual German OpenID no-start error and title; saved preference reload. Actual local provider consent through stock Audiobookshelf 2.30.0 under `/abs` reached `/web/oauth`, exchanged the code, created `qa-openid`, cleared callback query data, opened the library and remained signed in after reload. No mocked success response.
- Stock 2.30.0 rejects configured mobile redirect URLs containing ports. Local port80 was already owned by shared SSH. The uniquely named synthetic fixture used its documented wildcard redirect option; strict hostname whitelist production acceptance is not claimed. No owner configuration or global routing changed.
- Candidate AZW3 `Glass Orchard` rendered readable passages, German navigation and settings with frame title `Buchtext`. Next saved `mobi:1:0:11` at 9% on the server; reload returned to 9% with readable content. The dialog focused its first control and returned focus to its trigger on close.
- T3 `preview_press` returned an automation client error for PageDown, Tab and Escape, including after retry/open. These attempts are not keyboard success evidence. Retained reader keyboard/offline/audio/other-format evidence on unchanged engines remains applicable; no new complete format matrix is claimed.

Physical Safari/VoiceOver, native-speaker approval and actual owner migration/cutover remain unverified. The owner's current physical-check deferral does not waive translation quality, synthetic migration correctness or safe cutover. Existing preservation contracts, associations, unknown locations, queued progress and legacy fallback are unchanged. Root coordinates fresh independent review, packaging and production deployment; this branch must not merge before that review.
