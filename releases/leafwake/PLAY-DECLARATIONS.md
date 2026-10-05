# Play beta distribution and declarations

The free public package is `com.forkzed.leafwake`, default language `en-GB`, target SDK36. Initial distribution uses Google Play App Signing with Google's existing app signing key. The owner's private key signs the uploaded AAB as the upload key. Do not publish an owner-signed direct APK under the same package: that certificate cannot update the Play-signed installation. Internal preview APKs retain their separate identity. Automatic installer protection remains off.

The signed beta must link the exact reviewed source revision and bundle the generated GPL/dependency notices and privacy policy. No GMS or media3-cast runtime dependency is allowed in this variant. Archive its runtime inventory, artifact hash and upload-key certificate fingerprint. Never archive the key, signing configuration or service-account credentials.

## Data safety mapping

The developer receives no automatic telemetry or library data. The app nevertheless sends data off-device to the server the user selects. Treat these transfers as collection for the form rather than claiming that all data stays on-device. The mapping is for the Cast-free variant only:

| Data | Purpose and handling |
| --- | --- |
| User IDs and authentication information | Account management and app functionality; needed for sign-in to the selected server. |
| Device or other IDs, device manufacturer/model, Android and app version | App functionality and listening-session identification; a random saved installation UUID accompanies playback and listening synchronization to the selected server. No advertising identifier or developer analytics copy. |
| Name and email address | Optional RSS owner fields, entered by an account allowed to publish a feed. Sent to the chosen server and exposed in the public feed when indexing is permitted. |
| App interactions, in-app searches, and other user-generated content such as bookmarks | App functionality and progress synchronization; retained on the selected server according to its administrator's policy. |
| Files or documents explicitly shared with another app | User-selected transfer, with the destination controlled by the user. The app does not upload a developer analytics copy. |

User-directed transfers to a chosen server or chosen sharing destination are disclosed in the policy. Their sharing classification must follow the actual Console definitions and the user-initiated-transfer exception. Do not claim advertising, fraud analysis, developer analytics, sale, or automatic crash reporting. Do not claim all traffic is encrypted: user-selected plain HTTP servers are supported. Local diagnostics stay on the device unless the user chooses to share them.

Audiobook Loft does not create a developer-hosted account. Users authenticate to an existing self-hosted account. Server-side deletion is controlled by that server's administrator; local deletion instructions are in the privacy policy. Do not promise a developer deletion service for data the developer does not possess.

Definitions: [Google Play Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en-GB). Recheck the final form against the uploaded binary and all distributed versions.

## Review and account gates

Use only synthetic media in screenshots and a reachable review server. A loopback QA server is not review access. The owner cutover reached Audiobook Loft at `audiobookshelf.nginx.lan`, and the NAS has recovered. The existing public hostname has restrictive access rules; a separate globally reachable synthetic review server remains necessary. Do not supply private owner credentials to reviewers.

The personal Play account requires12 opted-in closed testers for14 continuous days before applying for production access. Upload, internal testing, closed testing, production application, review approval and public availability are separate states. Record each actual Console/API result. No tester enrollment or elapsed testing period is inferred from an uploaded artifact.

Requirement: [Google's personal-account testing policy](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB).

## October 5 Console results

Version code 1 is available to the selected owner-only internal testers. Closed alpha has version code 1 saved as a validated draft, without rollout or enrolled closed testers. Music & audio, six listing graphics and foreground-service declarations are saved. User-requested download and media-playback demonstrations are published with release rc.4. Sign-in review access, target audience and final Data safety submission remain incomplete. No production approval is claimed.
