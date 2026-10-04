# Administration inventory

The replacement owns these settings; no old administrator frontend or backend is required for them.

| Capability | Replacement surface | Enforcement |
| --- | --- | --- |
| Owner, accounts, library/tag permissions | Accounts | Current SQLite authority on HTTP, media, realtime and jobs (#152) |
| Libraries, mounted folders, name, order, cover ratio, archive | Libraries | Confined paths, stable IDs, producer commit validation, scan/edit exclusion, archive policy on all item projections (#154, #165) |
| Scanner capacity | Server settings | Bounded entries, depth and FFprobe concurrency (#165) |
| Server identity, language and sign-in message | Server settings | Persisted login/status values (#165); translated UI belongs to #171 |
| Password attempt count/window | Server settings | Persisted attempt buckets; changing the window atomically resets old buckets (#165) |
| Browser origins | Server settings | Exact HTTP(S) origins, HTTP CORS/preflight and Socket.IO handshake policy (#165) |
| Podcast discovery, schedules, queue, retention and transfer bounds | Podcast settings | Persisted jobs/timers and current account/media authority (#163–164) |
| OpenID provider and client secret | OpenID sign-in | Encrypted secrets, validated discovery/PKCE, exact callbacks and issuer/subject identity (#166); original migration mappings remain #172 |
| RSS shares, SMTP and e-reader access | Item RSS controls, E-reader delivery, Migration and backups | Explicit public shares, current publisher authority, confined range media, bounded TLS SMTP, encrypted settings and archived configuration, original feed/device import (#167) |
| Book uploads, covers, metadata and removal | Upload and metadata; item management | Current upload/update/delete authority, managed uploads, persisted overrides/covers, bounded optional provider, reversible catalog removal retaining source/history (#168) |
| Listening/year statistics | Statistics and native annual views | Current media policy, numeric contracts, UTC partitioning, personal recent pages and role-gated anonymous server totals (#169) |
| Backup schedule, restore and diagnostics | Migration and backups; image maintenance CLI | Private database/key snapshots, explicit media scope, durable scheduling, manual-preserving retention, empty-volume restore and bounded secret-free diagnostics (#170) |
| Original logging controls | Migration inventory (#172) | Product logs report error categories without settings or credentials; original log settings need explicit migration disposition |

No secret is accepted by the general server settings schema. Provider/mail secrets require dedicated private storage and masked administrator projections in their tickets. Unsupported original settings must remain reported by migration, never silently counted as complete. Deprecated Cast settings have no effect in the public Cast-free candidate. Full migration rehearsal remains #172.
