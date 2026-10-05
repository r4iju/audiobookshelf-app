# Leafwake Apple listing preparation

Canonical store fields: [store-metadata.json](store-metadata.json), Apple `en-GB`.

Name: Leafwake
Subtitle: Your self-hosted audio library
Keywords: audiobook,podcast,offline,player,listen,book,stream,download,progress,PDF
Support: leakwake@mozdom.mozmail.com
Independent bundle identifier: com.forkzed.leafwake
Privacy: https://r4iju.github.io/audiobookshelf-app/privacy.html
Support and source: https://r4iju.github.io/audiobookshelf-app/

Leafwake connects to your Leafwake or compatible Audiobookshelf server so you can listen to your own audiobooks and podcasts.

Browse your library, stream audio, keep your listening place across devices and download supported audio for offline listening. Read supported PDF companion documents while listening.

You need a self-hosted server and your own media. No books or subscriptions are included. Compatibility depends on the server version; tested versions and known limitations are recorded on the release page.

Leafwake is independently maintained and is not affiliated with or endorsed by the Audiobookshelf project.

Leafwake is open source under GPLv3, with applicable third-party licenses retained.

Source code, license notices, corresponding build materials and compatibility information:
https://github.com/r4iju/audiobookshelf-app/releases

Privacy and support:
https://r4iju.github.io/audiobookshelf-app/

Support: leakwake@mozdom.mozmail.com

## Release notes for maintainers

Audiobookshelf is mentioned descriptively for compatibility, with an explicit independent-maintenance statement. It is absent from the name, subtitle and keyword field. Keywords describe actual functions without other app or company names. Search visibility and review acceptance are not guaranteed.

The bundle identifier is registered under the existing developer team. This is prepared listing text, not an App Store record or upload. The signed-in App Store Connect session and creation of a separate Leafwake record remain necessary. Do not reuse the earlier Audiobookshelf record as an independent release.

Native inherited GPL distribution rights and current Apple terms must be resolved before public TestFlight or App Store upload. Upstream discussion #2051 remains pending; no exception is inferred from the new backend. Matching public native identity, artwork, signing and license/source notices must be checked on an actual public build after this gate clears. Current simulator evidence covers the preview identity, not a store-signed public build. No Apple Watch, CarPlay, Cast, tablet-specific layout or physical TV acceptance claim is made here.
