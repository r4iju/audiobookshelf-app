# Chromecast route status, October9,2026

Upstream discussion2051 still has zero replies; no linking exception was granted. Its permission issue remains open for inherited GPL implementations. This candidate instead removes the confirmed inherited runtime resources and gives owner-controlled replacement Android code a scoped MIT grant. Root GPL and historical distributions are unchanged.

The source uses Google's Default Media Receiver constant, not upstreamFD1F76C5. Google's official web receiver and registration guides explicitly permit the default-receiver path without custom application registration. Custom/styled receivers still require registration. Google SDK additional terms, branding/UI and privacy obligations remain applicable.

Google Maven metadata checked October9 shows current Cast framework22.3.1. The candidate updates framework/cast to22.3.1, base18.7.2, basement18.9.0, flags18.1.0 and tasks18.3.2. Their cached published POMs identify Android SDK terms; they are recorded as proprietary. JSR-330 javax.inject:1 lacks POM license metadata, so its upstream source header was checked: Copyright2009JSR-330ExpertGroup, Apache-2.0. Its notice is retained. The full resolved graph and embedded Google third-party notices accompany the candidate, not a blanket MIT claim for dependencies.

Verification in progress: source generator's inherited-input/freshness regression tests were observed red before implementation, then green. A second red-to-green check rejects Cast notices generated from a Cast-free graph. Core and app unit tests and both variant debug builds passed. Emulator execution and final frozen package audit follow; this document is not a public rollout receipt.

Public defaults remain Cast-free. No upstream contact, discussion closure, public upload, Apple Cast changes or Google Play rollout occurred. The existing public Cast-free privacy policy is unchanged; the separate Cast policy is prepared but not published.

The LAN advertises three VibeCast services. No confirmed Google Cast hardware or authorized target is established by that discovery; advertising a Cast service does not prove a supported real receiver. A physical receiver playback/control/return/progress check and updated Play Data safety remain public Cast release gates. A private .lan hostname or privately issued TLS certificate may prevent receiver access even when phone playback works; do not weaken transport security or expose owner media to work around it.

Review baseline6e07b8d2. This Android change is isolated above the existing Apple release source; it does not waive that branch's outstanding Apple acceptance or merge unrelated pending Apple work.
