# Chromecast route status, October9,2026

Upstream discussion2051 still has zero replies; no linking exception was granted. Its permission issue remains open for inherited GPL implementations. This candidate instead removes the confirmed inherited runtime resources and gives owner-controlled replacement Android code a scoped MIT grant. Root GPL and historical distributions are unchanged.

The source uses Google's Default Media Receiver constant, not upstreamFD1F76C5. Google's official web receiver and registration guides explicitly permit the default-receiver path without custom application registration. Custom/styled receivers still require registration. Google SDK additional terms, branding/UI and privacy obligations remain applicable.

Google Maven metadata checked October9 shows current Cast framework22.3.1. The candidate updates framework/cast to22.3.1, base18.7.2, basement18.9.0, flags18.1.0 and tasks18.3.2. Their cached published POMs identify Android SDK terms; they are recorded as proprietary. JSR-330 javax.inject:1 lacks POM license metadata, so its upstream source header was checked: Copyright2009JSR-330ExpertGroup, Apache-2.0. Its notice is retained. The full resolved graph and embedded Google third-party notices accompany the candidate, not a blanket MIT claim for dependencies.

Verification complete for frozen source62b880281119672743cd68bbb76a57676d9a4549: three generator/notice regression checks,64core unit tests,6app unit tests and9emulator Cast/localization/handover checks passed. Regression checks were observed red before implementation. The final emulator run used the latest source and disabled captures. Two intermediate regressions were corrected: discovery now accepts either real discovered routes or the empty explanation while proving phone continuity, and independently maintained German/Arabic basic labels restore the existing localization journeys. No actual receiver was selected by those tests.

Both debug variants were inspected:136Cast-free versus156Cast-enabled runtime artifacts, exact bundled privacy/licenses/inventory bytes, no copied launcher resources and no production migration fixture assets. Cast classes/default receiverCC1AD845 exist only in the Cast APK; upstreamFD1F76C5 is absent in both. Gradle preBuild refuses any bundled inventory that differs from the exact resolved graph/hashes.

Owner-signed public-identity beta3 APK and AAB were built with the existing upload key and sourceURL pinned to62b880281119672743cd68bbb76a57676d9a4549. Signature/APK identity and exact bundled input checks pass; release targetSDK36/minSDK24. [CANDIDATE.json](CANDIDATE.json) records hashes and limits. These private candidates have not been uploaded or rolled out. Direct APKs use the upload signer and must not be offered as updates to Play-signed installations.

Fresh independent Standards and Spec reviews at62b88028 report zero new source blockers. Their bounded copyright review is recorded in PROVENANCE.md; it is not exhaustive legal certification. Public receiver/disclosure gates below remain open.

Public defaults remain Cast-free. No upstream contact, discussion closure, public upload, Apple Cast changes or Google Play rollout occurred. The existing public Cast-free privacy policy is unchanged; the separate Cast policy is prepared but not published.

The LAN advertises three VibeCast services. No confirmed Google Cast hardware or authorized target is established by that discovery; advertising a Cast service does not prove a supported real receiver. A physical receiver playback/control/return/progress check and updated Play Data safety remain public Cast release gates. A private .lan hostname or privately issued TLS certificate may prevent receiver access even when phone playback works; do not weaken transport security or expose owner media to work around it.

Review baseline6e07b8d2. This Android change is isolated above the existing Apple release source; it does not waive that branch's outstanding Apple acceptance or merge unrelated pending Apple work.
