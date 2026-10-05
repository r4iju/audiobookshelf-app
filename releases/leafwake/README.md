# Audiobook Loft release workspace

## Audiobook Loft rc.5, completed October 5, 2026

The selected public name is live at `https://audiobookshelf.nginx.lan`. [The rc.5 prerelease](https://github.com/r4iju/audiobookshelf-app/releases/tag/audiobook-loft-v1.0.0-rc.5) publishes the one-image Linux amd64 archive, exact corresponding source `995abf39ae721dee184f9397c86b497438dcc714`, build materials and checksums. Image ID: `sha256:1c88111930dcf85170a7a63e73b14a13a964832e34e02dafc763c5cab978bfa7`; archive SHA256: `3df518b6571f9860863a49205255259a4d8ba63034687ac73b7a3ecb932f0063`. Docker archive config digest is distinct: `sha256:f7f82a623fea53ccfbaef25907498d536c4c47adb6b1d1471a4415fab5a9b9fb`.

A fresh live backup preceded the tag-only rollout. Imported config/source/product identity was verified. After an actual application restart: one ready production pod, zero crash restarts, zero retired-app pods; original owner identity/password, 127 library items and 34 history records retained; authenticated audio Range 206 (32 bytes), anonymous media 401 and HTTPS websocket authentication passed. No automated progress writes touched owner data. DNS, TLS, ingress, WAF, media/data mounts and persisted crypto formats were preserved.

Verification: 119 units, types/lint, 29 locales, 16 browser browse/settings journeys and a title replay on the final source-labelled image. Cast-free Android beta 2 passed all four unchanged real-server emulator journeys against rc.5. iOS/tvOS simulator builds passed; iOS used deployment target 15 only as a build override for the installed SDK. The earlier full Apple media journeys remain rc.4 evidence, not newly rerun rc.5 claims.

**Android beta 2:** exact AAB SHA256 `74aadcc6b8fdc3aa8c1f660425acf83ac8a8eab5a48219a3c3794294b97b3cff`, version code 2, source `995abf39ae721dee184f9397c86b497438dcc714`. Owner upload signing, target SDK 36, public display name, policy/license asset bytes, all 136 dependency notices and absence of Cast were verified. Uploaded/validated/committed and read back: internal version 2 completed; closed alpha version 2 draft. Testers unchanged; no production rollout. [Existing internal invitation](https://play.google.com/apps/internaltest/4701528550804807345). Direct APK remains unpublished because its signer differs from Play's app signer.

**Apple and public site:** Apple accepted Audiobook Loft on record 6819142007. iOS/tvOS descriptions and subtitle retain explicit app-fork origins, rewritten browser/backend, GPL/upstream notices and independence. Both versions remain Prepare for Submission, no public upload. Play descriptions and renamed feature graphic are saved; the public support/privacy site returns the renamed title and origin disclosure. Apple rights/privacy/signing/review-access and Play closed-testing/review gates remain open. Earlier source-matched Leafwake artifacts remain immutable.

## Historical preparation gates (superseded by RELEASE-STATUS.md)

| Channel | Status |
| --- | --- |
| Google Play | Leafwake is registered as a free app in the existing Barbellry developer account, with package `com.forkzed.leafwake` and default language `en-GB`. Automatic installer protection was disabled. App-specific service-account read access passes; no binary has been uploaded. This personal account requires 12 opted-in closed testers for 14 continuous days before applying for production access. |
| Public Android APK | A separate Cast-free candidate is implemented behind `-Pleafwake=true`. No binary has been published. The owner selected it for the initial beta on October 4, 2026; product acceptance remains open. Do not publish the existing Cast-enabled preview APK as Leafwake. See [the dependency audit](ANDROID-LICENSE-AUDIT.md). |
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
- [Permission request](PERMISSION-REQUEST-DRAFT.md): posted to upstream discussion #2051 with owner authorization; approval is pending.
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

Verification during preparation: public and preview debug compilation; preview core/unit tests; both instrumentation source sets compile; public release without an owner key fails as required. The owner-signed candidate installed on an API 36 emulator and a physical Android 16 phone. Manual emulator checks covered pre-login privacy access, sign-in, library browsing and streaming against an isolated stock 2.30.0 server. The physical phone was locked, so installation is not physical playback acceptance. Three stock-server journeys pass; offline-finish remains failing. See [the QA status](QA-STATUS.md) for scope and the remaining gates.
