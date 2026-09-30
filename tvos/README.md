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

- Library selection, cover grid, paginated browsing, and filtering of loaded titles/authors.
- Audiobook streaming and resume from server progress, including multi-file books.
- Podcast episode selection and streaming.
- Play/pause, 30-second skips across files, chapter selection, and speeds from 0.75× to 2×.
- Now Playing metadata and remote transport commands.
- Progress sync every 15 seconds, on pause, and when ending a session; failed sync remains pending while the app is running and can be retried.
- Modern access/refresh tokens, legacy server tokens, and reauthentication without discarding the active playback session.
- Layered Apple TV home-screen icon and top-shelf artwork.

This target streams audio. Downloads, ebook reading, and OpenID/browser sign-in are not included. Server-side resume requires a successful progress sync; unsent progress does not survive app termination. Returning to the library keeps audio playing; leaving the app pauses and attempts to save progress.

## Build and verify

The project has no external Swift dependencies. Xcode 27 and its tvOS SDK are installed on this Mac; the app deployment target is tvOS 17, compatible with the discovered Living Room TV running tvOS 18.6.

```sh
swift test --package-path tvos/Core

# Signed release for the Apple TVs already registered with this account:
./tvos/scripts/deploy.sh --build-only

# Simulator build (retain default ad hoc signing so Keychain works):
xcodebuild -project tvos/AudiobookshelfTV.xcodeproj \
  -scheme AudiobookshelfTV -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath tvos/build build
```

Only if editing the project specification or artwork:

```sh
swift tvos/scripts/generate-assets.swift
xcodegen generate --spec tvos/project.yml
```

Provisioning uses `python3` with `cryptography`, both already available here. The API key remains at `~/.appstoreconnect/private_keys/AuthKey_HK78P3V55N.p8`; no private keys, credentials, or profiles are stored in this directory. `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` can override the defaults. The installed Apple Development certificate belongs to team `C7X9BCC7LP` and expires November 30, 2026; renew it before that date to sign subsequent builds.

## Prepared artifacts and verification

The signed hardware app is at `tvos/build/Build/Products/Release-appletvos/AudiobookshelfTV.app`, and the packaged IPA is at `tvos/build/AudiobookshelfTV.ipa`.

The prepared profile includes the **older “Living Room” Apple TV registered in the developer account**. The currently discovered Living Room TV is a second-generation Apple TV 4K and has not been paired with this Mac. **Use `deploy.sh` after pairing so its actual UDID is included before installation.** The script rebuilds with that device's profile; do not assume the prebuilt IPA is already provisioned for the current TV.

See [QA.md](QA.md) for checks and simulator evidence. Physical-TV installation and your actual server's credentials/library must be verified after tomorrow's pairing; they have not been represented as already tested.
