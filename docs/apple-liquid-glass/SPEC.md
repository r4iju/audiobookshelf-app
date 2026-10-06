# Apple Liquid Glass redesign

## Problem Statement

Audiobook Loft’s Apple apps use dated custom cards and navigation chrome rather than Apple’s current Liquid Glass design language. The user wants every existing Apple app modernized and shipped independently, with no changes to Android, the browser or backend.

## Solution

Redesign the iPhone/iPad and Apple TV presentation around native SwiftUI navigation, adaptive layouts and genuine system Liquid Glass for appropriate control surfaces. Preserve all existing account, catalog, playback, offline, reading and synchronization behavior.

## User Stories

1. As a listener, I want to recognize a modern Apple interface on iPhone, iPad and Apple TV, so that the app feels at home on each device.
2. As a listener, I want to navigate libraries with native platform chrome, so that content remains the focus.
3. As a listener, I want to use a floating compact player, so that I can control playback while browsing.
4. As a listener, I want to open a clear expanded player, so that transport and chapter controls are easy to use.
5. As a iPad listener, I want to use the available screen width and multitasking sizes, so that navigation stays comfortable.
6. As a TV listener, I want to see focus move clearly with the remote, so that I always know which action will run.
7. As a TV listener, I want to read titles and controls across the room, so that glass never obscures essential content.
8. As a reader, I want to read PDF and EPUB without distracting glass behind text, so that long reading sessions remain comfortable.
9. As a listener, I want to search and filter with native controls, so that I can find my books quickly.
10. As a listener, I want to manage downloads and podcasts in the same visual language, so that offline and queued work stays understandable.
11. As a listener, I want to sign in and recover expired credentials clearly, so that I can return to my saved listening.
12. As a listener, I want to manage accounts and settings without losing data, so that the redesign is safe to install.
13. As a listener using VoiceOver, I want to hear accurate labels and control states, so that I can navigate and listen independently.
14. As a listener using larger text, I want to see controls without clipped labels, so that all actions remain reachable.
15. As a listener using Reduce Transparency, I want to get legible opaque control surfaces, so that glass does not compromise accessibility.
16. As a listener using Reduce Motion, I want to avoid unnecessary motion, so that the app respects my preferences.
17. As a listener on an older OS, I want to keep a coherent native fallback, so that I do not need a new device.
18. As a listener, I want to keep light, dark and black appearance choices, so that my existing preferences remain respected.
19. As a listener, I want to keep offline playback and progress recovery, so that the redesign does not lose my listening.
20. As a maintainer, I want to have verified screenshots and release evidence for each Apple platform, so that the redesign is reviewable.
21. As a user, I want to see the app’s origins and license notices preserved, so that the independent app remains transparent.

## Implementation Decisions

- Scope covers the existing iOS/iPadOS and tvOS apps only. There is no existing standalone macOS/watchOS/visionOS app to create.
- Use current installed Apple SDKs and documented public APIs. Prefer system navigation, toolbars, buttons, sheets and focus behavior over custom replicas.
- Adopt genuine Liquid Glass on OS 26 and newer where supported; preserve existing minimum deployment targets with availability-guarded native fallbacks.
- Restrict glass to navigation and controls. Cover art, catalog rows and reading content remain clear, stable content surfaces. Do not layer glass unnecessarily.
- Introduce small platform presentation helpers only where custom controls need consistent availability and accessibility handling. Do not rewrite domain stores, persistence or API contracts.
- Modernize sign-in/recovery, library browsing/search/detail, compact and expanded playback, reader controls, downloads/podcast actions, statistics/settings and TV navigation/player controls.
- Preserve accessibility identifiers, localization, Dynamic Type, VoiceOver semantics, remote focus/Back/Play-Pause, appearance preferences and existing credential and offline storage identities.
- Respect Reduce Transparency, increased contrast and Reduce Motion. Preserve content readability and hit targets in fallback appearances.
- Preserve licensing and origin disclosures. Source merge and verified local Apple builds are authorized. Public Apple distribution remains gated by actual rights/terms approval; this redesign does not grant permission or bypass that gate.

## Testing Decisions

- Use the existing Apple and TV UI journey seams with synthetic accounts and fixtures. Verify externally observable navigation, playback, offline/recovery and accessibility rather than private view implementation.
- Any new behavioral test must be written and observed failing before implementing that behavior. Do not add tests that merely assert modifier names or mirrored constants.
- Build both apps for simulator and unsigned device/archive as supported; run relevant existing native and UI checks. Capture actual iPhone, iPad and TV screens using pooled simulators and the shared device panel.
- Inspect light/dark, large text, reduced transparency/motion, iPad compact/wide layouts and TV focused controls. Record any untestable physical-device limitations truthfully.
- Keep Android, web and backend source unchanged. Validate scoped diff and document exact source/build evidence.

## Out of Scope

Android, browser, backend, new Apple platform products, data migrations, bundle/account identity changes, new playback features, license changes and unapproved public Apple uploads.

## Further Notes

The user explicitly authorizes no interview, seam confirmation or ticket confirmation. Apple’s adoption and custom-view guidance are primary design references:
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

Ship the reviewed source and verified Apple candidate builds; report actual external distribution blockers without claiming App Store publication.
