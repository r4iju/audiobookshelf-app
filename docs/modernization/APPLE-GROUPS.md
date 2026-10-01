# Apple collections and playlists

The native preview browses existing book collections and personal book/podcast playlists through the installed server 2.30.0 contract. Group members retain their server order and episode identity. Playback starts the first playable unfinished member, uses a completed account-owned download when available, and pauses a currently playing group member. This does not introduce automatic queue advancement absent from the baseline.

Collection controls follow update/delete permissions; playlists belong to their authenticated owner. The editor saves metadata, membership and order through separate server operations. Retrying fetches current membership before sending differences, because a failed metadata request can follow a successful membership update. Failed saves retain the draft and explain that partial changes may already exist on the server. Removing the final playlist member requires explicit deletion, matching the server's empty-playlist behavior without accidental deletion.

Mutations pin the canonical server/user identity and invalidate outstanding reads. A late refresh cannot overwrite a completed edit. Book and podcast member detail routes retain their distinct playback identity. Downloads exclude supplementary and ebook-only entries when choosing audio.

## Local verification

Run `bash apple/scripts/verify-ui.sh -only-testing:NativeJourneyTests/CollectionJourney` with the synthetic loopback fixtures. Use `ABS_QA_SIMULATOR='Audiobookshelf Native iPad QA'` for the dedicated tablet simulator. The checks drive the signed production app and observe persisted server membership, real WAV playback and outgoing requests.

Observed meaningful failures preceded implementation for missing group navigation, missing playlist creation, group pause behavior and downloaded-group playback while the server was unavailable. The selected-episode regression was found by source review; its initial UI assertion also exposed an incomplete fixture description, so that failure alone is not evidence of the routing defect.

Completed selected journeys cover browsing order, playlist create/reorder/relaunch/remove/delete, group pause, selected podcast episode details/playback, and actual downloaded book/episode playback without streaming requests. A later review identified stale remote/local progress arbitration in the downloaded path. The completion-after-opening regression first failed by playing the completed downloaded member, then passed after refreshing remote progress and honoring newer durable local positions. Existing offline sessions reconcile a changed position through the player’s seek loop, retaining a newer pause/seek command.

All six journeys passed on the iPhone simulator and on the latest iPad simulator build (October 1, 2026). The first tablet attempt was interrupted after two passes when simulator keyboard animation stalled; the fresh run passed all six. Minimum-iOS-14 source typechecking, 15 shared-core tests, eight fixture/compatibility checks, the shared TV simulator build and strict local signing/packaging passed. The signed preview was installed on both physical devices. Those installations do not establish physical interaction acceptance.

## Remaining acceptance

Permission denial, partial membership failure/retry, unavailable/deleted members, collection editing, podcast playlist membership editing, and physical/live-library acceptance remain unverified. The fixture models selected paths and does not establish complete production parity. Issue #13 remains open until its acceptance is complete.
