# Native Apple preview

SwiftUI iPhone/iPad client, connecting directly to the existing server through the shared production API core. The preview identity is `com.forkzed.audiobookshelf.native.preview`, team `C7X9BCC7LP`. Its explicitly scoped Keychain group keeps credentials separate from the working legacy app. Do not change it to the legacy identity until the migration/backup acceptance tickets are complete.

## Local builds

```sh
xcodegen generate --spec apple/project.yml
./apple/scripts/verify-ui.sh
./apple/scripts/deploy.sh --build-only
./apple/scripts/deploy.sh <paired-iPhone-or-iPad-UDID>
```

Create the dedicated simulator with `xcrun simctl create 'Audiobookshelf Native QA' com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0` if absent. The UI journey uses synthetic loopback servers and proves sign-in, library selection, Keychain restoration after relaunch, invalid-address recovery, qualified `.lan` HTTP, and rejection of an untrusted HTTPS certificate. `verify-ui.sh` owns HTTP fixtures on 19765 and 19766 and an untrusted HTTPS fixture on 19767, using synthetic accounts `qa` and `qa-other` with password `qa`. It creates a temporary two-day test certificate and requires the Studio's existing `dev.nginx.lan → 127.0.0.1` alias. It does not install a trust root. Simulator builds must be ad hoc signed with the app's entitlements: disabling signing makes genuine Keychain operations fail with `-34018`. The qualified-host regression was first observed failing with an ATS cleartext-denial message; removing the conflicting `NSAllowsLocalNetworking` key made it pass while normal HTTPS trust remained enforced.

No replacement in-memory credential store is used by the app or UI journey.

Packaging reuses Xcode's local dependency cache and automatically retries a clean local build if strict signature verification rejects cached resources. Both the built app and copied IPA payload must pass signature verification. Use `ABS_CLEAN_BUILD=1 ./apple/scripts/deploy.sh --build-only` when a fresh rebuild is needed. Focused feature journeys reuse the sign-in helper without an extra process restart; authentication journeys and explicit persistence scenarios retain their restart checks.

The provisioning helper uses the existing developer certificate and App Store Connect signing key to register the internal preview and devices. Signing, compilation, packaging and installation execute on the Studio; there is no hosted build or public release. The resulting internal IPA is `apple/build-release/AudiobookshelfNative.ipa`.

Source deployment minimum remains iOS 14. Xcode 27 needs a build-only iOS 15 override; iOS 14 runtime compatibility remains unverified until an appropriate SDK/runtime is available. The override does not authorize changing the final supported audience. TLS uses platform certificate validation; allowing HTTP servers does not accept untrusted HTTPS certificates. Certificate failures explain installation and full-trust recovery.

## Saved accounts and browser sign-in

Saved connections and each connection's selected library live in the preview's Keychain document. Their identity uses canonical server plus server user ID; switching pauses audio, durably retains pending listening, and reloads catalog state for the selected account. An offline switch does not wait for the former server to acknowledge listening. Stream cleanup uses the original server and token; pending journal records are published when that account is selected again. The previous single-preview-login Keychain format is readable without touching the legacy app's credentials.

OpenID uses ASWebAuthenticationSession with PKCE, callback-state validation and the existing server's mobile exchange. An ephemeral HTTP session preserves the server's session cookie between authorization and exchange. Provider browsing is ephemeral. No intermediary authentication service is introduced. When OpenID is enabled, allow `audiobookshelf-native-preview://oauth` in the server's mobile redirect URI settings. This preview scheme leaves the legacy app's `audiobookshelf://oauth` registration intact.

Production UI journeys exercise two distinct local servers, two users on one server, retained unsent listening, library choices, browser sign-in and relaunch, cancellation with the existing account retained, and rejection of an invalid callback before token exchange. Browser fixtures run wholly on the Studio; installed server 2.30.0 source supplied the session-cookie, PKCE and redirect contract. The live homelab currently enables local authentication, so live-provider acceptance remains pending.

## Browsing

The native catalog uses the server's paginated item API, expanded book details, current-user progress and personalized Continue Listening shelf. Resume cards can include titles outside the first catalog page; scrolling to the last catalog card requests the next page. Cover and list views share the same navigation and support missing artwork. iPad uses a library sidebar and a flexible catalog grid.

The UI journeys exercise the actual signed app against the synthetic server: book details and chapters, scrolling through 61 titles, and a resume card outside page one without an eager page-two request. The fixture's request observations verify pagination behavior. The original placeholder failed the browsing journey; the eager-fetch regression failed before personalized shelves and scrolling-driven pagination were implemented.

Run the same journeys on a dedicated iPad simulator with `ABS_QA_SIMULATOR='Audiobookshelf Native iPad QA' ./apple/scripts/verify-ui.sh`. Create that simulator using an available iPad device type and the same iOS runtime.

## Playback

The app and TV target share `Playback/ApplePlayback.swift`. One app-owned AVPlayer session survives catalog navigation and player dismissal. The mini-player and full-screen player provide play/pause, whole-book scrubbing, saved skip intervals, elapsed time and preparation/error status. Authenticated media URLs are validated against the connected server. File-relative positions are translated to complete-book positions, and natural track endings load the next file.

Pending seeks are serialized with the newest requested position retained. Play intent is separate from AVPlayer's observed playback state, so pausing during session or file preparation prevents autoplay. Failed media preparation stays visible; failed session close retains its progress rather than silently signing out.

Production UI journeys use real synthetic WAV media and server request/progress observations. They cover file transitions while navigating, missing media, a replacement seek during slow file preparation, and pausing during a delayed session request. The missing-play action, dropped-seek race, preparation-pause gap and missing-media error were observed failing before their implementations or fixes.

## Listening controls and discovery

The full-screen player uses server artwork, separate chapter and whole-book positions, chapter selection, the baseline 0.5–10× speed range, saved forward/backward intervals, and bookmarks stored by the server. Bookmark failures retain the draft and offer retry; selecting a bookmark keeps the current play/pause intent. Saved intervals also update the system skip controls. Speed and interval preferences persist on this device.

Duration sleep timers count time while audio plays and pause during buffering or paused playback. Timer ownership stays with the shared player after its screen is dismissed. End-of-chapter boundaries are installed on the current file, and seeking past a boundary stops audio and clears the timer. Users can add/subtract five minutes, reset the original duration, cancel timers, and enable the final-minute fade. When a faded timer expires, playback pauses, restores volume, and seeks back to the position where fading began. Later seek/play commands invalidate a pending timer rewind.

Resume rewind follows the baseline Apple thresholds: pauses shorter than 10 seconds do not rewind; longer pauses rewind 3/10/20/30 seconds at 10 seconds/1 minute/5 minutes/30 minutes. Initial session playback does not rewind. The rewind preference and system-position seeking preference persist on the device. System controls support play/pause/toggle, configured skips, optional seeking, and book artwork. Audio interruptions pause and recover only when the system permits resuming and no newer playback control supersedes that intent. App-suspension interruptions cannot resume automatically; removal of the current audio device pauses playback. Actual lock-screen, phone-call, headset/Bluetooth routes, background timer, and relaunch timer acceptance remain open under #9/#11. Auto-window and shake options are Android-only in the baseline UI.

Native search calls the existing server endpoint, with book/podcast/episode results and author, series, narrator and tag links. Result expansion requests a larger supported search limit. Catalog ordering uses the baseline server sort fields, and filters use server-provided metadata and its Base64 filter contract. Filtered catalog pages retain their filter and order and suppress unrelated Continue Listening entries. The explicit-content filter follows the account permission.

Podcast details list episodes with date/title/season/episode-number/filename ordering, saved ordering preferences, and completion/in-progress filters. Each episode has its own title, description, duration, listening progress and resume identity. Finish/unfinish actions flush pending listening and close the matching active episode before publishing the explicit progress edit; an older detail refresh cannot overwrite that edit.

Admin/root accounts can discover podcasts by name through the existing server search, preview an RSS feed, choose a configured server folder and create the podcast with the baseline auto-download option. Creation preserves selected discovery metadata and finishes its catalog refresh before dismissing. Feed selection sends the complete server RSS objects back to the existing download endpoint, including enclosure/GUID/chapter fields. Queue polling checks expanded episodes for actual readiness: the server omits its active download from the queue endpoint, so an empty queue alone is insufficient. Requested enclosure identifiers persist per canonical account and podcast as hashes; private feed URLs are not written to preferences. Network errors retain pending identifiers for explicit retry and foreground recovery. Download failures absent from the server queue still need realtime failure-event handling; the local Downloaded filter awaits the offline-content slice.

Signed simulator journeys verify chapter/file seeking, actual faster playback and restored speed, saved skip intervals, server bookmark create/edit/jump/delete through relaunch, actual timed audio stopping after leaving the player, a title beyond the first catalog page, and descending order plus genre filtering. Each newly introduced journey first failed through the production UI. These observations use the local 2.30.0 synthetic contract; physical and live-library acceptance remains outstanding.

## Durable listening

Listening positions and cumulative listening time are atomically persisted in the app's Application Support directory before publication. Each record has a stable session UUID and a canonical server/user identity; credentials stay in Keychain. Reopening the app recovers unsent records before requesting a new playback session. Acknowledgments retire only the revision actually sent, retaining listening recorded during a request. Unreadable data is preserved for recovery, and a disk-write failure pauses playback with an error.

The server's `/api/session/local-all` endpoint accepts absolute listening totals for the same UUID, allowing an ambiguous acknowledgment to be retried without adding the same listening twice. This behavior was checked against the installed server's `PlaybackSessionManager` implementation. Ordinary stream `/sync` requests add deltas and are unsuitable for this retry path. Stream sessions close with an empty body; they do not repeat journal progress. A server response accepting history while preserving newer remote progress is a successful acknowledgment.

Core tests reopen real files, isolate accounts, preserve newer revisions, recover terminated sessions and exercise failed writes. Native simulator journeys play actual WAV files, terminate the process while progress publication is unavailable, then restore it and observe server progress. iPhone and iPad restart-recovery journeys pass. These local fixtures do not establish physical-device acceptance or real-server multi-device acceptance.

## Audio downloads and offline listening

Download a book or episode from its details and open Downloads from the account menu. Downloads is also available while the server is loading or unavailable. The service owns a background URLSession and a durable account-scoped manifest, independently of the screen. It downloads original audio files with bearer headers, keeps completed parts when unfinished transfers are canceled or retried, and validates HTTP status, content type and byte length before publishing available content. Missing local files reopen as retryable failures; an unreadable manifest is preserved for recovery. Audio files and manifests are excluded from iCloud backup and protected until first device unlock. Cellular policy applies to requests; changing it invalidates unfinished task generations and replaces transfers with the new policy.

Offline playback uses owned file URLs in the shared player. It retains multi-file seeking, chapters, speed and skip preferences, and writes listening to the local journal before attempting publication. Resume positions remain cached after history is acknowledged. Reconnection records timestamped remote progress so a later offline start can adopt a newer position from another client without downloading the audio again. Saved media remains scoped to canonical server plus user ID.

MOBI/AZW3 and comic readers, expanded transfer interruption/storage/device acceptance, preference/data migration and final physical-device acceptance remain tracked separately. This preview is a delivery slice, not a replacement readiness claim. Synthetic fixture coverage does not establish live-server or physical-device readiness.


## PDF reading

Book details open the primary or supplementary PDF using PDFKit, with native zoom and links, page navigation, continuous display, and rotation relative to the document's original orientation. Downloaded PDFs open without a library request. Primary reading uses server ebook progress; supplementary documents retain separate local locations and never replace primary progress. Download snapshots retain the server page even when the first opening happens offline.

Reading locations and rotation are atomically persisted per server/user/item/document. Reading publication waits for an open listening session to close, flushes durable listening first, and reserves publication before another listening session begins. The installed server (2.30.0) exposes one modification timestamp shared by audio and ebook progress. Recognized echoes of our older publications advance the durable server baseline while retaining newer local pages, including a lost response followed by a rejected retry.

The ten-scenario iPhone PDF journey passed, covering invalid files, a 120-page document, authored rotation, offline relaunch, downloaded audio upgrades, newer remote progress, supplementary PDFs, active audio and display preferences, and delayed/lost responses. A separate double-failure regression first failed by losing page 3, then passed after the baseline fix. These fixtures do not establish physical-device, actual PDF annotation-link, or multi-device live-server acceptance. Run `bash apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/ReaderJourney` locally. No hosted build service is required.

## EPUB reading

Primary and supplementary EPUBs use bundled EPUB.js and JSZip inside a local WebKit renderer, with native contents, settings and swipe controls. No CDN or cloud renderer is required. Publisher styles and images remain available; book scripts and network navigation are blocked. Settings persist theme, font, size, spacing, weight, spread and keep-awake choices. Primary books save passage CFIs and percentage through the reading journal; supplementary books keep separate local positions. Downloaded books reopen offline. Derived location maps are cached by account and book contents and can be regenerated independently of saved passages.

Simulator journeys passed chapter navigation, publisher styles and images, swipe navigation, invalid-file recovery, a long document, downloaded offline relaunch, concurrent audio, preference persistence and correction of a restored passage's percentage. An unreadable reading journal remains visibly unavailable across relaunch and is preserved; the reader does not publish unsaved progress. The combined reader run passed 16 of 17 cases; the failed PDF retry assertion was corrected to observe requests from its own scenario, and all three retry scenarios then passed. The latest cache/storage checks passed separately. Hardware volume navigation is implemented with enabled, mirrored and off preferences, but actual device buttons still require acceptance; preference tests do not establish hardware behavior.

Selected iPad journeys also passed downloaded offline restoration and publisher styles/images with swipe navigation. A downloaded EPUB with a saved progress snapshot first failed to open when its reading journal was damaged; guarding snapshot adoption restored readable content while retaining the saving warning and original journal. The signed internal preview was built locally and installed on both physical devices; installation alone does not establish reading or hardware-control acceptance.
