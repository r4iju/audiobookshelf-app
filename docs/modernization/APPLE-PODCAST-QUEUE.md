# Apple podcast server-download recovery

Incremental delivery for #14. The server 2.30 queue omits the active job and removes completed failures, so an empty queue is not proof of success. The native app now owns the authenticated realtime connection independently of podcast detail navigation. Received failure events are saved atomically per canonical server/user/podcast/enclosure before being presented. Requested intent is saved before the HTTP queue request; an ambiguous response retains that intent. Enclosure URLs are stored as SHA-256 identifiers, not private feed URLs.

Failed job IDs are retained with the request. Retrying changes its state to pending; another receipt for a previously recorded failed job cannot fail the new attempt. Original preview pending hash preferences are adopted once, after the manifest is saved, without deleting the original preferences.

The realtime transport uses the existing Engine.IO 4 / Socket.IO websocket contract, platform TLS validation, the reverse-proxy subpath including its required trailing slash, current credentials, and an authenticated init matching the pinned account. It answers heartbeats, expires stalled authentication, and reconnects with bounded backoff. Account replacement stops the old connection and rejects old callbacks.

Unreadable manifests are preserved and prevent writes. If a received result cannot be saved, the warning offers saving retry; its in-memory receipt remains available while the process lives. A new queue request waits for those results to be saved. Successful durable episode reconciliation retires only matching obsolete receipts. Storage and authentication warnings are separate. This does not guarantee receipt survival if the process terminates during a failed disk write.

## Local verification

`bash apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/PodcastJourney` runs nine production UI journeys against synthetic local media and HTTP plus real Socket.IO 4.7.4. The primary HTTP fixture is proxied through the same websocket origin. The wrapper owns loopback ports 19765, 19766, 19767 and 19769 and cleans up its processes. Install the pinned dependencies with the repository's configured route if `verification/realtime/node_modules` is absent; no cloud service is used.

New journeys were observed failing before implementation:

- A failed active job omitted from the queue left the app waiting. The implemented event handler retained failure and recovery through relaunch.
- Leaving the podcast screen lost its subsequent failure event. Moving event ownership to the application retained it while browsing elsewhere.
- A failure receipt repeated after retry marked the new attempt failed. Persisting prior failed job IDs retained the retry until its episode became available.

The complete nine-case iPhone podcast run passed. The latest three failure/relaunch/navigation/retry cases passed on iPad after the storage-retirement correction. It also covers permission-gated creation/discovery, existing RSS metadata preservation, completion filters, independent episode playback/resume, and stale detail updates. A first websocket run failed because URL normalization removed the required Socket.IO trailing slash; inspection of the installed Engine.IO matcher identified the cause, and the corrected URL passed.

The updated fixture also passed the qualified-LAN HTTP/untrusted-TLS rejection journey and real multi-file audio/navigation journey on iPhone. Minimum iOS 14 source typechecking, 15 shared-core tests, eight fixture/compatibility/upgrade tests, two legacy realtime tests and the TV simulator build passed. Strict local signing and packaging passed, and the latest preview was installed on the physical iPhone and iPad. Installation does not establish physical interaction or live acceptance. These checks do not establish iOS 14 runtime acceptance. Review found and corrected obsolete unsaved receipt retirement; that disk-error edge has source-review evidence without a UI acceptance test.

## Remaining acceptance

The full #14 realtime contract, native reconnection/account-switch event acceptance, physical device interaction, interrupted storage recovery, actual queued episode playback, and live-server acceptance remain open. Server 2.30 does not expose a completed-failure history. Events missed during disconnection, suspension or termination cannot be reconstructed from the queue alone. Such unresolved requests remain pending with foreground refresh and feed retry available; this slice does not claim automatic recovery of missed events or close #14.
