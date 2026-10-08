# Audiobook Loft Apple privacy policy

Effective date: October 9, 2026. Developer: Emanuel Franzen. Contact: leakwake@mozdom.mozmail.com.

This policy covers the independent iPhone, iPad and Apple TV clients. You choose and operate, or obtain access to, a self-hosted Audiobook Loft or compatible Audiobookshelf server. The developer does not operate a media relay or require a developer-hosted user account.

## Connections and server data

The app sends credentials or browser authentication responses to your selected server and its configured authentication provider. Server addresses and authentication tokens are saved in device Keychain. Browsing, listening progress, reading progress on mobile, bookmarks and account-authorized editing requests go directly to your server. Listening synchronization includes a generated session/device identifier and generic Apple device information. Your server administrator controls server retention, access, backups and deletion.

Your network provider, server and authentication provider receive ordinary connection information such as your IP address. Media and artwork may use hosts designated by your server. HTTPS uses platform certificate validation. User-selected HTTP servers send unencrypted traffic; use HTTPS or a trusted network.

## Local device storage

Settings, cached catalog data and a journal of unsent listening remain on your device. On iPhone and iPad, downloaded media and saved document locations also remain locally, scoped to the selected server/account. Apple TV does not offer offline downloads or document reading. The bundled mobile document reader operates locally and does not use a cloud rendering service.

The clients contain no advertising, analytics, Google Cast or automatic crash-report upload SDK. Apple may independently process App Store, TestFlight and device information under Apple's policies. The developer receives no automatic copy of your library, credentials or listening history.

Diagnostics remain locally with credential redaction. On mobile you may explicitly copy or share a diagnostic report. Review it before sharing because server or library information can remain. Contacting support voluntarily supplies the information you send; do not include passwords or tokens in public GitHub issues.

## Retention and deletion

Signing out removes the saved connection but can retain recoverable listening and media; it is not a server-account deletion request. Remove downloads in the app, clear diagnostics and remove the app using Delete App rather than Offload App to remove its local app data. Saved Keychain connections should be removed in the app before uninstalling because Keychain data can outlast installation. Copies explicitly shared or saved to other apps must be removed there. Contact your server administrator for server-account or history deletion.

No developer-hosted account is created by these clients. You can use a server without sharing its credentials with the developer. This policy will be updated when data practices change.
