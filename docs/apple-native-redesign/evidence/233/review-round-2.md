# Independent visual checkpoint #233, round 2

**PASS for the executable design checkpoint.** The three confirmed round-1 composition defects are resolved in actual rendered evidence. Broad screen migration may proceed. This is not full redesign, private-candidate, signature, older-OS or accessibility acceptance.

Reviewed integration `d82e2e28ded94c9cdc773bdb4cadb350b05a3a28`. Corrected mobile runtime `8739a7b49b43a11950981eae7ffeb162c43d1ce0`, evidence `a8e2e6d0`; unchanged TV runtime `5acca8c1a39cdcf9525e67874583651eef9e6900`. Fresh reviewer did not implement the slices or corrections. Read-only review: no source, test, repository document, index, tracker, PR, device, fixture or simulator changes. Only this temporary report was written.

Read personal context/preferences, SPEC.md, INVENTORY.md, STATE.md, tickets/03.md, round-1 findings, 231/232 RESULT records and 233 correction/TV records. Images listed below were actually opened with view_image. Current Apple primary guidance was checked through the web tool; the adoption guide's readable Apple Markdown was consulted for Search. API names and test totals did not determine the visual decision.

## Findings and responses

**D1 resolved.** `iphone-library-search-inactive.png` and `iphone-search-cancelled.png` show four primary destinations and a separate trailing native Search control. `iphone-search-active-keyboard.png` and `iphone-search-results-keyboard.png` show the field immediately above the real software keyboard, not at the remote top edge. Scope is visible as Audiobooks. Typed results, submission with keyboard dismissed, clear returning to the empty prompt, and Close returning to Library are separately captured. The former five-tab ghost group is gone. A faint collapsed previous-destination glyph remains under the keyboard's lower-left translucent surface. It does not form a competing labeled navigation strip or obscure a key/field in these frames. I find no demonstrated app-level defect requiring custom suppression of this native rendering. This is a bounded visual judgment, not proof of all keyboard hit regions or accessibility behavior.

The wide iPad keyboard captures now exist. They show the appropriate upper-trailing toolbar field, visible selected Search destination, scope and result above the software keyboard. The field's long placeholder truncation is ordinary native placeholder fitting, with scope separately visible; it is not essential metadata loss. The empty frame's sidebar labels are partly affected by native active-search presentation, while the typed result frame clearly retains all destinations. No vanished destination claim is inferred from one raster. Actual destination switching and keyboard dismissal are supported by the retained final-source iPad Shell replay, not screenshots alone.

**D2 resolved.** `ipad-detail-actions.png` shows artwork paired with title/author/context and an intrinsic Resume listening action, rather than a full-pane 852pt button. Finish, offline and destructive discard actions form one subordinate row directly below that header action, followed immediately by progress. Description and chapters have their own hierarchy below. The resulting row is plain adjacent text controls; ControlGroup's name alone is not evidence. In pixels, labels are complete and visually distinct, destructive discard is differentiated, and the row is coherent with the primary action rather than three unrelated stretched lines. Exact inter-button gaps are a potential styling preference, not a confirmed defect at this normal width. Largest text, localization, independent activation and compact reflow remain later mandatory interaction checks.

**D3 resolved.** `iphone-player-tools.png` shows Chapters/1x and Bookmarks/Sleep timer as two readable native rows with complete labels, normal text and icon identity. Bookmarks no longer breaks mid-word. Playback settings and Close playback remain below. `iphone-player-overview.png` prioritizes artwork, title, chapter/file context, whole-book versus chapter progress and transport. The second tool row requires scrolling at this normal viewport; the paired captures explicitly demonstrate that reachable scrolled composition, rather than hiding functions or claiming every action fits without scrolling. All tool activation, largest-text and persistent preference checks remain #235/#239.

**No new confirmed current-slice design blocker.** Library hierarchy, continuing shelf, visible collections/playlists, aligned equal artwork canvases and readable metadata remain coherent. The selected library is prominent. Native toolbar control density is bounded. Portrait artwork fitting within equal canvases is intentional and does not justify cropping merely to make the visible artwork widths equal. Compact player is visually separated from destination navigation; it remains above the phone tab group. Content can scroll beneath translucent navigation, which is not by itself proof of unreachable rows. Complete final-row reachability belongs to actual later interaction acceptance.

Wide sidebar composition and the earlier unchanged two-column expanded player remain purposeful. The latter is contextual source0894 evidence, not a new8739 capture; corrections concern narrow tool composition. Do not represent it as a final-source recapture.

TV bounded root, chooser beginning/end, catalog focus and player composition remain acceptable in the unchanged final runtime's rasters. Focused catalog author is visibly bright and the card changes enlargement/background/border, while unfocused metadata is subordinate. Player transport sits alongside artwork/context/progress, with a distinct secondary row and destructive Stop. Focused Play is clearly distinguishable. The new portrait-detail pair supplies the missing state: full-fit art stays consistent, Resume changes from subdued orange text/fill to bright focused fill with dark text, and title/context remain readable. These are raster observations, not across-room physical hardware or spoken VoiceOver results.

## Behavioral and provenance limits

The recorded final mobile replay has six passing tests, including immediate Search input, episode-only search/play, beyond-page result/Back, sorting/filtering, destination/detail/library retention and fractional bookmark deletion. The final wide iPad Shell replay passes1/1 after an observed real keyboard-dismissal failure and correction. The earlier iPad bookmark pass was on da05a80a and is not claimed as final8739 replay. TV additional portrait capture replay passed1/1 with existing shell assertions retained. This reviewer did not execute these tests and distinguishes the original recorded logs from visual inspection.

Mobile source minimum14 remains; SDK27 simulator and unsigned generic binaries use minimum15. Source14 typechecking is diagnostic only. Runtime captures are iOS27.0 and tvOS27.0; TV binary minimum17 does not establish execution17.

The installed phone and current build product have a recorded codesign sealed-resource failure naming modified Assets.car. Tablet bundle verification passes. Recorded executable/debug-library hashes match between phone/tablet and final runtime mapping, but equal code hashes do not establish integrity of every resource. No release/signature pass is granted. This caveat does not erase the directly observed system search geometry and app layout: all inspected artwork is synthetic server-fixture content and the controls are visibly rendered native controls. There is no evidence here that an altered asset changed D1-D3. The parent must resolve or precisely diagnose the resource discrepancy before accepting a signed candidate, and a relevant affected visual asset must be recaptured if its origin is uncertain. Do not re-sign a bundle merely to conceal an unexplained mismatch. Bounded #233 design-direction PASS is appropriate while private candidate acceptance stays pending.

#234–238 still own the remaining catalog, listening panels, readers/downloads/groups, connection/settings/utilities and complete TV screens. #239 retains actual narrow-to-wide iPad window interactions, combined OS accessibility settings, largest text and RTL/long translations, spoken VoiceOver, durability/offline/auth recovery and real supported fallback execution. None is waived by this checkpoint. #240 retains independent final review, merged-source QA and private signed installs preserving owner data. No public Apple upload, rights grant, Cast or license conclusion follows.

## Exact viewed coverage

All paths relative to checkout unless stated.

Corrected mobile13, production8739:
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-library-search-inactive.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-search-active-keyboard.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-search-results-keyboard.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-search-submitted.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-search-cleared.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-search-cancelled.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-detail-compact-player.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-player-overview.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/iphone-player-tools.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/ipad-library.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/ipad-search-software-keyboard.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/ipad-search-results-keyboard.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/ipad-detail-actions.png`

TV portrait pair, production5acca:
- `docs/apple-native-redesign/evidence/233/corrections-round-1/tv-portrait/archive-detail-focused.png`
- `docs/apple-native-redesign/evidence/233/corrections-round-1/tv-portrait/archive-detail-unfocused.png`

Unchanged TV232 evidence, production5acca:
- `docs/apple-native-redesign/evidence/232/screens/after-many-libraries-shell.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-focused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-unfocused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-now-playing-focused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-now-playing-unfocused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-chooser.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-chooser-end.png`
- `docs/apple-native-redesign/evidence/232/screens/after-multi-library-search.png`

Historical mobile context, production0894, not final corrected source:
- `docs/apple-native-redesign/evidence/231/after-iphone-library-covers.png`
- `docs/apple-native-redesign/evidence/231/after-iphone-compact-player-covers.png`
- `docs/apple-native-redesign/evidence/231/after-ipad-library-covers.png`
- `docs/apple-native-redesign/evidence/231/after-ipad-expanded-player-covers.png`

The equivalent portrait pair was also opened first at `/tmp/native-tv-233-portrait-unfocused/archive-detail-{focused,unfocused}.png`, then opened again at the committed paths above. Their source/binary/capture manifest was read. Mobile screenshot and simulator-build manifests were read; resource caveat retained.

## Primary guidance

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), current Apple page checked and Apple Markdown `/tmp/apple-adopting-liquid-glass.md` Search section read: appropriate platform search placement, keyboard movement and semantic trailing Search.
- [Searching](https://developer.apple.com/design/human-interface-guidelines/searching), current official JSON read at https://developer.apple.com/tutorials/data/design/human-interface-guidelines/searching.json: single clear entry and visible scope.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), current official JSON checked at https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.json: adaptation, alignment and hierarchy.
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), current official JSON checked at https://developer.apple.com/tutorials/data/design/human-interface-guidelines/buttons.json: understandable actions and prominence.

No Apple exact-width or padding rule is invented. No proprietary artwork copied. No subjective palette preference is promoted into a blocker. There are zero remaining confirmed must-fix composition defects for this bounded checkpoint; completion of the full spec remains pending.
