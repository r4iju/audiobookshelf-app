# Leafwake release workspace

This directory holds the public release preparation. No binary is cleared for distribution yet. The native applications, their internal preview identifiers and installed data remain separate from the proposed public product.

## Current gates

| Channel | Status |
| --- | --- |
| Google Play | Barbellry's existing service-account token exchange and read access to `com.barbellry` pass. `com.forkzed.leafwake` returns package not found. The new app needs Play Console registration and initial setup; app-specific access must then be checked. |
| Public Android APK | A separate Cast-free candidate is implemented behind `-Pleafwake=true`. No binary has been published. Its selection and product acceptance remain open. Do not publish the existing Cast-enabled preview APK as Leafwake. See [the dependency audit](ANDROID-LICENSE-AUDIT.md). |
| Apple stores and public TestFlight | Existing App Store Connect API access works. The old `com.forkzed.audiobookshelf` app record is in `PREPARE_FOR_SUBMISSION`; it is not evidence of an approved public license grant. Resolve the GPL/current Apple terms gate before upload. |
| Public product acceptance | Use the recorded platform gates in [the release plan](../../docs/modernization/PUBLIC-RELEASE-PLAN.md). A source or store preparation change does not close hardware, migration, localization or stock-server compatibility acceptance. |

## Android publishing setup

Barbellry uses `apps/expo/eas.json` to submit to Play's `alpha` closed-testing track. Its private service-account JSON is at `apps/expo/credentials/android/barbellry-45151cd5babe.json`. Reuse the account only if it is authorized for Leafwake; do not copy the secret into this repository, release archive, logs or app assets. The native Leafwake app is a Gradle build and does not need Expo/EAS.

Check access using an absolute path to that private credential:

```sh
python3 releases/leafwake/check-play-access.py /private/path/service-account.json com.forkzed.leafwake
```

Create a separate local Android signing identity:

```sh
python3 releases/leafwake/init-signing.py
```

This creates a PKCS12 key and private configuration outside the checkout under `~/.local/share/leafwake/signing/`, with restrictive permissions. It never replaces an existing key. Back up the key/configuration securely. Decide the Play App Signing strategy before the first upload so Play and direct APK update paths have the intended signer; an APK signed by a different key cannot update an existing install in place.

Public build preparation must reject a missing owner signing configuration instead of falling back to the preview debug keystore. Permanent application IDs, OAuth callbacks, manifest branding, original icons, in-app privacy/license information, exact runtime license notices and source archives must match the final artifact. Validate all of these before distribution.

## Licensing and metadata

- [Android license audit](ANDROID-LICENSE-AUDIT.md): current linked libraries, Cast receiver and privacy gates.
- [Permission request draft](PERMISSION-REQUEST-DRAFT.md): local draft only; no outreach has been sent.
- [Privacy policy draft](PRIVACY.md): applies only to the proposed Cast-free public Android build and must be checked against its exact runtime graph.
- [Store listing draft](STORE-LISTING.md): independent affiliation and beta scope; final metadata still requires artifact verification.
- [GPLv3 license](LICENSE.txt): retain the upstream license and notices. Publish complete corresponding source/build materials matching every covered binary.

Do not substitute a different license for inherited code, reuse upstream's Cast receiver without permission, claim that source availability alone settles store-term compatibility, or submit declarations that do not match the shipped runtime.

## Reversible Android candidate

The default Gradle build retains the internal preview identity and Chromecast. `-Pleafwake=true` selects Leafwake's independent application ID, callback scheme, original icon, privacy/license screens, and Cast-free source/dependency graph. Legal screens are accessible before sign-in and in Settings. Cast instrumentation tests are compiled only for the preview.

```sh
cd android-native
./gradlew --offline -Pleafwake=true :core:jar :app:writeRuntimeInventory
cd ..
python3 releases/leafwake/generate-notices.py
```

The generator rejects unknown license name/URL metadata and all GMS or media3-cast artifacts. It preserves embedded notices (including OkHttp's MPL public suffix notice and checker-qual's MIT grant) and includes full GPL, Apache, MIT and MPL license texts. This is a metadata check plus notice collection, not a complete legal opinion. Verify the packaged artifact, not just the source inventory.

Public release packaging requires the owner signing environment variables documented in `android-native/app/build.gradle.kts`, plus `-PleafwakeSourceUrl=https://github.com/r4iju/audiobookshelf-app/tree/<exact-40-character-commit>`. This guard applies when release packaging is reached through aggregate Gradle tasks too. Leafwake never falls back to the debug signer. Supply passwords through environment variables from the private signing configuration, without printing them or adding them to command arguments.

Before distributing, archive the exact committed source and build materials with `git archive`, retain the dependency inventory and source access for included dependencies, check the signer and application ID, and complete the release plan's stock-server and device gates. An owner-signed build is still a candidate, not acceptance or publication clearance.

Verification during preparation: public and preview debug compilation; preview core/unit tests; both instrumentation source sets compile; public release without an owner key fails as required. The Device panel could not boot either available emulator, so there is no new device/UI acceptance evidence from this change.
