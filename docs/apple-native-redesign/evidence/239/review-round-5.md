# Independent frozen review, round5

Source `d49f2a42545ba19b40fa1f2a453711e02032abcc`, base `77c154b1`. Read-only reviews, no new captures or user gate. Review time preceded terminal hosted TV17 failure. The subsequent original hosted result is one Readiness pass and two failures, Related author Back and Shell chooser selection; it supersedes the pending runtime statement below without changing the independent findings. No release approval inferred.

## spec

Frozen review: `77c154b1...d49f2a42545ba19b40fa1f2a453711e02032abcc`. **Acceptance remains incomplete; no new confirmed implementation defect identified.**

- **TV acceptance remains partial.** Spec requires “including Back restoration” ([SPEC:98](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:98)). The new selection applies only after native dismissal and clears on account change ([source:128](/Volumes/ai-ssd/code/leafwake-fullstack/tvos/App/LibraryView.swift:128)). Exact d49 modern Readiness/Related/Shell pass 3/3 ([result:5](/tmp/native-d49-modern-tv/RESULT.md:5)); no completed d49 TV17 result was supplied. Earlier bc121 passes Readiness/Related but fails Shell ([evidence:19](/Volumes/ai-ssd/code/leafwake-fullstack/verification/older-os/RUN-ID.md:19)). The [workflow:38](/Volumes/ai-ssd/code/leafwake-fullstack/.github/workflows/native-older-os.yml:38) explicitly selects three navigation cases; the retained seven-case suite does not establish complete final-source acceptance.

- **Combined contrast remains RED.** “Preserve the existing measured contrast audit without adding dismissals” ([SPEC:97](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:97)). Detail metadata/progress remain in [BookDetails.swift](/Volumes/ai-ssd/code/leafwake-fullstack/apple/App/BookDetails.swift:243). Positioned audits narrow the clipping hypothesis but prove neither harmlessness nor global acceptance ([evidence:19](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/corrections/V239-01/RESULT.md:19)).

- **Spoken VoiceOver remains partial.** “Verify VoiceOver roles, values, selected/disabled states, group order, errors and recovery” ([SPEC:99](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:99)). Phone production is unchanged from f922. Six non-onboarding clips support bounded app speech with local ASR; zero-audio “Thank you” transcripts are invalid. Full destinations, recovery, selected/disabled controls, Downloads, readers and Settings remain uncovered ([source](/Volumes/ai-ssd/code/leafwake-fullstack/apple/App/NativeShell.swift:150), [evidence:7](/tmp/native239-spoken-app-bc121/RESULT.md:7), [clip manifest](/tmp/native239-spoken-app-bc121/clips.json)).

- **Older execution and release remain pending.** “Verify supported fallback branches” and “Replay representative journeys on the merged source” ([SPEC:101](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:101), [SPEC:102](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:102)). Minimum14 build proof does not establish execution ([evidence:33](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/RESULT.md:33)). Exact d49 signed candidates remain NOT ACCEPTED/uninstalled; phone binary minimum15 is disclosed ([result:3](/tmp/native240-preparation/PREACCEPTANCE-d49f2a42-RESULT.md:3)).

Adaptive/largest results retain their bounded scopes; V239-01 remains resolved. No confirmed scope creep, identity/legal change or self-granted acceptance waiver found. Synthetic fixtures and CI support are verification changes; shared compiler fixes preserve contracts. Parent230/historical222 remain unchanged. Historical originals retain their labels; no final-source screenshot gate applies. Public distribution remains separately rights-gated.

## visual

**Complete acceptance remains PENDING for frozen source `d49f2a42545ba19b40fa1f2a453711e02032abcc`, compared with `77c154b1`. No new confirmed presentation defect was found in the reviewed source and existing originals.**

Read-only review covered the 47 stories, inventory, rubric, source changes and source-scoped evidence. Issues222 and230 remain preserved. No captures, device operations, source edits, GH changes or delegation occurred. Historical originals retain their actual source labels.

- **V239-01 · Medium · Resolved within recorded scope.** Largest-text iPhone Downloads retains the f922 correction. Native text-fit measurements and independent Retry→ready→Play→Remove actions pass. Mobile production source is unchanged through d49. [Correction evidence](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/corrections/V239-01/RESULT.md).

- **V239-02 · Acceptance pending; no confirmed visible color defect.** The f922 iPhone27 combined Reduce Transparency, increased contrast and Reduce Motion audit remains RED without exclusions. Fully positioned narrator/progress labels are not reported; different offscreen or partially clipped content is reported. **Requirement:** resolve the strict audit through supported noncapturing evidence. Clipping remains a hypothesis, insufficient to dismiss the audit or prescribe a global color change. [Exact observations](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/corrections/V239-01/native239-visible-contrast-f922-positioned.observations.txt).

- **V239-03 · Spoken VoiceOver partially evidenced; complete acceptance pending.** The later owned iOS27 process-private route captured actual app speech. Six nonsilent clips have machine transcripts covering form labels, selected Library “two of five,” Downloads “three of five,” book context, narrator, Resume listening and compact/expanded context. Native double-tap actions opened the book, started playback and expanded the player. Two all-zero clips correctly reject ASR’s “Thank you” hallucination; onboarding is separate. This supersedes the earlier zero-byte route as capability evidence. **Requirement:** assess complete traversal/grouping, recovery, readers, Settings, Downloads actions and disabled/selected tools. Machine transcription is not human listening or full spoken acceptance. [Assessment and limitations](/tmp/native239-spoken-app-bc121/parent-spoken-assessment.json).

- **V239-04 · Older-system acceptance partial.** Original-minimum iOS14 binaries build; actual stock14.5 installation rejects the hosted system volume, so execution remains genuinely unavailable through that route. Source313’s five passing TV17 journeys and two failures remain historical, separately scoped evidence. Build success does not establish runtime acceptance.

- **V239-07 · Medium historical TV navigation failures; final TV17 resolution pending.** d49 applies library selection after native chooser dismissal and clears pending selection on account changes. Its exact TV27 replay passes Readiness **46.577s**, Related **30.805s** and Shell **67.732s**, zero failures/skips. bc121’s hosted17 Readiness and Related passes establish progress; its Shell label assertion still failed. The retained trace ends before Select, so it cannot establish a post-Select chooser state. The removed global hittability prerequisite was an invalid remote-test assumption. **Requirement:** inspect terminal originals from supplied d49 TV17 run `37812757060`; no terminal artifact was available in the reviewed local evidence. [Exact modern replay](/tmp/native-d49-modern-tv/RESULT.md).

- **V239-05 · Resolved within recorded scopes.** Compact player/tab overlap, ghost Search, submission routing and extreme-duration corrections remain intact. Actual compact iPad navigation/player/keyboard and largest-text Search/podcast checks retain their disclosed sources. New preferences and importer selection/cancellation/reopening retain native controls and recorded passing behavior.

- **V239-06 · Owner installation and merged-source QA pending.** d49 private candidates remain NOT ACCEPTED and uninstalled. Phone binary minimum15/SDK27 is an explicit override, distinct from source14; TV minimum17 remains. [Preparation result](/tmp/native240-preparation/PREACCEPTANCE-d49f2a42-RESULT.md).

Existing corrected TV originals show readable Notices hierarchy, distinct focus outlines/fills and reachable book/episode passage12. The older interim typography measurements are not carried forward as final defects. Historical frames cannot establish every current visual state.

I independently verified **441 original-image hashes**, **nine audio hashes**, the **2125-file source archive**, **46 phone/36 TV product hashes**, strict signatures and modern replay source provenance. Selected SDK27 declarations confirm Search26 and enabled accessory26.1 availability with compilation and runtime guards. The typed podcast payload preserves fields and precedence.

The reviewed composition supports native destinations, hierarchy, adaptive content and restrained materials, consistent with Apple’s [adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) and [custom-view guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views). **The complete rubric remains PENDING**, principally for strict contrast and complete spoken accessibility. No new screenshot or user-inspection gate is introduced.


## standards

Frozen review: `77c154b1…d49f2a42545ba19b40fa1f2a453711e02032abcc`, full integration and commit list. **No new confirmed documented-standard breach.** No Rationalised Shortcut or Comment Bulk finding.

Confirmed facts:

- [LibraryView.swift:128](/Users/emanuel/code/leafwake-fullstack/tvos/App/LibraryView.swift:128) applies pending library selection only in native sheet `onDismiss`; account changes clear pending selection. Installed SwiftUI declarations place this sheet callback at tvOS13 and bound NavigationStack at tvOS16, both within the preserved tvOS17 minimum. Existing routes and library identity remain.
- [TVJourney.swift:66](/Users/emanuel/code/leafwake-fullstack/tvos/UITests/TVJourney.swift:66) restores original focus plus one Select. [ShellJourney.swift:25](/Users/emanuel/code/leafwake-fullstack/tvos/UITests/ShellJourney.swift:25) returns after the existing assertion fails; it does not convert failure into success. No new test was added, consistent with [SPEC.md:89](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:89).
- Source-pinned [modern replay](/tmp/native-d49-modern-tv/RESULT.md:1) now records **3/3 passed**, zero failures/skips: Readiness46.577s, Related30.805s, Shell67.732s on tvOS27. This is scoped modern evidence.
- [Workflow:38](/Users/emanuel/code/leafwake-fullstack/.github/workflows/native-older-os.yml:38) explicitly selects three navigation cases. Default configuration retains three jobs; TV-only overrides skip mobile jobs, establishing no mobile pass.
- [RUN-ID.md:21](/Users/emanuel/code/leafwake-fullstack/verification/older-os/RUN-ID.md:21) correctly retracts post-Select snapshot proof. The retained bc121 trace ends before Select.
- Podcast payload fields/default precedence and download callback bodies/main-queue handoff remain preserved. No React/Next scope creep was found.

Hypotheses and judgment calls:

- Deferred identity replacement may explain the navigation recovery; modern passes do not establish its cause or TV17 behavior.
- **Nonblocking Duplicated Code:** [PlaybackViews.swift:74](/Users/emanuel/code/leafwake-fullstack/apple/App/PlaybackViews.swift:74) and [line258](/Users/emanuel/code/leafwake-fullstack/apple/App/PlaybackViews.swift:258) repeat the artwork reset/fetch/stale-ID rejection/decode sequence.
- Spoken evidence contains partial machine transcripts and explicitly rejects silent-clip hallucinations; it establishes no complete traversal or human-listening assessment.

V239-02/strict contrast, complete spoken accessibility, actual iOS14 execution, final-source TV17 acceptance, owner installation and merged-source QA remain pending. Historical images retain their original source labels; no new capture or user-inspection gate applies. **Shipping is not approved.**
