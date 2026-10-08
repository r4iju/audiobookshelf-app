# Independent visual checkpoint #233, round 1

**BLOCKED.** Correct the current phone Search composition and wide-iPad detail action composition before broad #234–238 migration, then obtain fresh independent rendered review. Phone player label wrapping is an additional current-slice polish defect to resolve in that correction. This is a design checkpoint decision, not a rejection of the already passing functional journeys or a claim that all #239 gates should run now.

Reviewed integration: `ae3f927d741a4b51cfa7576920bd049947e84dbc`, `feature/apple-native-redesign`. Phone/tablet production source `0894eb047a5319294dcc5e1d41f976f7eb1f4bf5`, evidence `f1116e66`; TV source `5acca8c1a39cdcf9525e67874583651eef9e6900`, evidence `5f48fdd0`. Draft PR #241 targets `fork/native-tv`. Reviewer did not implement either slice. Source, PR, tracker, spec and inventory were not changed. Only this temporary report was written.

Read Git common directory `/Volumes/ai-ssd/code/audiobookshelf-app/.git`, personal AI context and global preferences; SPEC.md, INVENTORY.md, tickets/03.md, STATE.md and both RESULT.md files. Build records and TV capture manifest associate final images with binaries. Images were actually opened with `view_image`, not inferred from source. No tests, fixtures, simulator leases or app interaction were started for this review.

## Must fix in the current executable slice

### D1, high: phone Search still uses the old top-field/attached-tabs composition

Evidence: `docs/apple-native-redesign/evidence/231/after-iphone-search-software-keyboard.png`, supplemented by `after-iphone-library-covers.png` and `after-iphone-detail-covers.png`.

The active search field sits at the very top, well away from the software keyboard. The five-tab group remains visibly ghosted underneath the bottom keyboard area. In the normal Library/detail frames Search is attached to the other four tabs rather than occupying a separate trailing search section. The keyboard frame alone does not prove blocked taps or broken submission, and I am not alleging those failures. It does establish the actual geometry.

This is a concrete current design-direction defect, not a claim that every supported older iOS search controller is invalid. The slice is being reviewed on the latest OS for a current Apple redesign. Apple's [Adopting Liquid Glass, Search](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) explicitly describes bottom phone search moving above the keyboard and semantic search-tab separation; tablet search belongs in the toolbar. The SPEC requires familiar system search, distinct native navigation and no keyboard/player/tab-bar overlap. No content-specific need for overriding this placement is apparent in this global catalog Search destination. System API names do not cure the visible mismatch.

Minimal requirement: on the current phone OS, let the platform choose the bottom Search presentation and make the search tab a separated trailing semantic search destination. Show fresh inactive and active/software-keyboard captures with the field immediately above the keyboard and without a lingering navigation group competing beneath it. Retain native appropriate tablet search and availability fallbacks; do not draw a custom search bar to imitate the guidance. A bounded type, clear/cancel and submit replay should accompany changed placement; full keyboard acceptance remains #239.

Cause references: `apple/App/LibrarySearch.swift:49` forces `.navigationBarDrawer(displayMode: .always)`. `apple/App/NativeShell.swift:53–60` puts a semantic Search tab in a universally `.sidebarAdaptable` TabView. The latter is a likely configuration interaction, not a proved framework root cause; evaluate phone style and role together and judge the new rendered result.

### D2, medium: wide iPad detail retains an expanded phone action stack

Evidence: `docs/apple-native-redesign/evidence/231/after-ipad-detail-covers.png` and `after-ipad-compact-player-covers.png` (actual 1210×834).

The header adapts into a good artwork/metadata pair, but Resume listening then spans roughly x319–1171 (852 pt), with its label only occupying the leading ~150 pt. Mark unfinished, Discard progress and Download for offline form separate ungrouped lines underneath, followed by a wide blank interval before progress. The substantial trailing space in this action area carries no information or interaction distinction. The result visually treats the broad detail pane as a stretched phone stack, unlike the intentionally two-column expanded player. This is not an objection to having one prominent primary action or to generous hit regions.

SPEC decisions require adaptive detail composition, subordinate secondary/destructive actions and coherent hierarchy; the visual rubric rejects stretched rows. Apple's [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) asks layouts to adapt to available space and express relationships through alignment/grouping. [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) supports prominence through styling and understandable action sets. Neither source mandates a numerical width, and the defect does not depend on copying an Apple app.

Minimal requirement: compose a bounded detail action area tied to the header/content hierarchy at regular width. Give primary listening action a sensible intrinsic or bounded width and group subordinate progress/offline actions in a coherent secondary area or native menu. Keep destructive progress reset subordinate. Preserve the compact layout and all existing actions. A new real wide iPad capture should show that controls use the added width purposefully instead of stretching across the full pane.

Cause references: `apple/App/BookDetails.swift:61–75` uses one leading VStack and a primary label HStack containing Spacer; the secondary buttons and Download at ~121 remain direct vertically separated siblings. Header adaptation does not extend to this action section.

### D3, low: default phone player tools fragment an ordinary label

Evidence: `docs/apple-native-redesign/evidence/231/after-iphone-expanded-player-covers.png`.

The otherwise coherent transport surface has a secondary row where Chapters and 1× fit on one line, Sleep timer wraps naturally, and Bookmarks breaks mid-word into “Book-” / “marks”. This occurs at the supplied normal text size, not an unavailable largest-text setting. The four equal allocations do not fit their ordinary labels, making the tool row uneven and slower to scan.

SPEC requires compact grouped secondary functions, consistent type/spacing and readable labels. Apple's [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) supports grouping and adaptation rather than letting text force an awkward composition. This is a small confirmed composition flaw, not clipping or an inaccessible-control claim.

Minimal requirement: keep complete normal-size labels intact, using an adaptive grouped layout (for example two rows when needed) while retaining icon/text identity and normal hit regions. Do not hide Bookmarks, reduce semantic text size or shrink the text to force the four-across arrangement. Largest text/localization interaction remains #239.

Cause references: `apple/App/PlaybackViews.swift:198–227`, stacked label style and equal max-width allocations in a navigation ControlGroup.

## Rendered qualities that pass this bounded review

The five mobile destinations are consistently visible in normal phone frames and a readable iPad sidebar. Library scope has a strong title; Search visibly names Audiobooks. Library content establishes continuing shelf, group links, All books, artwork/title/author/duration hierarchy. Equal artwork canvases keep metadata columns aligned. Portrait covers are intentionally fitted without cropping; their narrower visible artwork is not unequal-column failure.

Library toolbar contains one contextual library button plus a three-control group (sort/filter/more), with layout beside All books. Density is reasonable in the viewed frames. Utility screens behind Settings/Downloads were not represented as newly redesigned here and do not become checkpoint defects simply because later tickets own them.

Phone compact artwork/title/transport and wide iPad accessory are clearly distinct from content, with no stacked wall of glass actions. A screenshot does not prove final-row reachability; no coverage claim is made for scroll/resize/keyboard activation. Expanded player clearly prioritizes artwork/title, progress and primary transport. iPad two-column player uses width well. The phone tool-label exception is D3. Glass is limited to functional navigation/primary controls; cover art remains a solid content surface.

TV shell remains bounded despite twelve server libraries. Chooser beginning/end identifies current selection with a checkmark and current focus with a native bright row; Archive 10 is visible and selectable in the final frame. Catalog focus has enlargement, border/shadow and a brighter background, not only a color change. In `after-library-focused.png` and `after-library-back-focused.png`, the author is visibly bright primary foreground on the focused card. In `after-library-unfocused.png` it is visibly subordinate gray. The final correction is present in pixels. Square and portrait detail title/metadata/primary Resume are readable. Focused Resume becomes an orange-filled dark-label control; unfocused Resume is visibly less prominent. Portrait fit preserves the cover's full design within the same square canvas.

TV player arranges artwork alongside context/progress/transport and a separate secondary tools row. Focused Play has a bright fill and dark glyph distinct from the unfocused state, and remote action is visually obvious. Chapters/speed/timer/Stop have a coherent lower row; Stop has a distinct destructive treatment. This is functional grouping, not an arbitrary pill-button wall. TV Search uses the recognizable system linear keyboard with result artwork/title below. These statements are bounded raster observations, not viewing-distance hardware, spoken VoiceOver or combined accessibility acceptance.

## Exact viewed coverage

All following paths are relative to the checkout. Every listed image was opened with the image tool.

Phone, final (5):
- `docs/apple-native-redesign/evidence/231/after-iphone-library-covers.png`
- `docs/apple-native-redesign/evidence/231/after-iphone-detail-covers.png`
- `docs/apple-native-redesign/evidence/231/after-iphone-compact-player-covers.png`
- `docs/apple-native-redesign/evidence/231/after-iphone-expanded-player-covers.png`
- `docs/apple-native-redesign/evidence/231/after-iphone-search-software-keyboard.png`

Wide iPad, final (4):
- `docs/apple-native-redesign/evidence/231/after-ipad-library-covers.png`
- `docs/apple-native-redesign/evidence/231/after-ipad-detail-covers.png`
- `docs/apple-native-redesign/evidence/231/after-ipad-compact-player-covers.png`
- `docs/apple-native-redesign/evidence/231/after-ipad-expanded-player-covers.png`

TV, final (12):
- `docs/apple-native-redesign/evidence/232/screens/after-many-libraries-shell.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-chooser.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-chooser-end.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-focused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-unfocused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-library-back-focused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-detail-focused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-detail-unfocused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-archive-detail.png`
- `docs/apple-native-redesign/evidence/232/screens/after-now-playing-focused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-now-playing-unfocused.png`
- `docs/apple-native-redesign/evidence/232/screens/after-multi-library-search.png`

Contextual before (3), not same-fixture art comparison:
- `docs/apple-native-redesign/evidence/231/before-iphone-library-missing-artwork.png`
- `docs/apple-native-redesign/evidence/231/before-ipad-detail-covers.png`
- `docs/apple-native-redesign/evidence/232/screens/before-many-libraries-shell.png`

Unavailable: no separate retained unfocused portrait-detail raster was found. `after-archive-detail.png` shows portrait detail with focused Resume; square detail supplies the focused/unfocused pair. No final wide iPad Search keyboard raster was present. This report does not pretend either missing state was viewed. Provide the missing portrait state during the next capture round; no broad suite rerun is requested. Existing narrow resize, largest-text/combined accessibility, spoken VoiceOver and old-OS acceptance remain explicitly #239 requirements. Phone source minimum14, build override/binary minimum15, TV binary minimum17 with runtime27 only retain the evidence limitations in the RESULT files. Public Apple/Cast/license/owner installation remain outside this checkpoint.

## Primary guidance consulted

- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass (current URL checked; full Apple Markdown read from `/tmp/apple-adopting-liquid-glass.md`, especially Controls, Navigation, Search)
- https://developer.apple.com/design/human-interface-guidelines/searching (current primary content retrieved at https://developer.apple.com/tutorials/data/design/human-interface-guidelines/searching.json, updated June 8, 2026)
- https://developer.apple.com/design/human-interface-guidelines/tab-bars (primary JSON https://developer.apple.com/tutorials/data/design/human-interface-guidelines/tab-bars.json, June 8, 2026; includes iPad sidebar/tab behavior and TV focus state)
- https://developer.apple.com/design/human-interface-guidelines/buttons (primary JSON https://developer.apple.com/tutorials/data/design/human-interface-guidelines/buttons.json, December 16, 2025)
- https://developer.apple.com/design/human-interface-guidelines/layout (primary JSON https://developer.apple.com/tutorials/data/design/human-interface-guidelines/layout.json, September 9, 2026)

Search-fields, sidebars and focus-and-selection page/JSON probes did not expose readable primary content through the web tool. No conclusion is attributed to those unavailable pages. The available Apple adoption guide, Searching, Tab bars, Buttons and Layout cover the actual findings. No secondary-blog conclusions used.

Color palette preference, whether compact-player labels should be centered, and exact cover size are subjective choices, not blockers. D1–D3 identify actual current-slice composition defects. #233 remains BLOCKED until they are corrected and independently rereviewed on fresh source-pinned rendered evidence.
