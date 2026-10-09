# Frozen final review

Reviewed `git diff c7c85389...b16355f4` and the five commits in `git log c7c85389..b16355f4 --oneline`. HEAD is `b16355f42ed6619164f85c606775c5b80b51b95d`; working tree clean.

## Standards

No remaining documented violation or material smell heuristic found. No Rationalised Shortcut or Comment Bulk finding.

Round-one findings are resolved: `apple/scripts/appstore-api.py:30` uses `curl -q --noproxy ''`, enforcing the explicit proxy against default curl configuration/environment bypasses. `archive-testflight.sh` retains the OAuth scheme; the actual distribution plist and `OpenIDSignIn.swift` consistently use `audiobookshelf-native-preview` while bundle/keychain identity is separately configured.

The scoped Apple MIT grant excludes vendor distributions, inherited code and LegacyRealm fixtures; root GPL remains unchanged. No new affirmative copied-runtime finding emerged. Prior provenance comparisons remain bounded evidence, not ownership certification.

## Spec

One outstanding delivery requirement: SPEC.md:7 says “Upload and assign only to the owner internal group.” Upload, Apple processing and owner-only group assignment are still root work, not established by package export. This is an acknowledged pending gate, not a newly discovered source blocker or self-granted deferral.

No additional source/package blocker found. Both build-2 IPA hashes match the supplied b163 proof, distribution profiles have `get-task-allow=false`, and export options specify internal-only testing. Public identifiers, original source minima and the disclosed local iOS15/tvOS17 package minima are consistent. All 30 packaged locale tables per platform match independent generation. Bundled MIT/vendor notices match source; API/data contracts and origin disclosure remain preserved.

Generation freshness, independent-generation regression and shell syntax passed. Recorded mobile connection/restoration and TV notice/Back journeys each passed 1/1; these do not establish full redesign, spoken accessibility or original-minimum acceptance.

No source writes, signing, upload, network, device/browser operations or captures performed.

Totals: Standards 0 findings; Spec 1 pending delivery gate (owner-only TestFlight assignment). No new blocker to proceeding with the authorized upload.
