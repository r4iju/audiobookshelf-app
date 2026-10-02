# Android visual consistency

Scoped UI finishing for [#130](https://github.com/r4iju/audiobookshelf-app/issues/130), based on `d2d7543be26f7e9a70c9508008ba6fb6ce3f3c0c`.

| Before | After |
| --- | --- |
| Brown/cream surfaces in dark, black and light modes | Neutral charcoal, black and grouped light surfaces |
| Pastel dark primary controls and brown secondary containers | Apple-style orange accent with contrast-safe foregrounds; neutral chips, menus and outlines |
| Orange library title competing with shelf headings | Neutral library identity and orange disclosure affordance |
| Progress-bearing cards shifting title/author baselines | Equal progress, two-line title and one-line author slots |
| Narrow fixed shelf/grid widths | Shared font-scale-aware artwork widths and 16/24 dp spacing |
| Catalog heading squeezed beside three actions | Full-width heading above an aligned control row |
| Search text using generic row styles | Rounded input, consistent 64 dp covers and explicit title hierarchy/ellipsis |
| Detail stretching across large screens; cramped chapter timestamps | Bounded content, scale-aware stacked header and grouped chapter rows |
| One-line group names and competing compact actions | Two-line names, consistent covers and wrapping action layout |
| Unbounded message text and fixed-height connection actions | Bounded status content, neutral icon tiles adaptive minimum-height buttons and safe-area insets |

Reference: Apple `ShelfStyle`, accent assets and current `BookCard`/`ContinueCard`; web semantic colour tokens, `MediaCard` and item detail. Android retains native navigation, Material controls, square artwork frames and existing interactions.

Validation: local offline `:app:assembleDebug` passed at `c9086e328d00375e2dc663f6c6b702b1291ced1d`, app source tree `4e45ffea9defdb345b37f698b34970c75d4081e6`. `git diff --check` passed. Primary text/fill contrast calculates to 5.44:1 light and 6.66:1 dark. One synthetic API 36 emulator pass inspected 411 dp/100% dark phone, 320 dp/150% phone and 800 dp/100% light tablet: library cards and controls, list/grid switching, detail/chapters, author-filtered grid, search results/no-results, groups, connection/sign-in form, long titles and temporary error/retry recovery. Screenshots exposed two corrections (light chapter tone and connection safe-area insets), which were built and checked locally in the same pass. Earlier browse captures have identical final component inputs; corrected detail/form captures identify their respective builds. Cached artwork remained visible in the long-title scenario; fresh missing-artwork acceptance is not claimed.

No new tests for visual-only changes. Playback/progress/download callbacks, resource values, migration and UX-owned source remain unchanged. Private screenshot/log evidence is retained outside the repository. Root handles fresh review and combined delivery; existing physical-device, migration, localization and baseline-lint gates remain open.
