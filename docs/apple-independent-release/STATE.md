# Independent Apple internal beta, October 9, 2026

Frozen app source: b16355f42ed6619164f85c606775c5b80b51b95d, build 2, version 1.0.0, separate public identity com.forkzed.leafwake. Both distribution archives and extracted IPA payloads passed strict signature verification. Source/resource manifests are in COMPILED-INPUTS.json and package checks in CANDIDATES.json.

The native localization loader regression was observed failing against inherited-root loading before implementation, then passed. Localization tests passed 15/15. Existing production mobile account restoration and TV notices/Back journeys each passed 1/1, no skips; their production source matches this candidate. This is targeted verification, not comprehensive redesign acceptance.

Both package files were uploaded through the fixed authorized proxy using Apple's Build Upload API and finalized successfully. Both processed as VALID and INTERNAL_ONLY; both are now IN_BETA_TESTING, with external state NOT_APPLICABLE. Owner internal group bf82b29b-63b5-4d91-9231-8287abd4c015 has exactly one tester, verified against the account holder's email, no public link and no access to all builds. Both build-2 binaries are assigned to this group. The owner tester state is INVITED; receipt, acceptance and installation on the owner's devices have not been observed.

Round-two Standards review has no findings. Spec review identified delivery as pending at review time; subsequent Apple readback verifies processing and owner-only assignment. Earlier callback, proxy bypass and export-tool failures are corrected. Historical failed exports are not release candidates.

Scoped Apple MIT notices cover independently controlled app code only. Root GPL, inherited code/history and Android are unchanged. Reader vendors retain their notices. Bounded provenance evidence does not certify ownership from Git author names. Translation coverage remains incomplete, with English fallback. Source minima remain iOS14/tvOS17; this SDK27 mobile package requires iOS15.

The broader redesign's contrast, spoken accessibility and original-minimum execution acceptance remain open under the existing dependency PR #241. This internal beta does not close those requirements or authorize external groups, public links or App Store submission.
