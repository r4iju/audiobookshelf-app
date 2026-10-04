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
| RSS shares and SMTP secrets | #167 | Not yet implemented |
| Covers, metadata providers and editing | #168 | Not yet implemented |
| Listening/year statistics | #169 | Existing progress history is retained; remaining views pending |
| Backup schedule, restore, diagnostics and logging controls | #170 | Manual migration backup/restore exists; remaining controls pending |

No secret is accepted by the general server settings schema. Provider/mail secrets require dedicated private storage and masked administrator projections in their tickets. Unsupported original settings must remain reported by migration, never silently counted as complete. Deprecated Cast settings have no effect in the public Cast-free candidate. Full migration rehearsal remains #172.
