# Leafwake replacement compatibility

The supported release target is the Leafwake 1.0.0-rc.1 unified backend/browser and the independently branded Cast-free Android beta. This replaces the active Audiobookshelf backend as well as the browser. It is not a proxy to an original server. The inherited native clients and migration readers retain their licenses.

## Verified contracts

The replacement uses the native status, password/OpenID login, refresh, REST and Socket.IO contracts. Accounts, original imported IDs, password policies, bookmarks, progress, listening history, readers, collections and private playlists persist in SQLite. Media mounts and source snapshots are read-only; new podcast media is managed under `/data/media`. Browser APIs, realtime and media use the same listener and optional build-time subpath.

Progress reset increments a durable generation, including a reset with no existing progress. A retried reset ID increments once. Reports from an older generation can retain their listening history but cannot restore discarded progress. New listening started while a reset is pending receives the confirmed generation before its first publication. Clients connected to a server without generation metadata retain the explicit cross-tab unconfirmed-delivery fallback.

One-item download routes return streamed ZIP archives, including for a single file. Individual-file routes support authorized ranges. Direct media and HLS sessions check the current account and content policy; closed or revoked sessions stop serving media. Archive concurrency, catalog traversal, sidecar/cover bytes, imports, tool jobs and remote responses are bounded.

## Migration and rollback

Use [MIGRATION.md](MIGRATION.md) and [RECOVERY.md](RECOVERY.md). Imports inventory all tables, columns and nested fields, preserve source hashes, and block cutover for unsupported data. Original author portraits, active old cron backups, nondefault per-show schedules/limits and unknown nonempty extensions need resolution before cutover. A retained archive is not evidence that an unsupported feature was migrated.

A complete synthetic original snapshot has been imported through all five stages, including original OpenID issuer/subject, cover bytes, podcast enclosure/GUID/chapters, private lists, feeds, configuration and 47 seconds of listening history. This proves the exercised schema and contracts. It does not establish acceptance for the owner's live installation, whose deployment target and snapshot have not been supplied.

## Scope limits

- The downloaded product image is Linux arm64. Other architectures must be built from source and verified on their target; no multiarchitecture artifact is claimed.
- Native Android streaming, PDF reading, offline progress and offline completion are exercised against the replacement image. A prior stock Audiobookshelf 2.30.0 offline-completion failure remains a limitation of that stock-server matrix; it is not waived or described as fixed upstream.
- Simulator/emulator evidence is not physical handset, Siri Remote, vehicle or native-speaker acceptance. Physical device and assistive-technology gates stay explicitly recorded.
- Browser comic archives use the documented decoder build without OpenSSL. Password-encrypted comic archives are not a supported release feature.
- No Chromecast is included in the public Android variant. Apple/TV external uploads remain blocked until actual distribution rights and current store terms are resolved. The pending permission request grants no exception by itself.
