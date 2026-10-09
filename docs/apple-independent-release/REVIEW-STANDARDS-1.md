# Standards review

Reviewed `git diff c7c85389...HEAD`; commits `8f87253d` and `68d31f88`. Shared personal context/preferences, parent AGENTS instructions, Apple/TV READMEs, scoped license, supplied Standards baseline and release spec applied.

## Documented violation

- **P1, fixed network route is not enforced:** `apple/scripts/appstore-api.py:30` invokes curl with `--proxy` but without `--noproxy ''` or disabling curl's default configuration. A matching `NO_PROXY`/`no_proxy` environment value can bypass the proxy, sending the authenticated request directly. This conflicts with `~/.ai/PREFERENCES.md`: “Clearnet egress requires explicit user approval covering the intended use” and the helper's “owner's fixed proxy” contract. Start curl with `-q` and explicitly clear proxy bypasses. No network request was made during review.

## Smell heuristics (judgement calls)

No Rationalised Shortcut or Comment Bulk finding.

- **Possible Primitive Obsession, release identity:** `apple/scripts/archive-testflight.sh:21` globally replaces `'audiobookshelf-native-preview'` with `'leafwake'` in the staged YAML. This changes the declared OAuth URL scheme, while `apple/App/OpenIDSignIn.swift:7,64,105` still requests, validates and intercepts `audiobookshelf-native-preview://oauth`. The public plist and runtime therefore describe different callbacks. ASWebAuthenticationSession may intercept the old callback without plist registration, so this is not evidence that every sign-in fails. Make the intended callback an explicit release contract and retain it consistently, independently of bundle identity.

No additional documented source/license violation found in this bounded review. The loader no longer reads inherited tables; scoped MIT excludes vendor/LegacyRealm material; root GPL and reader notices remain. Prior provenance evidence is bounded, not ownership certification. The archive helper prepares packages and contains no upload/group-assignment action.

Read-only validation: generation freshness, independent-generation regression and shell syntax passed; recorded red regression inspected. No source edits, signing, upload, device/browser use or captures.

A concurrent worktree edit to the archive helper appeared at the end; findings refer to committed HEAD `68d31f88`.

**Total: 1 documented violation; 1 smell heuristic.**
