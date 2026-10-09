# Standards, frozen public Apple round 1

Reviewed `git diff c657210d...20215a06` (sole commit `20215a06`). Applied personal context/preferences, parent AGENTS instructions and the code-review skill baseline. No additional applicable repository coding standard found.

**First two smell heuristics:** Rationalised Shortcut: none. Comment Bulk: none. No other material baseline smell found. These are judgments, not hard standards.

**Hard documented-standard violations:** none established.

**Release review judgments:**

- **P2, Apple privacy policy is undiscoverable from the supplied store link.** `APPLE-LISTING.md` and `store-metadata.json` retain “Privacy and support: https://r4iju.github.io/audiobookshelf-app/”. The source landing page links only `privacy.html`, whose policy explicitly covers “the Cast-free Android public build”. Nothing links the new `site/apple-privacy.html`. Point Apple privacy copy directly to the Apple policy or add a clearly labelled Apple link. Actual deployment/App Store Connect privacy URL remains unverified; this finding concerns the frozen source navigation.
- **P2, privacy disclosure omits voluntary public RSS publishing.** `APPLE-PRIVACY.md:9` groups actions as “account-authorized editing requests” going directly to the server. Mobile `ItemServerActionsViews.swift:135-164` also accepts owner name/email and indexing preferences to publish an RSS feed. Explain that feed settings can expose owner information and selected media through a public feed, and describe closing it. The Android policy already makes this distinction. Mirror the addition in Apple HTML. This is a completeness judgment, not evidence of undisclosed developer telemetry or a mandatory privacy-label category.

The checked native code supports Keychain connections, retained listening/downloads after sign-out, generic Apple device/session information, local redacted diagnostics and explicit sharing. EPUB rendering uses local assets and a restrictive CSP. Cached official Apple guidance distinguishes developer/SDK collection from on-device processing; no unsupported privacy-label conclusion is made here.

Archive inputs reject non-positive/non-numeric build numbers and unknown audiences before provisioning. `app-store` makes `testFlightInternalTestingOnly=false`; internal remains the safe default. Shell syntax passes. Export configuration establishes eligibility intent, not successful processing/submission. MIT scope, root GPL, Android/history exclusions, origin and bundled notices remain unchanged.

Original-minimum, contrast and spoken acceptance remain open. No waiver inferred. No source edits, signing, upload, network, contact or screenshots performed.

Totals: 0 hard Standards violations; 2 release judgments to resolve before public distribution.
