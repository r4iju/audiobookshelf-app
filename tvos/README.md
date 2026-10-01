# Audiobookshelf for Apple TV

Native SwiftUI streaming client for tvOS 17 or later. The iOS/Android app and its existing local changes are separate from this target.

## Install tomorrow

1. Keep the Mac and Apple TV on the same network.
2. On the TV, open **Settings → Remotes and Devices → Remote App and Devices**.
3. In Xcode 27, open **Xcode → Open Developer Tool → Device Hub**, select the discovered TV, and pair it using the code shown on the TV. If prompted, enable Developer Mode on the TV.
4. From the repository root, run:

   ```sh
   ./tvos/scripts/deploy.sh
   ```

The command identifies the paired physical Apple TV, registers its UDID with your existing developer account, downloads a tvOS development profile using the existing App Store Connect API key, signs the release build, verifies the signature, installs it, and launches it. It does not need an Apple ID added to Xcode or a TestFlight upload. If more than one Apple TV is paired, pass the TV name or UDID as the first argument.

Sign in on the TV with your Audiobookshelf server address, username, and password. An iPhone's Apple TV Remote keyboard makes entry easier. HTTPS, local HTTP addresses, and reverse-proxy subpaths are supported. Passwords are not persisted; access and refresh tokens are kept in Keychain.

Apple's [pairing instructions](https://help.apple.com/xcode/mac/current/en.lproj/devbc48d1bad.html) describe the required TV-side step. The bundled project can also be opened directly as `tvos/AudiobookshelfTV.xcodeproj`.

## Included

- **Remote-first navigation.** A top tab bar holds Home, one tab per server library, Search, Now Playing (while a session exists) and Settings. Every screen is operated with the Siri Remote: focus is always visible, rows and controls are focus sections so directional movement is predictable, and Back returns to the tile that opened a screen.
- **Home.** The server's personalized shelves, such as Continue Listening and Recently Added, with listening progress on each cover.
- **Libraries.** Server-side sorting (title, author, recently added) and filtering (progress, genre, narrator, author) with automatic pagination as focus approaches the end of the loaded titles. Loading, empty and failure states each offer a recovery action.
- **Search.** Server search across every library for titles, authors, narrators and podcast episodes, including titles that have not been loaded yet.
- **Details.** Cover, title, author, narrators, duration, chapter count, genres, description and listening progress, with Play, Resume or Play again, and Mark as finished.
- **Podcasts.** Episodes sorted newest or oldest first with publication date, duration and per-episode state; episode details with Play/Resume and Mark as finished. Episode progress and completion are kept separate from audiobook progress.
- **Now Playing.** Chapter title and position, chapter and total progress, previous/next chapter, a chapter list, skip back/forward, play/pause (also from the remote's Play/Pause button on any screen), speeds from 0.75× to 3×, a sleep timer and an explicit Stop. Leaving the tab or browsing elsewhere never ends playback. Multi-file books play as one timeline.
- **System controls.** Now Playing metadata, artwork and remote transport commands come from the shared Apple playback engine (`apple/Playback`).
- **Durable listening.** Listening is written to a local journal before it is sent. It is reported every 15 seconds, on pause, on stop, when the app opens and when it returns from the background; only reports the server acknowledges are retired, so unsent listening survives termination and is sent once.
- **Recovery.** Connection errors explain what to change (untrusted certificate, unknown host, unreachable server, missing reverse-proxy path). Expired logins prompt for the password without discarding the session or saved listening.
- Layered Apple TV home-screen icon and top-shelf artwork.

### Sign-in and connection support

The TV supports Audiobookshelf **username and password** sign-in, for both legacy `user.token` and modern access/refresh-token servers. OpenID single sign-on is not offered: it requires a browser, which tvOS does not provide, and the spec does not require an unsupported TV authentication flow. Accounts that only use single sign-on need a local account on the server.

Connections go directly to the server. HTTPS uses system trust only, so a server signed by an installed and trusted homelab certificate authority profile works without pinning or exceptions. Local HTTP addresses and reverse-proxy subpaths are also supported. Passwords are never stored; tokens are kept in Keychain.

### TV playback policy

- Switching tabs, opening details or returning to Home keeps the current session.
- Pressing the TV/Home button sends the app to the background, which pauses and saves. Control Center or the screen saver (the inactive phase) keeps listening.
- Stop closes the server session after sending outstanding listening. Signing out stops playback first and is cancelled if listening cannot be saved.

### Not included

Downloads, offline playback, ebook/PDF reading, collections/playlists management, podcast administration and bookmarks are mobile capabilities that are deliberately not on the TV.

## Build and verify

The project has no external Swift dependencies. Xcode 27 and its tvOS SDK are installed on this Mac; the app deployment target is tvOS 17, compatible with the discovered Living Room TV running tvOS 18.6.

```sh
swift test --package-path tvos/Core

# Remote-driven UI journeys on the dedicated tvOS QA simulator against owned synthetic fixtures
# (HTTP on 20765, HTTPS on 20767 signed by a throwaway CA trusted only in that simulator):
./tvos/scripts/verify-ui.sh
./tvos/scripts/verify-ui.sh -only-testing:TVJourneyTests/PodcastJourney   # a single journey

# Signed release for the Apple TVs already registered with this account:
./tvos/scripts/deploy.sh --build-only

# Simulator build (retain default ad hoc signing so Keychain works):
xcodebuild -project tvos/AudiobookshelfTV.xcodeproj \
  -scheme AudiobookshelfTV -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath tvos/build build
```

`verify-ui.sh` uses the simulator `00DD108F-2435-4FEC-9C37-3E62861A0EF6` (override with `ABS_TV_QA_SIMULATOR`) and refuses to start if its fixture ports are busy. Debug builds accept a `--reset-tv-state` launch argument that clears the saved login and listening journal so each journey starts signed out; Release builds, including every signed device build, do not contain it.

Only if editing the project specification or artwork:

```sh
swift tvos/scripts/generate-assets.swift
xcodegen generate --spec tvos/project.yml
```

Provisioning uses `python3` with `cryptography`, both already available here. The API key remains at `~/.appstoreconnect/private_keys/AuthKey_HK78P3V55N.p8`; no private keys, credentials, or profiles are stored in this directory. `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` can override the defaults. The installed Apple Development certificate belongs to team `C7X9BCC7LP` and expires November 30, 2026; renew it before that date to sign subsequent builds.

## Prepared artifacts and verification

The signed hardware app is at `tvos/build/Build/Products/Release-appletvos/AudiobookshelfTV.app`, and the packaged IPA is at `tvos/build/AudiobookshelfTV.ipa`.

On October 1, 2026, the second-generation **Living Room TV** running tvOS 18.6 was paired, registered, and provisioned. `deploy.sh` successfully built, installed, and launched the app on that physical TV. Run the script again for subsequent updates; it builds with the selected device's profile. The original packaged IPA predates this pairing, so use the script rather than assuming that IPA is provisioned for the current TV.

See [QA.md](QA.md) for automated evidence and the physical-TV acceptance checklist, and [HANDOFF.md](HANDOFF.md) for integration notes for shared code owners.
