# Leafwake Android distribution audit

2026-10-04. Bounded inspection of `android-native` Gradle files, Kotlin/manifest and locally cached published POMs/AARs, plus current primary distribution terms. No repository changes, credential reads, external messages or final APK inspection. Findings concern the current Cast-enabled native code; re-audit the exact final release graph and packaged files after changes.

## Decision

**Do not publish the present Cast-enabled APK as license-cleared.** Direct APK hosting avoids store contracts, but does not avoid the linked proprietary SDK problem, Cast registration obligations or third-party notices. The most concrete route within the user's request to avoid violations is a **Cast-free, independently branded GPLv3 Android beta**, with owner signing, exact corresponding source and complete third-party notices. Keep a Cast-enabled development build private until permissions/terms are resolved. Do not relabel upstream code under a new permissive license or invent a linking exception.

Google Play adds a separate distribution-contract review, account/testing and policy requirements. Apple distribution remains unresolved for inherited GPLv3 code, including TestFlight; source publication alone does not resolve Apple's terms.

## Native runtime evidence

| Dependency family | Cached evidence | Consequence |
|---|---|---|
| AndroidX Core/Browser, Compose, lifecycle, Work, Media3; Material; Kotlin/coroutines/serialization; Coil; OkHttp/Okio | Inspected POM samples identify Apache-2.0. Direct pinned versions are in `android-native/app/build.gradle.kts` and `core/build.gradle.kts`. | Compatible license family for combination under GPLv3, while original notices/licenses remain required. This is a sample audit, not the final resolved transitive inventory. |
| `io.socket:socket.io-client:2.1.2`, `engine.io-client:2.1.0` | Cached POMs identify MIT. | Retain applicable copyright/permission notices. |
| `androidx.media3:media3-cast:1.9.0` | Its Apache-2.0 POM directly pulls `com.google.android.gms:play-services-cast-framework:22.1.0`. | Apache licensing of the wrapper does not cover Google's proprietary runtime. |
| Google Cast framework/cast 22.1.0, GMS base/basement 18.5.0, flags 18.1.0, tasks 18.2.0 | Cached Google POMs point to Android SDK terms. Cast framework pulls these GMS components and Google DataTransport dependencies. `Casting.kt` directly imports GMS classes. | No known additional GPL linking permission in this checkout. This is a concrete unresolved compatibility gate for **every binary channel**, not just a store. |

Cache source: `~/.gradle/caches/modules-2/files-2.1/<group>/<artifact>/<version>/*/*.pom`. Cache availability does not prove a module is shipped; final `releaseRuntimeClasspath` and APK inspection must establish the exact inventory.

[Apache's compatibility guidance](https://apache.org/licenses/GPL-compatibility.html) confirms Apache-2.0 compatibility with GPLv3. [Apache license section 4](https://www.apache.org/licenses/LICENSE-2.0) requires a license copy, applicable notices and NOTICE preservation. AAR/JAR metadata may be insufficient for an end-user notice bundle.

## GPL and Google SDK gate

The repository `LICENSE` is unmodified GPLv3 text; no project-specific Cast/GMS exception was identified. GPLv3 sections 5, 6, 7 and 10 require licensing the covered combined work and corresponding source, preserve permissions and forbid additional restrictions. An independently shipped proprietary SDK included in app code should not be assumed to satisfy the system-library exception. Whether a particular architecture qualifies requires actual analysis, not the fact that Google services are common on Android. [GNU's GPL-incompatible-library FAQ](https://www.gnu.org/licenses/gpl-faq.en.html#GPLIncompatibleLibs) and [SPDX's GPLv3 linking exception](https://spdx.org/licenses/GPL-3.0-linking-exception.html) describe additional permission, which the fork cannot grant on behalf of upstream copyright holders.

Google's [SDK terms](https://developer.android.com/studio/terms), identified by cached GMS POMs, grant a limited nonsublicensable SDK license and restrict modification/redistribution except as otherwise licensed. Open-source SDK components are expressly governed by their separate licenses. This confirms the terms are not a general GPL-compatible grant for all Google SDK binaries; the precise SDK distribution permissions must be established before retaining them.

Preferred action: remove `media3-cast` and GMS code/manifest references **from the published variant's compile/runtime graph**, rather than hiding its UI. A disabled feature still bundles the same libraries. Reinspect for remaining `com.google.android.gms` modules before claiming this gate removed.

## Cast-specific obligations, if retained later

`Casting.kt` currently hard-codes receiver ID `FD1F76C5`, with a comment that it is registered by the existing Audiobookshelf app. [Google Cast additional terms](https://developers.google.com/cast/docs/terms) section 3.3 requires application registration. Obtain explicit applicable rights/registration for the independent product or register its own receiver; possession of an upstream receiver ID is not proof. Those terms also require appropriate Cast UI, user-initiated casting, playback APIs and no personally identifiable receiver console logs.

Both cached Cast AARs contain `third_party_licenses.json` and `third_party_licenses.txt`. [Google's notices guidance](https://developers.google.com/android/guides/opensource) makes developers responsible for displaying applicable OSS notices. No Android notice asset or screen was found in the inspected native source, so root must add/verify one. Do not solve this by adding another proprietary GMS notices runtime to a Cast-free variant; a static bundled notice screen can serve that purpose.

Google's [Cast SDK data disclosure](https://developers.google.com/cast/docs/android_sender/data_disclosure) says SDK interactions, discovery/session events, mobile-device and app information may be logged to Google; data is anonymized/encrypted and cannot be opted out of or deleted by developer/users. This prevents an unqualified “no analytics/no collection” assertion if Cast ships. Its guidance covers latest SDKs, so confirm behavior for the selected SDK. This obligation affects APK privacy statements as well as Play Data safety.

## Direct APK release requirements

Before a public beta artifact is concrete:

1. Cast-free graph or documented applicable permission resolving the proprietary linkage and SDK distribution issues.
2. Independent name, icon, package ID and support/privacy owner; no implied upstream affiliation. Upstream [client branding rules](https://audiobookshelf.org/docs/faq/app/) allow independent clients, not misleading use of the official identity.
3. Owner-provided signing, never automatic debug-key release fallback. Current Gradle release configuration defaults to debug signing if the owner keystore variable is absent; root is changing this.
4. GPLv3 license, copyright/modification notices and source matching the exact released binary: native app/core, build scripts, relevant resources and applicable dependency source/build access. Put clear source directions alongside the binary under GPLv3 section 6(d). Do not expose private signing credentials in source; evaluate installation-information duties for the actual distribution situation.
5. Complete dependency license/NOTICE bundle retained in APK and accompanying release. Current Gradle excludes `META-INF/{AL2.0,LGPL2.1}`; exclusions need a deliberate substitute, not omission. OkHttp's cached JAR includes `okhttp3/internal/publicsuffix/NOTICE`, which also needs preservation where applicable.
6. Final resolved runtime inventory and packaged APK verify absence of proprietary dependencies and inclusion of notices. Test/debug-only libraries do not belong in the shipping inventory.

## Additional Google Play gate

The current [Developer Distribution Agreement](https://play.google/developer-distribution-agreement.html) is effective September 15, 2025. Sections 5.1/5.3 authorize Google distribution/security-review uses and allow an app EULA, but say the agreement prevails on conflict. Sections 11.1/11.2 require rights to distribute third-party material. GPLv3 does not permit sublicensing other contributors' rights beyond its grant. **This bounded audit does not establish a conflict-free reading or blanket prohibition.** Review the actual account agreements and applicable GPL grants before submission; a source link is not that review.

[Play consumer terms](https://play.google.com/about/play-terms/index.html) section 4 also contains restrictions on content modification and redistribution, with exceptions for express authorization, and permits app EULAs. Ensure the app's GPL permission is expressly conveyed, assess how the exception applies, and do not add DRM/license restrictions that reduce GPL rights.

Operationally: API36 mobile target, owner-signed AAB, privacy policy/Data safety, accessible demo credentials, content-rating/foreground-service declarations, verified publishing account and qualifying closed-test requirements still apply. Existing target36 is suitable, but is not proof of store eligibility or licensing clearance.

## Apple route

No extra upstream/contributor permission was found authorizing a different distribution license. The current [Apple Developer Program agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) and [App Store usage terms](https://www.apple.com/legal/internet-services/itunes/) need reconciliation with inherited GPLv3. The [FSF's App Store enforcement record](https://www.fsf.org/appeal/2010/licensing) demonstrates that this is a concrete concern, although historical enforcement does not decide this app's current legal position. Do not publish an inherited GPLv3 Apple binary or claim cleared TestFlight distribution merely because GitHub source is public or upstream already uses TestFlight. Viable later routes are documented applicable rights/permissions from all relevant holders or an independently implemented client with a compatible licensing and dependency position.
