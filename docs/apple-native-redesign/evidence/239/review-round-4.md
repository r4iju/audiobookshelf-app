# Independent frozen review, round4

Frozen source `bc1211135df900d4658d5d0b69de483b6044222f`, base `77c154b1a344c5936954c2e7346d45c563de61a8`. Fresh T3-owned read-only reviews; all original briefs/prior findings/responses supplied. No captures or user gate. Runtime experiment remains source-labelled. Reports below retain each axis separately; no shipping approval is inferred.

## standards

Frozen standards review: `77c154b1...bc1211135df900d4658d5d0b69de483b6044222f`. **No new confirmed documented-standard breach.** No Rationalised Shortcut or Comment Bulk finding.

Confirmed facts:

- [LibraryView.swift:7](/Users/emanuel/code/leafwake-fullstack/tvos/App/LibraryView.swift:7) adds `[Route]` state and binds it to the native NavigationStack. Installed SDK declarations place this initializer at tvOS16, within the preserved tvOS17 minimum. Existing route destinations, native Back handling and `.id(library.id)` remain. No new test was added; the unchanged journeys already failed through the required UI seam, consistent with [SPEC.md:88](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:88).
- [tv17-replay.py:74](/Users/emanuel/code/leafwake-fullstack/verification/older-os/tv17-replay.py:74) retains all seven default journeys and records exact suite selection. [Workflow line33](/Users/emanuel/code/leafwake-fullstack/.github/workflows/native-older-os.yml:33) selects only Shell, Related and Readiness. A resulting green would establish that three-case scope, not complete final-source acceptance.
- The retained [source313 log](/tmp/native239-ci-3137385e/tv17/representative-journeys.log:3171) confirms five passes and two failures, Related Back and Archive10 detail selection. Active bc121 experiments establish no result. The [private-candidate report](/tmp/native240-preparation/PREACCEPTANCE-bc121113-RESULT.md:1) correctly separates strict signature/build success from acceptance.
- Prior findings persist: V239-01 remains resolved within its measured scope; V239-02 remains RED. Podcast decomposition preserves fields/default precedence; download callback bodies/main-queue handoff remain unchanged. Installed declarations support the tvOS interruption-key exclusion and separate SDK/runtime guards. No React/Next scope creep was found.

Hypotheses and judgment calls:

- Explicit path ownership may resolve the two navigation failures; source inspection cannot establish Back/focus restoration or selection behavior.
- **Nonblocking Duplicated Code:** [PlaybackViews.swift:74](/Users/emanuel/code/leafwake-fullstack/apple/App/PlaybackViews.swift:74) and [line258](/Users/emanuel/code/leafwake-fullstack/apple/App/PlaybackViews.swift:258) repeat `artwork = nil → capture ID → fetch cover → reject stale ID → decode image`.
- Clipping/sampling remains a contrast hypothesis, not acceptance.

Strict contrast, genuine spoken VoiceOver, actual iOS14 execution, final-source TV17 journeys, matching owner installation and merged-source QA remain pending under [SPEC.md:97](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:97). Existing visual review remains PENDING; no new capture or user-inspection gate applies. **This review does not approve shipping.**

## spec

Frozen review: `77c154b1...bc1211135df900d4658d5d0b69de483b6044222f`. **Acceptance remains incomplete; no new confirmed implementation defect identified.**

The explicit `[Route]` path in [LibraryView.swift:7](/Volumes/ai-ssd/code/leafwake-fullstack/tvos/App/LibraryView.swift:7) retains native links, route destinations and Back handling. Library identity still bounds its lifetime; no persistence key or domain callback changes. Its behavioral benefit remains unproved.

- **TV navigation acceptance remains pending.** Spec requires “including Back restoration” ([SPEC:98](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:98)). Source313’s actual TV17 replay records five PASS/two FAIL: related-content Back remains on Series; Archive10 activation remains on the grid ([original log:2689](/tmp/native239-ci-3137385e/tv17/representative-journeys.log:2689), [frozen evidence:17](/Volumes/ai-ssd/code/leafwake-fullstack/verification/older-os/RUN-ID.md:17)). The bc121 path experiment has no supplied final result. Its explicit three-case CI selection preserves assertions and the seven-case default, but cannot establish complete final-source acceptance ([replay source:74](/Volumes/ai-ssd/code/leafwake-fullstack/verification/older-os/tv17-replay.py:74)).

- **Combined contrast remains RED.** “Preserve the existing measured contrast audit without adding dismissals” ([SPEC:97](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:97)). Positioned observations support a clipping/sampling hypothesis, without proving harmlessness, global acceptance or a visible-color defect ([correction evidence:19](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/corrections/V239-01/RESULT.md:19)).

- **Spoken VoiceOver and iOS14 execution remain pending.** “Actual spoken traversal should be tested” and “Verify supported fallback branches” ([SPEC:99](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:99), [SPEC:101](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:101)). Enable/restore, AX and zero-audio probes provide no app speech; successful minimum14 binaries do not establish execution ([RESULT:33](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/RESULT.md:33)).

- **Merged QA and owner installation remain pending.** “Replay representative journeys on the merged source and install the matching private candidate” ([SPEC:102](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:102)). Exactbc121 private builds/signatures pass but explicitly remain NOT ACCEPTED and uninstalled; phone binary minimum15 remains disclosed ([preparation result](/tmp/native240-preparation/PREACCEPTANCE-bc121113-RESULT.md:1)).

V239-01 remains resolved within its measured scope. Adaptive/largest results retain their recorded scopes. No confirmed scope creep, identity/license change or self-granted acceptance waiver found. Later CI files and synthetic fixtures are verification support; shared compiler fixes preserve contracts. Parent230/historical222 remain unchanged. Historical originals retain truthful labels; no final-source screenshot gate applies. Public distribution remains separately rights-gated.

## visual

**Complete acceptance remains PENDING for frozen source `bc1211135df900d4658d5d0b69de483b6044222f`. No new confirmed presentation defect was found on that source.**

Reviewed against baseline `77c154b1`, all 47 stories, the inventory, rubric, frozen manifests and supplied supplemental artifacts. Historical images retain their original source labels. Review was read-only, with no captures, device operations, GH changes or delegation. Issues222 and230 remain preserved.

- **V239-01 · Medium · Resolved.** Largest-text iPhone Downloads retains the f922 correction. Native Retry/Remove text-fit measurements and independent Retry→ready→Play→Remove actions pass. Mobile production source is unchanged in bc121. [Correction evidence](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/corrections/V239-01/RESULT.md).

- **V239-02 · Acceptance pending; no confirmed visible color defect.** The f922 iPhone27 combined-mode audit remains RED without exclusions. Positioned, fully visible narrator/progress labels are not reported; the audit instead identifies offscreen Resume listening and a partially clipped author label. Clipping remains a hypothesis, not grounds to dismiss the audit or prescribe a global color change. **Requirement:** resolve the strict contrast result through supported noncapturing evidence. [Original observations](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/corrections/V239-01/native239-visible-contrast-f922-positioned.observations.txt).

- **V239-03 · Spoken VoiceOver pending.** Actual iOS27 enable/restore and running output establish capability. The process-private audio probe captured zero bytes after IOProc creation hung. No utterance traversal, grouping or announcement assessment is available. This is an unsuccessful evidence route, **not proof that iOS27 VoiceOver is unavailable**. [Probe result](/tmp/native-voiceover-audio-probe/RESULT.md).

- **V239-04 · Older-system acceptance remains partial.** Source313’s original TV17 run genuinely passes five journeys: continuing/Back, Search, playback, readiness audit and authentication recovery. Related and Shell fail. Original decoded AX supports the reported observations: Back leaves Series displayed; activating focused `item-book-60` leaves the Archive10 grid displayed. These are historical behavioral failures, not invented screenshot defects. Original-minimum iOS14 binaries build, but stock14.5 installation rejects the hosted system volume, so actual14 execution remains unavailable. [TV17 original log](/tmp/native239-ci-3137385e/tv17/representative-journeys.log).

- **V239-07 · Medium historical TV navigation failures; final TV17 resolution pending.** bc121 binds explicit `[Route]` state to TV Library’s `NavigationStack`. Its actual **TV27** selected replay now passes Readiness **45.414s**, Related **29.955s**, and Shell **67.412s**, with zero failures/skips. Thus the modern affected behavior is verified. No terminal bc121 TV17 artifact was available locally; supplied hosted run `37808025142` remained active. **Requirement:** assess its original results before declaring the older failures resolved. [Modern result](/tmp/native-bc121-modern-tv/summary.json).

- **V239-05 · Resolved within recorded scopes.** Largest-text Search and podcast creation, Pad readiness and actual compact-window navigation/player/keyboard interactions retain their separately labelled passing scopes. Earlier compact-player overlap, ghost Search, failed submission routing and extreme-duration caption corrections remain intact.

- **V239-06 · Owner installation and merged-source QA pending.** bc121 private candidates remain NOT ACCEPTED and uninstalled. Phone binary minimum15/SDK27 override remains distinct from source14; TV minimum17 is retained. [Preparation result](/tmp/native240-preparation/PREACCEPTANCE-bc121113-RESULT.md).

Existing corrected TV originals show complete book/episode passage12, readable Notices hierarchy and distinct focus outline/fill. The older typography measurement is not carried forward as a final defect. The blended historical authentication frame does not establish persistent overlap: a separate same-source original shows the complete opaque form, and current source supplies its solid background.

I independently verified all **441 manifested originals**, the **2117-file original bc121 archive**, both release products’ **46 phone/36 TV file hashes**, and strict signatures. Generated-project differences and modern capture-helper suppression match their disclosed provenance. SDK27 declarations confirm Search26 and enabled accessory26.1 availability, with compilation and runtime guards. The typed podcast payload preserves fields and precedence; the compiler compatibility changes do not establish a domain rewrite.

The reviewed composition supports stable destinations, native Search, purposeful hierarchy, adaptive content, readable long-content access and TV focus. This aligns with Apple’s [Liquid Glass adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) and [HIG materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials). **The complete rubric remains PENDING because strict contrast and actual spoken accessibility remain unresolved.** No new screenshot or user-inspection gate is introduced.

