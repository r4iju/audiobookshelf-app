# Leafwake public release plan

> Superseded scope: the owner subsequently authorized a full replacement of the backend and browser. The active release contract is [the full-stack specification](../fullstack/SPEC.md) and [the replacement compatibility matrix](../fullstack/COMPATIBILITY.md). This document retains the earlier client-only research and historical gates; references to a required original backend or its patched acceptance are not the replacement release claim.

Prepared October 4, 2026. The owner authorized an independent app under their developer accounts and asked for a name and licensing consideration. **Leafwake** is the working name. Public release is a new milestone beyond the original internal distribution scope; this plan does not declare the existing acceptance gates passed.

## Product and channels

Working tagline: **Your library, wherever you listen.**

Positioning: an independently maintained native client for your Audiobookshelf server, focused on dependable listening across Apple and Android devices. An existing server is required; the app supplies no books. Offline audio and companion PDF reading are candidate listing features, subject to final release acceptance. Do not advertise deferred mobile EPUB, MOBI, AZW3 or comic acceptance, unverified device integrations, or compatibility with arbitrary server versions.

Launch order: Android Play testing and owner-signed APK releases, then mobile production; iPhone/iPad App Store distribution after the licensing gate is resolved; Apple TV after remote and physical playback acceptance. Keep the Next.js client self-hosted and publish reproducible deployment instructions. Android TV is a separate feasibility decision, not an assumed mobile-build capability.

The [market research](PUBLIC-RELEASE-RESEARCH.md) supports a limited launch experiment, not a revenue forecast. Competing clients already provide modern interfaces. Recruit actual users and evaluate repeat listening, successful offline use, sync reliability and specific reasons to switch. Do not add new analytics without a separate privacy decision; beta feedback can be collected directly.

## Brand and listing draft

- App name: Leafwake.
- Short description: A native player for your Audiobookshelf library.
- Opening copy: Connect to your own Audiobookshelf server and bring your library along. Leafwake is an independent client for listening to your audiobooks and podcasts.
- Affiliation disclosure: Leafwake is independently maintained and is not affiliated with or endorsed by the Audiobookshelf project.
- Name status: quoted web searches for Leafwake and Leafwake app audiobook found no obvious audiobook-app collision. This is preliminary screening, not trademark clearance, domain availability or store-name registration.
- Create an original icon and owned promotional assets. Follow the [upstream client branding rules](https://audiobookshelf.org/docs/faq/app/).
- Proposed identifiers, not registered or applied: `com.forkzed.leafwake` on mobile and `com.forkzed.leafwake.tv` for tvOS. Check account ownership and availability before choosing permanent IDs. Preserve internal preview identities and migration access; changing an identifier does not transfer its sandbox or Keychain data.

## Licensing gate before distribution

The repository [LICENSE](../../LICENSE) contains GPL version 3. Treat covered derivative code as GPLv3 unless an actual additional grant is established. Native target authorship or a new interface is not proof that the shipped executable is independent of upstream code.

1. Inventory the files and dependencies shipped by each target, including shared TVCore, migration/export code, bundled reader JavaScript, artwork and sounds. Trace copied or adapted code to its copyright holders. Distinguish original owner-controlled work, third-party permissive components and inherited copyleft work.
2. Retain copyright/license notices, document modifications and provide exact corresponding source with the build scripts and dependency information required to rebuild each distributed version. Tag the source used for every artifact and keep the source download available alongside binary access. Assess any applicable GPL installation-information requirements; signing alone does not settle them.
3. Check bundled dependency notices against the actual versions. Reader notices already exist in `apple/App/ReaderAssets`; their presence does not establish a complete audit of every target.
4. **Apple distribution remains unresolved.** Apple's [standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) has restrictions and an open-source carve-out; its [custom EULA minimum terms](https://www.apple.com/legal/internet-services/itunes/dev/minterms/) and [developer agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) also apply. The FSF's [historical GPL enforcement analysis](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement) concerns older terms and GPLv2, so it is evidence of a real compatibility issue, not a conclusive opinion on this GPLv3 build today. Obtain a specific licensing assessment of current terms and the actual shipped code before public Apple distribution, including external beta distribution.
5. If additional Apple distribution permission is needed, obtain it from every relevant rights holder, or remove/replace the affected code through an independently implemented path with established rights. Permission from one upstream maintainer does not cover other contributors' rights. Do not change the repository license unilaterally. A custom EULA or another app's store approval is not proof of clearance.

Upstream allowing independent proprietary API clients does not waive the license on its implementation. Android and self-hosted distribution still require their own dependency and GPL compliance review. GPL permits commercial distribution subject to its conditions; no pricing decision is made here.

## Current checkout and release gaps

Source inspected: `9c8cfca1`, integration branch `fork/native-tv`. It was fast-forwarded from `ed3463d5`, with no divergent local commits. Existing local legacy iOS packaging changes were restored; the merged Podfile checksum resolved the lockfile conflict. Backup stash: `0420a090beede3fe47e586d04c8de6376a8e6903`. Existing untracked artifacts and signing material remain local. This is not a clean, tested release candidate.

| Area | Evidence and required next work |
| --- | --- |
| iPhone/iPad | Native target is in `apple/`, not the old `ios/` Capacitor app. Existing deployment script creates an internal preview IPA. Prepare store archive/export settings after the rights and identity decisions. |
| Android | `android-native/app/build.gradle.kts` targets API 36 but uses a preview ID; release signing falls back to the debug keystore. Require the owner signing configuration for store builds, a signed AAB, permanent application ID and a documented key backup/update strategy. |
| Server support | [Current matrix](SERVER-COMPATIBILITY.md) includes a locally patched 2.30.0 server candidate. That pass does not establish public compatibility with stock 2.30.0 or current upstream versions. Define supported stock versions and run the existing matrix against those versions; do not require consumers to infer unpublished server patches. |
| Mobile acceptance | [Apple evidence](APPLE-REAL-SERVER-QA.md), [Android status](ANDROID-CURRENT-READINESS.md) and [localization status](APPLE-LOCALIZATION-READINESS.md) retain open hardware, assistive technology, owner-library, real migration and native-speaker gates. Arabic post-sign-in acceptance and Android bookmark-related unknowns remain recorded. Close or explicitly scope applicable claims before launch. |
| TV | [TV status](APPLE-TV-READINESS.md) records two owner-confirmed fixes, with wider remote, accessibility and physical playback acceptance still separate. |
| Web | [Current status](WEB-CURRENT-READINESS.md) retains final deployment, browser/device and legacy retirement criteria. Publish self-hosting instructions with explicit LAN, authentication and media reachability limits. |

## Submission preparation

1. Complete the code provenance/dependency inventory and choose a documented licensing route for each channel.
2. Validate the working name, finalize original brand assets and register identifiers in the owner's accounts. Inventory existing store records before creating new ones. No external messages, registrations or uploads have been performed.
3. Create permanent release build configurations alongside the previews. Enforce store signing; keep credentials, provisioning material, private libraries and device evidence out of public source artifacts.
4. Build one clean candidate per target at a recorded commit and verify exact artifacts on physical devices with the supported stock servers. Reuse existing journeys and evidence where their scope applies; do not label past candidates as checks of this head.
5. Prepare a reachable review demo server with a synthetic account and owned or appropriately licensed sample content. Supply setup instructions and offline/reconnection cases for reviewers.
6. Prepare real screenshots, support and privacy URLs, in-app privacy/license information, accurate App Privacy/Data safety declarations and content ratings. Audit diagnostics and SDK behavior rather than copying upstream's declarations.
7. Run a small beta. Apply the [Play account testing requirement](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en) if the owner's account falls within it. Apple's [SDK requirements](https://developer.apple.com/news/?id=6lxhtioi) and [Google's target API requirements](https://developer.android.com/google/play/requirements/target-sdk) must be checked again at upload time.
8. Submit the reviewed mobile release once its licensing, compatibility and acceptance gates pass. Publish exact matching source and release notes. Seek an [official community-directory listing](https://audiobookshelf.org/docs/documentation/community/community-apps/) after demonstrating stability.

No store release, license change, live-server change, application identity change or claim of completed release acceptance is made by this planning document.
