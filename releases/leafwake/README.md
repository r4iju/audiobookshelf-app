# Audiobook Loft release workspace

[RELEASE-STATUS.md](RELEASE-STATUS.md) is the authoritative release and verification record. The current live browser/backend is Audiobook Loft rc.6, served by one Next.js/TypeScript image. [Its release](https://github.com/r4iju/audiobookshelf-app/releases/tag/audiobook-loft-v1.0.0-rc.6) contains the exact image, corresponding source, dependency materials and checksums. Earlier source-matched releases remain immutable historical artifacts.

| Channel | Current state |
| --- | --- |
| Browser/backend | Rc.6 is deployed and verified on the owner's server. The original Audiobookshelf backend and browser deployments are retired. |
| Google Play | Audiobook Loft beta 2 is uploaded and completed on the internal track; closed alpha version 2 is a draft. Package `com.forkzed.leafwake`, free download, locale `en-GB`. Production still needs the documented closed-testing and review gates. |
| Direct Android APK | Unpublished. The local signer differs from Google's Play app signer, so direct APKs do not update Play installs. |
| Apple stores/TestFlight | Separate Audiobook Loft record 6819142007, bundle `com.forkzed.leafwake`; iOS/tvOS remain Prepare for Submission with no public upload. Rights, privacy, signing and review-access gates remain open. |

Initial public Android builds are Cast-free. The default internal preview retains Cast; private builds and distributed releases have different licensing considerations. The [upstream permission request](https://github.com/advplyr/audiobookshelf-app/discussions/2051) is pending. Independent branding and the backend rewrite do not grant exceptions for inherited native code.

## Android publishing setup

Barbellry uses `apps/expo/eas.json` to submit to Play's `alpha` closed-testing track. Its private service-account JSON is at `apps/expo/credentials/android/barbellry-45151cd5babe.json`. Reuse the account only if it is authorized for Audiobook Loft; do not copy the secret into this repository, release archive, logs or app assets. The native Audiobook Loft app is a Gradle build and does not need Expo/EAS.

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
- [Permission request](PERMISSION-REQUEST-DRAFT.md): posted to upstream discussion #2051 with owner authorization; approval is pending.
- [Privacy policy draft](PRIVACY.md): applies only to the proposed Cast-free public Android build and must be checked against its exact runtime graph.
- [Store listing draft](STORE-LISTING.md): independent affiliation and beta scope; final metadata still requires artifact verification.
- [GPLv3 license](LICENSE.txt): retain the upstream license and notices. Publish complete corresponding source/build materials matching every covered binary.

Do not substitute a different license for inherited code, reuse upstream's Cast receiver without permission, claim that source availability alone settles store-term compatibility, or submit declarations that do not match the shipped runtime.

## Android build procedure and earlier candidate evidence

The default Gradle build retains the internal preview identity and Chromecast. `-Pleafwake=true` selects Audiobook Loft's independent application ID, callback scheme, original icon, privacy/license screens, and Cast-free source/dependency graph. Legal screens are accessible before sign-in and in Settings. Cast instrumentation tests are compiled only for the preview.

```sh
cd android-native
./gradlew --offline -Pleafwake=true :core:jar :app:writeRuntimeInventory
cd ..
python3 releases/leafwake/generate-notices.py
```

The generator rejects unknown license name/URL metadata and all GMS or media3-cast artifacts. It preserves embedded notices (including OkHttp's MPL public suffix notice and checker-qual's MIT grant) and includes full GPL, Apache, MIT and MPL license texts. This is a metadata check plus notice collection, not a complete legal opinion. Verify the packaged artifact, not just the source inventory.

Public release packaging requires the owner signing environment variables documented in `android-native/app/build.gradle.kts`, plus `-PleafwakeSourceUrl=https://github.com/r4iju/audiobookshelf-app/tree/<exact-40-character-commit>`. This guard applies when release packaging is reached through aggregate Gradle tasks too. The public build never falls back to the debug signer. Supply passwords through environment variables from the private signing configuration, without printing them or adding them to command arguments.

Before distributing, archive the exact committed source and build materials with `git archive`, retain the dependency inventory and source access for included dependencies, check the signer and application ID, and complete the current replacement-image and device gates in [RELEASE-STATUS.md](RELEASE-STATUS.md). An owner-signed build is still a candidate, not acceptance or publication clearance.

## Historical candidate preparation, October 4, 2026

The following evidence predates the full-stack cutover, public rename and Play beta 2. It is not the current release status.

Verification during preparation: public and preview debug compilation; preview core/unit tests; both instrumentation source sets compile; public release without an owner key fails as required. The owner-signed candidate installed on an API 36 emulator and a physical Android 16 phone. Manual emulator checks covered pre-login privacy access, sign-in, library browsing and streaming against an isolated stock 2.30.0 server. The physical phone was locked, so installation is not physical playback acceptance. Three stock-server journeys pass; offline-finish remains failing. See [the QA status](QA-STATUS.md) for scope and the remaining gates.
