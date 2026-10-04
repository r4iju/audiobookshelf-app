# Release-market assessment

Checked 2026-10-04 against primary sources. This assesses channels and market evidence, not the local build's readiness.

## Recommendation

Publish a distinctly named, maintained independent client on iPhone/iPad and Android after release validation. Run a small beta first to establish whether the updated experience wins users. Android GitHub APK releases are a useful parallel distribution route. Treat Apple TV as a second wave after its existing native target passes release acceptance. Do not assume the Android mobile target provides Android TV support. A fresh appearance alone is not strong differentiation; reliable offline listening, sync, playback, accessibility and device integration need to justify switching.

## Demand and competition

- The official [Google Play listing](https://play.google.com/store/apps/details?id=com.audiobookshelf.app) reports **100K+ cumulative downloads**, and remains maintained. This demonstrates an existing Android audience, not active users, paid demand, or dissatisfaction with the official client.
- The upstream [mobile README](https://github.com/advplyr/audiobookshelf-app) still describes iOS as early beta, says TestFlight is full, and cites Apple's 10K tester limit. That is a distribution-access opportunity for an App Store client, not evidence that users will switch to this particular fork. Verify actual invitation availability when launching because tester slots fluctuate.
- This is a competitive niche. The [official community-client directory](https://audiobookshelf.org/docs/documentation/community/community-apps/) lists Absorb, AudioBooth, Lissen, plappa, SoundLeaf, Still and others. Voca explicitly supports Apple TV as well as mobile and watch platforms. Therefore “modern Audiobookshelf client” and “Apple TV support” are not empty market positions.
- That directory asks for stable, relatively mature apps and specifically mentions apps abandoned after weeks or months. It also warns about incorrect API use corrupting listening stats or bypassing server restrictions. A supported, compatible client is a more credible promise than freshness alone. Submission to this directory is a suitable discovery channel once stable.
- Upstream remains active: [recent releases](https://github.com/advplyr/audiobookshelf-app/releases) include playback, downloads, auth and platform fixes. Do not market upstream as abandoned.

**Inference:** There is enough observable audience to justify a measured mobile launch, but no primary-source evidence here establishes an unfilled demand for this exact modernization or substantial revenue. Validate with real users before building more platforms.

## Independent identity and licensing

[Upstream's client rules](https://audiobookshelf.org/docs/faq/app/) explicitly welcome third-party clients and do not require them to be free. They prohibit name/logo use suggesting official affiliation without maintainer permission, and prohibit piracy-related use. Use a separate product name, icon, developer identity, application identifiers, support contacts and privacy policy; explain that it connects to Audiobookshelf and is independently maintained.

This fork inherits the upstream [GPL-3.0 license](https://github.com/advplyr/audiobookshelf-app/blob/master/LICENSE). Before distributing binaries, preserve notices and license, mark modifications, and provide the corresponding modified source/build materials according to the license. Upstream saying that third-party clients may be closed source does **not** override the GPL on a derivative of its implementation.

**Unresolved App Store issue:** Review the actual inherited license grants, contributor rights and [current Apple Developer Program distribution terms](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) before claiming iOS distribution is cleared. GPL distribution restrictions and store terms require specific analysis; making source available alone does not establish compatibility. The [FSF has documented App Store GPL enforcement](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement), but that older source does not settle today's specific app. Do not silently relicense others' code or assume upstream TestFlight distribution provides this fork permission.

## Concrete store constraints

| Channel | Requirements that affect the release |
|---|---|
| iOS/iPadOS App Store | Apple membership is [US$99/year](https://developer.apple.com/programs/enroll/); personal enrollment displays the person's legal name as seller. Since April 2026, uploads require [iOS/iPadOS 26 SDK or later](https://developer.apple.com/news/?id=6lxhtioi). Prepare signed release build, unique identity, real screenshots, support/privacy URLs and accurate privacy metadata. Provide reviewers a working demo server/account and legally usable sample content. |
| Google Play mobile | [Play enrollment](https://support.google.com/googleplay/android-developer/answer/6112435?hl=en-EN) costs US$25 once and includes identity verification. New apps/updates must target [Android 16 / API 36 since August 31, 2026](https://developer.android.com/google/play/requirements/target-sdk). New personal accounts created after November 13, 2023 need [at least 12 opted-in closed testers for 14 continuous days](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en) before applying for production access. Prepare signed store bundle and listings. |
| Apple TV | Requires a real tvOS build, [tvOS 26 SDK or later](https://developer.apple.com/news/?id=6lxhtioi), and usable remote navigation. It does not follow automatically from an iOS target. |
| Android TV / Google TV | Needs [TV manifest/launcher declarations](https://developer.android.com/training/tv/get-started/create), touchscreen marked unnecessary, TV assets and a UI navigable from a remote at distance. Current [TV submission target minimum is API 34](https://developer.android.com/google/play/requirements/target-sdk). |

Apple's [review guidelines](https://developer.apple.com/app-store/review/guidelines/) require complete tested builds, reachable backend and reviewer access, accurate metadata and rights to promotional materials. Sections 4.1/4.3 reject copycats, impersonation and indistinguishable apps. Show concrete improvements under an independent brand. Section 2.4.3 requires Apple TV usability with Siri remote or supported game controllers.

Google requires [an accurate Data safety declaration and privacy policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en-gb), including a privacy policy link/text inside the app. Audit credentials, server URLs, listening history, diagnostics and SDKs rather than copying upstream declarations. Account-deletion requirements apply if the app offers account creation; connecting to an existing self-hosted account should be described accurately.

## Sensible launch order

1. Finish branch integration and mobile release acceptance: current auth/server compatibility, offline downloads, progress sync, background playback, lock-screen controls, connectivity failures, accessibility and privacy review.
2. Establish name/icon/package identifiers, source distribution and iOS licensing position. Prepare demo server and legal sample library.
3. Run TestFlight and Play testing with actual Audiobookshelf users; measure repeat listening, download completion and sync errors, and collect reasons to switch.
4. Publish mobile stores plus Android APK release; ask for the official community-directory entry after stability is demonstrated.
5. Expand to TV only after user feedback supports that investment and device-specific builds pass real remote-control playback testing.
