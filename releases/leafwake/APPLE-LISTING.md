# Audiobook Loft Apple listing preparation

Current Apple internal beta preparation is documented in [independent Apple release state](../../docs/apple-independent-release/STATE.md). Build 2 packages independently implemented native Apple code under a scoped MIT grant, preserving origin disclosure and vendor notices. Root GPL and inherited code/history remain unchanged. Both build-2 packages are valid, internal-only and assigned to the owner internal group in TestFlight. Dated licensing and no-upload statements below describe earlier candidates and do not apply as blanket license claims to this independent candidate. No external TestFlight or App Store submission is claimed.

Canonical store fields: [store-metadata.json](store-metadata.json), Apple `en-GB`.

Name: Audiobook Loft
Subtitle: Your books. Your server.
Keywords: audiobook,podcast,offline,player,listen,book,stream,download,progress,PDF
Support: leakwake@mozdom.mozmail.com
Independent bundle identifier: com.forkzed.leafwake
Existing Android privacy policy (not configured for Apple): https://r4iju.github.io/audiobookshelf-app/privacy.html
Support and source: https://r4iju.github.io/audiobookshelf-app/

Audiobook Loft connects to your Audiobook Loft or compatible Audiobookshelf server so you can listen to your own audiobooks and podcasts.

Browse your library, stream audio, keep your listening place across devices and download supported audio for offline listening. Read supported PDF companion documents while listening.

You need a self-hosted server and your own media. No books or subscriptions are included. Compatibility depends on the server version; tested versions and known limitations are recorded on the release page.

Audiobook Loft began as an independently maintained fork of the Audiobookshelf app. Its browser and backend have been rewritten. Upstream copyright and license notices are retained. It is not affiliated with or endorsed by the Audiobookshelf project.

The independently implemented Apple clients are open source under a scoped MIT license. Bundled reader libraries retain their own licenses; inherited repository history and Android code retain their existing licenses.

Source code, license notices, corresponding build materials and compatibility information:
https://github.com/r4iju/audiobookshelf-app/releases

Privacy and support:
https://r4iju.github.io/audiobookshelf-app/

Support: leakwake@mozdom.mozmail.com

## Release notes for maintainers

Audiobookshelf is mentioned descriptively for compatibility, with an explicit independent-maintenance statement. It is absent from the name, subtitle and keyword field. Keywords describe actual functions without other app or company names. Search visibility and review acceptance are not guaranteed.

The separate [Leafwake Audio app record](https://appstoreconnect.apple.com/apps/6819142007) was created on October 5, 2026 for iOS and tvOS, bundle `com.forkzed.leafwake`, SKU `leafwake-2026`, primary locale `en-GB`. Apple rejected the plain Leafwake name as already taken; Leafwake Audio preserves the independent brand without claiming trademark rights. Both versions are in Prepare for Submission. This is not an uploaded build or public availability.

Native inherited GPL distribution rights and current Apple terms must be resolved before public TestFlight or App Store upload. Upstream discussion #2051 remains pending; no exception is inferred from the new backend. Matching public native identity, artwork, signing and license/source notices must be checked on an actual public build after this gate clears. Current simulator evidence covers the preview identity, not a store-signed public build. No Apple Watch, CarPlay, Cast, tablet-specific layout or physical TV acceptance claim is made here.

## tvOS description

Audiobook Loft connects to your Audiobook Loft or compatible Audiobookshelf server so you can listen to your own audiobooks and podcasts.

Browse your audiobook and podcast library, stream audio and keep your listening place across devices. Control playback with chapters, playback speed and a sleep timer.

You need a self-hosted server and your own media. No books or subscriptions are included. On Apple TV, sign in with a local server account. OpenID browser sign-in, downloads, offline playback and document reading are not offered on TV. Compatibility depends on the server version; tested versions and known limitations are recorded on the release page.

Audiobook Loft began as an independently maintained fork of the Audiobookshelf app. Its browser and backend have been rewritten. Upstream copyright and license notices are retained. It is not affiliated with or endorsed by the Audiobookshelf project.

The independently implemented Apple clients are open source under a scoped MIT license. Bundled reader libraries retain their own licenses; inherited repository history and Android code retain their existing licenses.

Source code, license notices, corresponding build materials and compatibility information:
https://github.com/r4iju/audiobookshelf-app/releases

Privacy and support:
https://r4iju.github.io/audiobookshelf-app/

Support: leakwake@mozdom.mozmail.com

TV keywords: audiobook,podcast,player,listen,book,stream,progress

The canonical tvOS description excludes mobile-only downloads, offline playback and document reading. The existing public privacy policy currently covers the Android build; Apple-specific privacy documentation and declarations remain to be completed before submission.

## Saved metadata

Name/subtitle, separate iOS and tvOS descriptions/keywords, marketing and support links were saved and read back through the Apple API on October 5. Both versions remain Prepare for Submission. Privacy URL/text, screenshots, age rating, privacy declarations, review access and a public signed build are not completed by this metadata save.

## Public rename, October 5, 2026

The owner selected Audiobook Loft, preserving `com.forkzed.leafwake`, app record 6819142007 and SKU `leafwake-2026`. The earlier Leafwake Audio name is historical. Name acceptance and saved draft copy do not establish trademark clearance or Apple review approval. Origins, retained upstream notices and independent status are disclosed in the descriptions and native Settings. Public Apple upload remains subject to the documented rights, privacy, signing and review-access gates.
