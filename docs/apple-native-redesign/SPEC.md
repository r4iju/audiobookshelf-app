# Audiobook Loft: complete native Apple interface redesign

## Problem Statement

Audiobook Loft's Apple apps still feel like a collection of individually styled screens. The previous Liquid Glass pass updated navigation chrome and buttons, but retained much of the old composition: primary destinations hidden in account menus, manually embedded search, crowded toolbars, inconsistent cards and typography, and a player assembled from separate glass actions. Passing functional tests did not establish a coherent Apple interface. The owner installed the private iPhone build and identified this gap.

The user wants the existing iPhone, iPad and Apple TV apps redesigned properly around Apple's current interface conventions. They need clear navigation, intentional hierarchy and familiar interactions throughout the product, while retaining their accounts, listening, downloads and reading. Success is a complete native experience, not a count of glass modifiers.

## Solution

Rebuild the Apple presentation and navigation around stable platform-native destinations, system search, adaptive content composition and a unified listening experience. Apply genuine Liquid Glass sparingly to navigation and important controls on supported systems. Keep artwork, catalog content and reading pages visually stable. Preserve Audiobook Loft's identity and origin disclosures without imitating an Apple product or implying affiliation.

Ship reviewed Apple source and private device candidates only after both functional and visual acceptance pass. Keep public App Store/TestFlight distribution behind the existing rights and release gates.

## User Stories

1. As an iPhone listener, I want main destinations visible in native navigation, so that I can browse without hunting through an account menu.
2. As a listener, I want Listen Now to show my continuing books and podcast episodes, so that I can resume quickly.
3. As a listener, I want Library to make the selected library clear, so that I know which catalog I am browsing.
4. As a listener, I want to change libraries through a clear library control, so that I can move between books and podcasts.
5. As a listener, I want collections and playlists reachable from Library, so that saved groupings feel part of my library.
6. As a listener, I want Downloads to be a main destination, so that offline listening remains easy to find.
7. As a listener without a server connection, I want saved downloads to remain accessible, so that navigation does not strand my offline media.
8. As a listener, I want Search to use familiar system search interactions, so that typing, clearing, submitting and returning behave as expected.
9. As a listener, I want search scope to show the current library, so that results are understandable.
10. As a listener, I want search results grouped by books, episodes, authors and series, so that I can scan them easily.
11. As a listener, I want sorting, filtering and layout controls grouped by purpose, so that toolbars stay clear.
12. As a listener, I want cover grids and list rows to share consistent metadata hierarchy, so that I recognize the same title across screens.
13. As a listener, I want book and podcast details to emphasize the title and main action, so that starting or resuming is obvious.
14. As a listener, I want loading, empty and failed states to look intentional, so that I understand what is happening and can recover.
15. As a listener, I want a compact player integrated with navigation, so that browsing and playback controls do not overlap.
16. As a listener, I want one clear expanded listening screen, so that artwork, chapter information, progress and transport are easy to understand.
17. As a listener, I want secondary playback actions organized into meaningful controls, so that the player does not become a wall of glass buttons.
18. As a listener, I want chapter and whole-book positions to remain distinguishable, so that seeking stays predictable.
19. As a listener, I want chapters, bookmarks, speed and sleep timer controls to remain available, so that redesigning the player removes no capability.
20. As a listener, I want my playback preferences and paused or playing intent retained, so that switching screens does not change listening unexpectedly.
21. As an iPad listener, I want a real sidebar with the same destinations as iPhone, so that the larger layout is more useful.
22. As an iPad listener, I want detail and selection state retained when my window changes size, so that multitasking does not reset my work.
23. As an iPad listener, I want narrow windows to provide reachable navigation and player controls, so that every action remains usable.
24. As an iPad listener, I want content to use the available width deliberately, so that the app avoids both stretched rows and a narrow phone layout floating in empty space.
25. As a reader, I want PDF and EPUB controls to follow the same presentation rules, so that reading feels integrated with the app.
26. As a reader, I want text and document pages to remain unobscured by glass, so that reading stays comfortable.
27. As a reader, I want reading preferences and contents presented in native sheets or panels, so that settings are easy to change and dismiss.
28. As a listener, I want download status, retry, cancellation and removal actions to be distinct, so that a row never runs the wrong action.
29. As a podcast listener, I want episode details, feed selection and queue status to be consistent with the catalog, so that downloads and listening fit one interface.
30. As a listener, I want Settings to contain clearly grouped account, playback, reading, network and appearance preferences, so that I can find a setting by its purpose.
31. As a listener, I want statistics, year in review and diagnostics to be clearly discoverable, so that these existing features are preserved.
32. As a listener signing in, I want a calm native connection form and actionable errors, so that initial setup feels as polished as browsing.
33. As a listener with expired authentication, I want a focused recovery flow that preserves saved work, so that I can return to listening safely.
34. As an Apple TV listener, I want a bounded set of native destinations, so that many server libraries do not create an unmanageable tab strip.
35. As an Apple TV listener, I want focused artwork and controls to remain obvious across the room, so that I know what the remote will activate.
36. As an Apple TV listener, I want Back to restore the prior selection and focus, so that browsing feels predictable.
37. As an Apple TV listener, I want native search, a clear player and reachable settings, so that every TV screen follows the same hierarchy.
38. As a VoiceOver user, I want correct labels, values, grouping and traversal, so that the interface works beyond its visual appearance.
39. As a listener using larger text, I want content to reflow without clipping or hidden actions, so that all features remain usable.
40. As a listener using Reduce Transparency, increased contrast or Reduce Motion, I want the interface to respect those choices, so that accessibility does not depend on a glass effect.
41. As a listener using another language, I want long translations and right-to-left layouts to fit naturally, so that localization is part of the design.
42. As a listener, I want light, dark, black and system appearances retained, so that my existing preference still works.
43. As a listener on an older supported system, I want a coherent native fallback, so that the redesign does not silently remove device support.
44. As an existing user, I want credentials, downloads, bookmarks, listening history and reading locations retained across an update, so that installing the redesign is safe.
45. As an owner testing the app, I want the finished private build installed on my paired devices, so that I can evaluate the actual interface before public release.
46. As a maintainer, I want independent visual review of complete journeys, so that a functional test pass cannot conceal unfinished composition.
47. As a user, I want the app's Audiobookshelf origins and license notices retained, so that its independent identity stays transparent.

## Implementation Decisions

- Scope is the existing iPhone/iPad and Apple TV products. This is a presentation and navigation replacement; domain stores, media delivery, synchronization, persistence and compatible server contracts remain authoritative. No schema or server API changes are planned.
- iPhone uses five stable native destinations: Listen Now, Library, Downloads, Search and Settings. Existing statistics/year in review and diagnostics are discoverable within appropriately labeled Settings groups. Account actions belong in Settings, with a contextual library chooser in Library. Collections and playlists are visible Library sections or destinations, not account-menu entries.
- iPad presents those same destinations in a native adaptive sidebar and detail layout. Navigation state is owned by the app shell, separately from playback state. Switching destinations preserves relevant selections; resizing between sidebar and compact navigation preserves the current detail and returns to the same catalog position. Use availability-appropriate native tab/sidebar APIs rather than drawing a substitute tab bar.
- Library and Search use the selected server library and expose that scope clearly. Downloads remains available through server failure and reauthentication. Saved account/server identity continues to delimit cached content; changing navigation does not mix accounts or invent new persistence keys for existing data.
- Apple TV has a bounded native shell: Listen Now, Library, Search, Now Playing when applicable, and Settings. Library selection happens inside Library rather than creating one top-level tab per server library. Preserve any existing multi-library search scope, remote Play/Pause, Back and focus restoration. Do not introduce mobile-only offline features to TV.
- Replace the fixed-height, manually embedded mobile search wrapper with system-managed search attached to its native destination. Preserve debounce, keyboard submission, clear/cancel, result pagination, localization and accessible identity. Search and result navigation must work through keyboard appearance, dismissal and destination changes.
- Define a coherent hierarchy for cover grids, list rows, continue-listening items, detail headers, episode rows, forms and empty/error states. Use semantic text styles, system colors and platform spacing conventions. Content-specific grids remain custom where useful, with adaptive sizing and shared composition. Every remaining custom layout must serve a content or interaction need rather than reproduce system chrome.
- Catalog/detail content emphasizes cover, title, author or podcast, listening state and one primary action. Keep metadata and destructive/server actions subordinate. Organize sort/filter/layout controls through native toolbar groups and menus without competing floating capsules or redundant navigation controls.
- Place the compact player using the native bottom accessory/bar mechanism where supported, with a coherent availability fallback. It must coexist with the tab bar, keyboard, safe areas and iPad resizing. Retain accessible expansion and transport actions. Its presence cannot cover catalog rows, reader text or destination controls.
- Compose the expanded player as one listening surface with artwork, item/chapter context, clear progress and primary transport. Group secondary functions into a compact native action area and contextual sheets/panels. Avoid independently glassing every secondary action. Preserve all speed, chapter, bookmark, sleep, locking, seeking, skip and playback-setting capabilities, including existing numerical ranges and persistence.
- Reader, download, podcast, group-management, statistics, year-review, diagnostics, settings and account screens use the same navigation and content hierarchy. Use native Lists/Forms for ordinary rows, native sheets/popovers appropriate to device size, and bounded reader chrome. Do not force a decorative card around every piece of text or add glass behind document content.
- Use system-provided Liquid Glass in navigation and standard controls on OS 26+; prefer native button styles over custom glass backgrounds. Any essential custom glass surface uses documented availability, grouping and scroll-edge behavior. Do not paint over system navigation backgrounds or layer glass surfaces unnecessarily. Preserve readable artwork and solid content surfaces.
- Reduce Transparency, increased contrast and Reduce Motion affect the complete presentation, including system and custom controls. Prefer system adaptation. Fallback buttons preserve independent row activation and inherited semantics. Color must not be the sole carrier of playback, selection, error or focus state.
- Preserve source minimums iOS14 and tvOS17 with coherent availability branches. The installed Xcode27 build-only iOS15 override is a toolchain limitation, not proof of iOS14 support. Obtain an appropriate toolchain for the original minimum or report the support gate honestly; do not silently raise the source or claimed binary minimum.
- Preserve native bundle IDs, URL schemes, entitlements, keychain identities, download locations, listening/reading journals, existing preference keys and origin/license notices. Existing accessibility identifiers survive where their semantic control survives; new native roles may change test locators with observable behavior and assertions intact. Update localization for new destination labels and explain partial translations as today.
- Remove superseded Apple presentation wrappers, manual search chrome, navigation routes and duplicate styling after their replacements land. Retain necessary platform fallbacks and domain logic. No dormant old screen implementation is left selectable by a feature flag.
- Before broad screen implementation, build an executable native design slice spanning the app shell, catalog/detail and compact/expanded player on phone/tablet, plus TV shell/catalog/player. Use real fixture content and system controls, not static web mockups or Apple artwork copied into the app. Capture current and proposed actual screens and review the hierarchy, interaction and material use against the visual rubric below. This is a design checkpoint, not a request for another user confirmation.
- Completion requires coverage of every existing Apple-facing flow, reviewed source, source-pinned private signed device candidates and installation on reachable owner devices. Publishing public App Store or TestFlight binaries remains separate and gated; this redesign grants no copyright exception.

## Testing Decisions

- The primary seam is the actual installed app UI, driven through existing XCTest mobile journeys and TV remote journeys against owned synthetic server/media fixtures. Use the same journeys for functional and visual acceptance. Retain existing native unit/package checks for domain preservation, without adding tests that mirror view modifiers, padding constants or route implementation.
- New externally observable navigation behavior, such as persistent destinations, per-destination selection retention and bounded TV libraries, must first fail through that UI seam before implementation. Existing test locator updates must follow an observed old-locator failure and retain behavioral assertions. Tests must not be backfilled green after the code change.
- Use existing connection/recovery, catalog/search/related items, listening, offline/download storage, reader, group/feed, localization, contrast, diagnostics and TV readiness/focus journeys as prior art. Exercise their new visible entry points rather than retaining hidden old routes only for tests. No production backend, owner media or real credentials belong in synthetic test fixtures.
- Produce an inventory of existing Apple screens and capabilities with their new destination, relevant preserved behavior, visual evidence and acceptance result. A forgotten reader, account or utility screen is an incomplete redesign even if the main catalog looks finished.
- Apply a concrete visual acceptance rubric to actual running builds: primary destinations are visible and stable; hierarchy distinguishes navigation, primary action, metadata and secondary actions; system search and bars control their own size; spacing and type roles are consistent; artwork/text remain readable; no competing glass layers, clipped labels, stretched rows, unreachable controls, overlapping keyboard/player/tab bar, or arbitrary pill-button wall remains. Custom content composition is allowed and must explain a visible product need.
- Require an independent visual reviewer with fresh context to inspect complete phone, tablet and TV journeys against Apple's primary guidance, the screen inventory and this rubric. Record findings by screen and resolve confirmed defects before declaring the redesign complete. Code review and test totals cannot substitute for this visual review.
- Capture actual iPhone and iPad light/dark/black states, cover-rich and missing-artwork catalogs, long titles, empty/loading/failure states, expanded/compact players, search with keyboard, readers and Settings. Include long translations and right-to-left content. Keep each image tied to the exact source/build and device/runtime; use synthetic content for shared evidence.
- On iPad, verify an actual narrow multitasking/window geometry and a wide layout. Open a detail, resize, use sidebar/compact navigation, return to the same selection, expand/dismiss the player, and reach tab/search controls with the keyboard visible. Portrait screenshots and scaled images do not satisfy compact-window acceptance. The earlier automation failure must be resolved through a reliable existing UI/platform seam, or this requirement remains blocked and cannot be marked passed.
- Verify largest Dynamic Type through real typing, clear/cancel, keyboard Search, result opening/Back, player secondary controls, preference rows and reader actions. Screen captures alone do not establish activation. Cover artwork may retain aspect ratio; adjacent essential title/metadata and accessible descriptions must remain complete.
- Enable Reduce Transparency, increased contrast and Reduce Motion in the actual OS, verify the setting state and run relevant interactions with them combined. Validate legibility, scroll-under behavior and independent Retry/Remove/Play actions. Preserve the existing measured contrast audit without adding dismissals to conceal a design defect.
- Run TV remote traversal through library selection, catalog, details, search, related content, player and settings, including Back restoration, Play/Pause, long notices and many server libraries. Inspect focused and unfocused controls at viewing distance. Use the existing TV accessibility audit without weakening it.
- Verify VoiceOver roles, values, selected/disabled states, group order, errors and recovery. Actual spoken traversal should be tested on reachable private owner devices with a synthetic account. If hardware or tooling prevents a required check, keep it explicitly pending; do not convert AX snapshots into a claim of spoken VoiceOver acceptance.
- Re-run relevant offline and durable listening/reading journeys after navigation changes: switch destinations while audio plays, relaunch, recover unsent listening, restore downloaded audio/PDF/EPUB and recover expired authentication without erasing saved content. Verify navigation never starts, stops, duplicates or reassigns a listening session unexpectedly.
- Build simulator and signed private device candidates for both Apple products. Verify supported fallback branches with an appropriate available runtime/toolchain and document actual binary minimums. Use pooled simulators, release leases and stop owned fixtures. Source/build/signature verification and direct install/launch are separate from functional acceptance.
- Replay representative journeys on the merged source and install the matching private candidate on reachable paired owner devices. Preserve owner data and allow manual use. Do not claim hardware playback, background behavior or a polished private experience from installation alone.
- Every acceptance result identifies source, device/runtime, fixture, command or interaction and evidence. Product failures, test-harness failures and unavailable capabilities are distinguished. Required checks that cannot run remain pending; no source or candidate is called fully accepted while a required visual or interaction gate is unresolved.

## Out of Scope

Android, the browser and backend; new macOS/watchOS/visionOS products; changes to server schemas/APIs or media processing; new playback or reading capabilities; credential/data migrations; a brand or bundle-ID change; dropping supported OS versions; changing inherited licenses or enabling Google Cast; public Apple uploads without rights/terms clearance; copying Apple's proprietary icons, artwork or product branding.

Creating implementation tickets and executing the redesign are later workflow steps. This invocation produces and publishes the complete spec.

## Further Notes

This spec supersedes the completeness assumption of the earlier Apple Liquid Glass scope, tracked in https://github.com/r4iju/audiobookshelf-app/issues/222 and delivered in https://github.com/r4iju/audiobookshelf-app/pull/229. The prior work remains useful functional and compatibility evidence; it is not the visual acceptance baseline for the completed redesign. Preserve that historical spec, issue and evidence unchanged.

The user already authorized Apple-only work without interviews, seam confirmations or ticket confirmations. That instruction carries forward: the actual-app UI seams above are the established expectation, so no additional confirmation is requested.

Primary references, to be checked against the SDK used for implementation:
- Apple's adoption guide: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Custom control guidance: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines

Audiobook Loft is an independent app with Audiobookshelf origins. The Cast/Apple additional-permission request remains separate at https://github.com/advplyr/audiobookshelf-app/discussions/2051; silence, this spec, private installation and store acceptance do not constitute a copyright grant. No maintainer outreach or public distribution is part of writing this spec.
