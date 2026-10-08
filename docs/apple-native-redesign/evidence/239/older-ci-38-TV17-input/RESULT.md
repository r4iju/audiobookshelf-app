# StockTV17 native keyboard input correction

Actual source38f647e3, Xcode16.2/Swift6/SDK18.2: original-minimum iOS14 binary build passes (not14 execution), stock14.5 capability remains blocked. TV app minimum17 and normal Xcode ad-hoc app/runner strict signatures pass. Corrected private CA and Keychain sign-in now work. Original Catalog continue-listening→detail→native Back case passes47.799s. No other selected journey is claimed passed.

Next original server-search case sends one native `app.typeText("Tomorrow 61")` event. Actual SearchField.value is `Tmorrow 61`; UI correctly displays no matches for that malformed query. Original result assertion fails; xcodebuild later traps133 in result building. This is not a passed/skipped search and not a production query-normalization request.

Existing TVJourney.search now sends individual characters through the same native keyboard, waits at most3s for each actual SearchField.value prefix, and asserts the complete value before unchanged result/focus/request assertions. No query injection, server match fabrication, typing repair loop, arbitrary sleep or assertion relaxation. All five callers start with a fresh query. Native focus prerequisite and original continueAfterFailure=false remain. SearchView keeps its standard @State binding, native searchable,400ms task debounce and stale-result guard unchanged; no production edit.

Actual hosted retry is decisive and remains pending at this handoff. No local devices, fixtures, screenshots or additional verification run was started for this QA-only correction. Runtime remainsf922; historical f635/f922 product/resource manifests are preserved exactly. Parent owns CI/pushes/reviews and unresolved spoken14.5/contrast gates.
