# Audiobook Loft privacy policy

Effective date: October 5, 2026. Developer: Emanuel Franzen (GitHub account r4iju).

Audiobook Loft is an independent app for a self-hosted Audiobook Loft or compatible Audiobookshelf server that you choose. This policy describes the Cast-free Android public build. Cast-enabled internal previews are not covered by its no-telemetry statement and are not offered as public Audiobook Loft releases.

## Your server and local storage

When you connect, Audiobook Loft sends your server address, username and password or browser authentication response to that server to authenticate. The app stores server/account information and authentication tokens on your device so you can reconnect. Downloaded audio, companion documents, settings, reading locations, listening progress and a journal of unsent listening are also stored locally. Listening and reading progress are sent to your server to support synchronization and statistics. Your server administrator controls server-side retention, access, backups and deletion.

The app generates and saves a random installation identifier. Playback and listening synchronization send this identifier, the app version, device manufacturer/model and Android version to your selected server to identify the listening session. It is not an advertising identifier, and the developer receives no analytics copy.

The developer does not operate a media relay, require a Audiobook Loft cloud account, or receive your library, credentials or listening history. The Cast-free build has no advertising, analytics or automatic crash-report upload SDK. Android and Google Play may separately process device or app information under their own policies.

## Connections and optional actions

Your device connects directly to your server and any authentication provider that your server directs you to. Server responses may refer to artwork or media on other hosts, and network providers receive ordinary connection information such as your IP address. HTTPS uses the device trust configuration, including certificate authorities you have installed. The app supports user-selected HTTP servers; HTTP traffic is not encrypted. Use a trusted network or configure HTTPS when sending credentials or media over a network you do not trust.

Downloads use the storage location you select. Sharing a file or opening a document in another app passes the file to the app you choose. Notifications and background services support playback and downloads. Diagnostic messages remain on your device, with credential redaction and a limit of 100 entries. You decide whether to share diagnostics with support; review them first because messages may contain server or library information.

If your account can publish an RSS feed, the app sends the feed settings to your server. Allowing indexing can include the owner name and email address you enter in the publicly accessible feed. Feed links also expose the selected media to anyone who can use the link. Publish only information and media you intend to share, and close the feed on your server to stop access.

## Retention and deletion

Local data remains until you delete downloads, clear diagnostics, clear the app's storage or uninstall. Signing out removes the saved connection but deliberately retains recoverable listening and downloads; it does not delete your server account or all local media. To remove all local data, use Android Settings to clear Audiobook Loft storage, and separately delete any downloads saved in a user-selected shared folder. Contact your server administrator to delete server-side history or an account. Audiobook Loft does not create developer-hosted user accounts.

## Support

For privacy questions contact the developer through https://github.com/r4iju/audiobookshelf-app/issues. Do not include passwords, authentication tokens, private server addresses or personal libraries in public issues. If you post an issue, GitHub processes that information under its privacy policy. This policy will be updated when the public app's data practices change.
