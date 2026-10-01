# Native Apple preview

SwiftUI iPhone/iPad client, connecting directly to the existing server through the shared production API core. The preview identity is `com.forkzed.audiobookshelf.native.preview`, team `C7X9BCC7LP`. Its explicitly scoped Keychain group keeps credentials separate from the working legacy app. Do not change it to the legacy identity until the migration/backup acceptance tickets are complete.

## Local builds

```sh
xcodegen generate --spec apple/project.yml
./apple/scripts/verify-ui.sh
./apple/scripts/deploy.sh --build-only
./apple/scripts/deploy.sh <paired-iPhone-or-iPad-UDID>
```

Create the dedicated simulator with `xcrun simctl create 'Audiobookshelf Native QA' com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0` if absent. The UI journey uses only the synthetic loopback server (`qa` / `qa`) and proves sign-in, library selection, Keychain restoration after relaunch, invalid-address recovery, qualified `.lan` HTTP, and rejection of an untrusted HTTPS certificate. `verify-ui.sh` starts/stops its own synthetic fixtures and creates a temporary two-day test certificate; it requires the Studio's existing `dev.nginx.lan → 127.0.0.1` alias. It does not install a trust root. Simulator builds must be ad hoc signed with the app's entitlements: disabling signing makes genuine Keychain operations fail with `-34018`. The qualified-host regression was first observed failing with an ATS cleartext-denial message; removing the conflicting `NSAllowsLocalNetworking` key made it pass while normal HTTPS trust remained enforced.

No replacement in-memory credential store is used by the app or UI journey.

The provisioning helper uses the existing developer certificate and App Store Connect signing key to register the internal preview and devices. Signing, compilation, packaging and installation execute on the Studio; there is no hosted build or public release. The resulting internal IPA is `apple/build-release/AudiobookshelfNative.ipa`.

Source deployment minimum remains iOS 14. Xcode 27 needs a build-only iOS 15 override; iOS 14 runtime compatibility remains unverified until an appropriate SDK/runtime is available. The override does not authorize changing the final supported audience. TLS uses platform certificate validation; allowing HTTP servers does not accept untrusted HTTPS certificates. Certificate failures explain installation and full-trust recovery.

This connection preview is a delivery slice, not a replacement readiness claim. Browsing, playback, offline storage, readers, preference/data migration and final physical-device acceptance remain tracked separately.
