# Frozen Apple review, round 3

Source `3137385eecf195348d00c871f24cc54dfc6c858e`; runtime `f9224289` unchanged. The QA-only keyboard correction and its evidence receive fresh independent review. The [complete-interface round2](review-round-2.md) retains its exact production scope and PENDING acceptance verdict. Later CI results are recorded separately and are not inferred here.

## Standards

Frozen standards review: `77c154b1...3137385e`, runtime `f9224289`. **No new confirmed documented-standard breach.** No Rationalised Shortcut or Comment Bulk finding.

- **Native Search correction preserves the required seam.** [TVJourney.swift:84](/Users/emanuel/code/leafwake-fullstack/tvos/UITests/TVJourney.swift:84) retains native keyboard focus, sends each character once, waits at most three seconds for the exact observed prefix, then asserts the complete query. Missing input fails without silent repair, query injection or server manipulation. Original result/request/detail/focus assertions and `continueAfterFailure = false` remain. All five journeys begin with fresh queries. This follows [SPEC.md:88](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:88).

- **Evidence preserves failure and source scope.** All 94 newly manifested older-run files match their hashes. [Follow-up evidence:7](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/older-replay-follow-up.md:7) distinguishes original-minimum iOS14 builds from unavailable execution, records the 47.799-second TV17 Catalog pass, and preserves malformed native Search input plus trap133. The helper change establishes no new functional pass; source313’s actual older replay remains required.

- **Prior findings remain.** Apple production files are unchanged from source38. V239-01 remains resolved within its measured scope. V239-02 remains RED; clipping/sampling is a hypothesis, not contrast acceptance. Compiler fixes preserve payload, callback and platform contracts. The duplicated artwork-loading shape at [PlaybackViews.swift:74](/Users/emanuel/code/leafwake-fullstack/apple/App/PlaybackViews.swift:74) and line258 remains a nonblocking judgment call.

Strict contrast, genuine spoken VoiceOver, actual iOS14 execution, remaining TV17 journeys, matching owner installation and merged-source QA remain pending under [SPEC.md:97–103](/Users/emanuel/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:97). The existing complete visual review remains PENDING; this delta adds no presentation change or capture gate. **This review does not approve shipping.**

## Spec

Frozen review: `77c154b1...3137385e`, runtime `f9224289`. **Acceptance remains incomplete; no new confirmed implementation defect identified.**

The new [Search helper](/Volumes/ai-ssd/code/leafwake-fullstack/tvos/UITests/TVJourney.swift:84) preserves native keyboard focus, sends each character once, waits at most three seconds for the actual prefix, and asserts the complete query before unchanged result assertions. Missing input fails without repair, injection or silent retry. All callers begin with fresh queries; `continueAfterFailure=false` remains. Production presentation is unchanged, so round2 visual findings retain their scope without another visual-review or screenshot gate.

- **Older-runtime acceptance remains pending.** “Verify supported fallback branches with an appropriate available runtime/toolchain” ([SPEC:101](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:101)). Source38 proves both iOS14 binary architectures and one actual TV17 sign-in/detail/Back-focus journey. Search entered `Tmorrow 61`, then failed; remaining journeys have no PASS ([evidence:7](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/older-replay-follow-up.md:7)). Stock14.5 execution remains unavailable. Source313 run `37802421109` is still `in_progress` in its [ledger](/tmp/native-actions-239-3137385e-20261009/state.json); the helper change supplies no functional green.

- **Combined contrast remains RED.** “Preserve the existing measured contrast audit without adding dismissals” ([SPEC:97](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:97)). Positioned observations narrow the clipping/sampling hypothesis, without establishing global acceptance or a confirmed visible-color defect ([evidence:19](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/corrections/V239-01/RESULT.md:19)).

- **Spoken VoiceOver remains pending.** “Actual spoken traversal should be tested” ([SPEC:99](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:99)). Actual enable/restore and capability failures provide no app utterance evidence ([RESULT:37](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/evidence/239/RESULT.md:37)).

- **Owner installation and merged QA remain pending.** “Replay representative journeys on the merged source and install the matching private candidate” ([SPEC:102](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/SPEC.md:102)). Matching f922 candidates remain explicitly unaccepted and uninstalled ([240 result](/Volumes/ai-ssd/code/leafwake-fullstack/docs/apple-native-redesign/evidence/240/RESULT.md:1)).

V239-01 remains resolved within its measured scope. No new scope expansion, identity/license change, incorrect requirement implementation or self-granted acceptance waiver was found. Required gates keep239/240 incomplete and the integration PR draft.

