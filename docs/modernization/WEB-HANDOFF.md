# Next.js browser client handoff

Branch `fork/nextjs-client`, based on `origin/fork/native-tv` at `39ad6af65715957c585e7b0f0d20238ebe60ee8f`. The
client is the isolated `web/` package. It does not touch the legacy Nuxt app, the native apps, the server, or the
shared modernization documents. Issues #55 to #65.

- How to run and deploy it: [web/README.md](../../web/README.md), [web/docs/DEPLOYMENT.md](../../web/docs/DEPLOYMENT.md)
- What it needs from the server: [web/docs/SERVER-CONTRACT.md](../../web/docs/SERVER-CONTRACT.md)

## Commits

| Commit | Scope |
| --- | --- |
| `edd63ce0` | Package, server connection, password sign-in with rotating tokens, saved servers, library shell |
| `101313e3` | Library browsing, search, series, authors, item details, persistent player, durable progress outbox |
| `c1a2d84e` | Test wait for the library page before the skip-link check |
| `c31890e4` | Ended sessions recover in place; live progress from other devices over socket.io |
| `18b42819` | Podcast episodes, latest episodes, podcast creation and downloads, collections and playlists |
| `10cb7568` | Browser reader with PDF and shared reading places |
| `2e84297e` | EPUB reader |
| `a762b943` | MOBI and AZW3 reader |
| `3e9abd08` | CBZ and CBR comic reader |
| `c037f578` | Settings, diagnostics, item downloads |
| `92652d5d` | Listening statistics and year in review |
| `1e810f4a` | OpenID sign-in, plain-HTTP origin fallbacks, production image, same-origin compose and nginx deployment under `/web` |
| `eef093ba` | Discarding progress resets this device too (player position and unsent listening) |
| `e109644f` | RSS feeds (open, view, close) and send ebook to an e-reader |
| `57ae6ae4` | README, deployment and server-contract docs, this handoff, formatting fix for `e109644f`'s spec |
| `eb6980e3` | Discard ordering: the reset belongs to the account it came from, survives switches and new playback during the close, and waits for listening already on its way |
| `df948480` | Discard barrier: a late session open cannot undo the reset, and listening begun after the reset is held until the delete is done |
| `f4e8d15f` | Discard holds last as long as their tab, however slow the delete, and tabs taking or releasing holds at once keep each other's |
| `c68e6c1e` | A discard is kept until the server confirms its delete: refused or abandoned deletes are sent again by any tab, playing it meanwhile starts from the beginning, and the item page shows it pending |
| `5710199f` | A discard accounts for listening any tab already sent, on plain-HTTP origins too: tabs record exactly what they send in IndexedDB; a discard deletes once those requests are answered, and otherwise is left unconfirmed for the user to keep or discard anyway |
| `5a56386d` | Records the full local run on `5710199f` |
| `cc26ec24` | A discard's delete is claimed in IndexedDB, so no tab can keep it once it is issued; listening goes out one session version at a time, and reader places and finished changes are recorded like listening |
| `56e92c87` | A reader place that waited for a discard which then deleted is dropped |
| `df362fbd` | Reader places are recorded when the page turns, not when their turn to be sent comes; stored coordination records are checked, and those an earlier version left are read as it meant them |
| `2baac784` | Records the full local run on `df362fbd` |
| `4f4bb7cd` | The QA fixtures (OpenID provider, podcast feed, SMTP sink) run as containers in the QA server's own network, adopted from the fixture-network branch |
| `96cbb5f7` | Formatting of `qa/server.mjs` |
| `a6961e2b` | Removing an episode leaves its page even when the server's update arrives first |
| `843a928c` | Only blocks whose delete was never issued are cleaned up when their book cannot be read; removing an episode leaves its page only if that page is still showing for the same account |
| `d272afbf` | Restart recovery: a delete that may still be running, with no discard left to finish it, is released only by a server restart the user asked for and then confirmed, retiring only the records recorded at the request |
| `296259de` | A restart request is used only if it is the account's own; a retired delete ends as a confirmed one; a request sent again after a renewed sign-in is a new attempt |
| (this commit) | Records the full local run on `296259de` |

## Checks

Run from `web/` on the Studio, against the isolated QA server only:

```sh
npm run lint && npm run typecheck && npm test && npx playwright test
```

Last full run, on `296259de` (Studio, Chromium; the commit after it changes only this file), log
`web/qa/.runtime/final-check-16.log`. The chain was `node qa/fixture-network.mjs 60`, then
`npm run lint && npm run typecheck && npm test && npm run build && npm run qa:deploy -- up && npx playwright test`:

- Fixture network check: **failed**. Of 3,424 connections from inside the QA server's network, 3 took just over a
  second: OpenID 1 of 1,144 (max 1,026 ms), mail 2 of 1,142 (max 1,069 ms), feed 0 of 1,138 (max 786 ms). None
  errored or timed out. The Studio's load average was 353 to 483 at the time. Run again alone straight after
  (`final-check-16-fixnet-rerun.log`, load 259 to 367), it passed: 3,550 connections, none failed, max 33 ms. The
  one-second threshold is what the check is for, so this run does not show the fixture network free of stalls
  under that load;
- Biome clean (1 info: the `recommended` field in `biome.json` is deprecated);
- `tsc` clean;
- vitest: 114 passed in 17 files;
- production build and deployment image built;
- Playwright: 63 passed, none skipped or failed, in 4.7 minutes. That includes the restart recovery journey, which
  restarts the QA server container `abs-web-qa` (not the owner's server), and the 7 deployment journeys against the
  image built from that commit, the OpenID journeys and the e-reader journey. The checks that a restart request
  must be the account's own are unit tests; no journey covers them.

Checked by hand on `296259de` in the T3 preview (the dev server, signed in to the QA server as `qa`): with a held
delete and a restart request naming another account seeded in IndexedDB, the shell showed the unreadable-request
notice with **Restart the server**; choosing it kept the foreign request as a `restarted:...:unreadable-...` record
and showed the request notice with **I restarted the server**, covering only this account's delete. The preview's
screenshots failed, so the notice text and stored records were read from the page. The seeded records were removed
afterwards, and nothing was confirmed.

Superseded runs: on `843a928c` (`final-check-14.log`) everything passed (101 unit tests, 62 journeys, no fixture
stalls); the run on `d272afbf` (`final-check-15.log`) was stopped part-way when review found the problems fixed in
`296259de`, and is not evidence for either commit. On `df362fbd` (`final-check-10.log`) 98 unit tests and 61 journeys
passed. On `56e92c87`, 54 passed and 7 failed with loopback connection errors and one click timeout, before the
fixtures moved into the QA server's network (`4f4bb7cd`).

Intermittent failures seen in full runs on `df948480`, `f4e8d15f` and `5710199f`, none reproduced on retry:

- Three journeys failed once each because the QA server's request to a loopback fixture on the host stalled: the
  OpenID token exchange (19884, "outgoing request timed out after 10000ms"), the SMTP sink (19886, 36 seconds to
  send) and the podcast feed (19885, "timeout of 30000ms exceeded"). Each is the server container reaching the Mac
  through colima's `host.docker.internal` (192.168.5.2, resolved from `/etc/hosts`, so not DNS). The deployment
  journeys then passed 5 of 5 alone and 50 of 50 repeated.
- The AZW3 reader journey's `toBeInViewport` check failed again once. Its cause is still not diagnosed.

Every behaviour change since the first commit started from a failing test that was observed failing, then made to
pass. The browser journeys drive the production UI in Chromium. They check results on the server (its API and files)
and in the browser's durable state, not component internals.

## Evidence and what it is

| Evidence | Kind |
| --- | --- |
| Browser journeys in `web/e2e` | Fixture: Chromium (Playwright 1.62.1) against an unmodified Audiobookshelf 2.30.0 container with a synthetic library and synthetic accounts, all on loopback |
| `e2e/deployment.spec.ts` | Fixture: the production image built from `web/Dockerfile` and run by `deploy/compose.yaml` with nginx. One plain-HTTP origin (`abs-web.test`, mapped to the proxy) serves the server and the client. OpenID sign-in through a loopback provider (`qa/oidc.mjs`). Two tabs on that origin, where Chromium offers no Web Locks: a discard stays unconfirmed, without deleting, while the other tab's listening is held in transit, and finishes once it is answered; after a delivery that failed without an answer, Keep progress deletes nothing and Discard anyway deletes |
| `docs/modernization/evidence/web-legacy-ui-through-proxy.png` | Fixture: the server's own web interface signed in through the same proxy, with its socket connected (`ws://abs-web.test/audiobookshelf/socket.io`) |
| Send to e-reader | Fixture: the QA server's real mail path to a loopback SMTP sink (`qa/mail.mjs`). No mail left the machine |
| RSS feeds | Fixture: the QA server serves the opened feed's XML, and returns 404 once it is closed |
| Audio | Fixture: real MP3, M4B and podcast files decoded by Chromium. The position is read from the player and progress is observed on the server. No physical audio output was checked |

No journey ran against the owner's server, the owner's data, a real identity provider, a real e-reader or mail
server, or a physical device. The production container `audiobookshelf` (port 13378) was never touched.

## Remaining gates (not met by this branch)

- **Real browsers.** Only Chromium was automated. Safari (macOS and iOS) and Firefox, including Media Session,
  background audio and autoplay rules on phones, are unchecked. Playwright's own Firefox and WebKit builds are not
  installed on the Studio (only `chromium-1234`): a run with them stops at "Executable doesn't exist" for
  `firefox-1538` and `webkit-2336` (`web/qa/.runtime/engines-unavailable.log`). Installing them downloads from
  Playwright's CDN, which needs the user's authorization for that egress. The config is ready; from `web/`:

  ```sh
  npx playwright install firefox webkit
  ABS_WEB_ENGINES=firefox,webkit npx playwright test --project=firefox --project=webkit \
    e2e/playback.spec.ts e2e/readers.spec.ts e2e/session.spec.ts
  npm run qa:deploy -- up && ABS_WEB_ENGINES=firefox,webkit npx playwright test --project=firefox \
    --project=webkit e2e/deployment.spec.ts
  ```

  Without `ABS_WEB_ENGINES` only Chromium runs, as before. Some journeys state what Chromium does, such as the
  deployment journey's two tabs without Web Locks on a plain-HTTP origin, and may need their own expectations per
  engine. Playwright's WebKit is not Safari: it shares the engine, not Safari's media, autoplay or storage policies,
  and whether its build runs on macOS 27 is unknown. Neither replaces checking Safari on a Mac and an iPhone by hand.
- **The owner's server and network.** No deployment beside the owner's server, behind the owner's HTTPS proxy and
  host name. That deployment is the root coordinator's call, following DEPLOYMENT.md.
- **A real identity provider.** Only the loopback provider was used. A real provider adds consent screens, its own
  key rotation and logout.
- **Real e-reader delivery.** This needs the owner's SMTP settings and a device.
- **Physical listening.** Audible output, Bluetooth and lock-screen controls, long sessions and sleep.
- **Release acceptance** (#55 and the parent issue). Compatibility, preservation and the owner's acceptance remain
  required before this client replaces anything. The legacy interface stays served by the server at `/`.

## The owner's deployment, as read

Read-only, on 2026-10-02, without changing or restarting anything:

- The owner's server runs 2.30.0 at exactly the digest the QA server pins (`sha256:6fbd7dc9...`), but its compose
  file names it by the `latest` tag, so a pull and recreate would upgrade it without the checks in
  SERVER-CONTRACT.md. Pinning that digest is the owner's call.
- The LAN proxy in front of it is nginx with one route to the server: it passes `Host` (as `$host`, without a port,
  which suits the default ports it serves), `X-Forwarded-Proto` and WebSocket upgrades, and does not buffer. It has
  one upstream, so it has no other server to retry a request on; the restart recovery's proxy caveat is about
  proxies that do. Serving this client means adding a `/web` route to the client's container there, as
  `deploy/nginx.conf` does, and keeping `/` on the server.
- The public route to the server admits only the apps' user agents and refuses browsers, by design. The browser
  client is therefore LAN-only (or through the owner's VPN) unless the owner adds a browser route. A gate that signs
  people in with a cookie in front of it would refuse the client's API requests, which send no cookies
  (`credentials: "omit"`); that is from the code and was not tried.

No owner hostnames, addresses or account details are recorded here, since this repository is public.

For a deployment beside an existing proxy, `web/deploy/existing-proxy.conf` is the one route to add, and
`web/qa/smoke.mjs <origin>` is a read-only check of the result (GET requests only, no sign-in). On 2026-10-02 it first ran while Docker's storage in the colima VM was failing with
write I/O errors (`web/qa/.runtime/smoke-qa-deploy.log`), and correctly reported the broken fixture (the client's
scripts and the server's interface answering 500). After the VM was restarted (by someone other than this lane) and
showed no further I/O errors, the deployment fixture was rebuilt from `0bd3ab11` and passed all four checks, and the
7 deployment journeys passed against it, including OpenID sign-in, readers and playback over the one origin
(`web/qa/.runtime/smoke-healthy.log`). Neither was run against the owner's server.

## Decisions and known differences

- **Server 2.30.0 only.** OpenID needs the same origin, and a return address without a port. Port-addressed
  deployments get password sign-in only (see DEPLOYMENT.md).
- **Reader places.** PDF and comic places are the 1-based page as text, as in the other clients. EPUB places are CFIs
  saved as the legacy reader saves them. MOBI and AZW3 places are the browser's own `mobi:<version>:<section>:<block>`,
  because the legacy clients never saved one.
- **EPUB locations.** Generated EPUB locations are cached in the browser for the ten most recent books.
- **MOBI and AZW3 content** renders in a same-origin frame without scripts, so a book cannot act as the app.
- **libarchive.** Its worker and wasm are copied into `public/libarchive` before dev and build (git-ignored).
- **Comic places** are saved when the reader turns or chooses a page. Opening a comic does not save one.
- **Downloads** carry the access token as `?token=`, as the server's own interface does.
- **Mobile-only settings are not ported.** The automatic sleep timer and the chime were Android-only in the legacy
  app, and haptics and cellular rules have no browser equivalent.
- **Year in review** is HTML and CSS, not the legacy canvas image.
- **QA fixtures.** The OpenID provider, podcast feed and SMTP sink run as containers in the QA server's own
  network. The server reaches them as `host.docker.internal`, mapped to its own loopback, which its SSRF filter
  allows through `SSRF_REQUEST_FILTER_WHITELIST`.
- **Latest episodes** lists the newest unfinished episodes across podcasts, from the server's `recent-episodes`
  endpoint.
- **Audio coexistence.** The reader keeps the player playing underneath; a second tab is a second player.
- **RSS feeds** follow the legacy item menu. Administrators open and close them; anyone sees an open feed's address.
  Opening needs an item with audio. The legacy slug cleaning is applied before opening, and the address shown is
  exactly the one used.
- **Listening is sent one version at a time.** Reports carry a session's cumulative totals, and 2.30.0 overwrites a
  session it already has with whatever request finishes last. So a newer version of a session is sent only after the
  request carrying the previous one was answered, by any tab; IndexedDB records which version each tab issued. A
  version whose request failed without an answer, or that another tab left unanswered for five minutes, is frozen:
  it is only ever sent again unchanged, and the session goes on under a new random id whose report carries only the
  listening after the frozen one (its `startTime` is where the frozen one ended). However late the frozen request
  lands, it rewrites its own session with the same values, so no session is lowered and the listening time adds up
  to what was played, split over more than one session in the server's history.
- **Discarding progress** is a recorded intent that ends only when the server confirms the delete. For the
  account the discard came from only:
  1. a hold is stored for the book or episode, naming the progress row to delete. While it exists, no tab delivers
     that account's listening for it. Each hold has its own stored entry, so tabs discarding at once never
     overwrite each other's;
  2. this device drops its unsent listening for it, and the player (if it holds that book for that account) goes
     back to the start, paused. A session still being opened for it is let go when it arrives. Playing it again
     while the hold exists starts from the beginning, not from the server's old place;
  3. the old playback session is closed without a final report;
  4. the book is blocked in IndexedDB, and the reports dropped in step 2 are retired there, so a tab whose copy of
     the queue still has them never sends them. Anything for the book that any tab of the account recorded as sent
     (listening, a reader place, finished) must be answered (see below);
  5. the discard moves to **deleting** in IndexedDB, and the server's progress row is deleted;
  6. once the delete is confirmed, the discard is **finished**: the block and the hold end, frozen listening for the
     book (which carries the old place) is dropped, and listening recorded since step 2 is delivered as new
     progress. A tab waking late neither blocks the book nor deletes again.

  Where a discard stands (blocked, deleting, finished or kept) is one IndexedDB record that every step changes
  inside a transaction, so tabs agree on it with or without Web Locks. **Keep progress** succeeds only while the
  discard is blocked. Once the delete is issued it can no longer be kept, from any tab: the hold stays until the
  delete is answered, and the item page shows it pending. Tabs learn of each other's changes through storage events.

  Every tab records exactly what it is about to send in IndexedDB, reading the queue and checking the blocked books
  in the same transaction, then sends exactly that. A delivery recorded before the block counts against the
  discard, and one recorded after it leaves the book out. A record ends only with the server's answer to that
  request. A request that failed without an answer stays recorded, since it may still reach the server, or still be
  running there. Reader places and finished changes (`PATCH /api/me/progress`) are recorded the same way, at the
  moment they are made: a reader sends its places one at a time, so a place can wait behind earlier ones, and a
  discard waits for every place made before it began, which then reaches the server before the delete. One made
  while the book is blocked waits instead: it is sent if the discard is kept, and dropped if any discard of the book
  deletes after it was made, since it may carry the old place. The next page turn saves the place again. A discard
  moves to deleting only in the same transaction that finds nothing for the book being sent.

  The records are checked when read, whichever version of this client wrote them. The version before `cc26ec24`
  stored blocks without a phase while its delete could already be on its way, discards that deleted as `finished:`
  records, and what it sent as `reports`, which is read as failed without an answer. A block without a readable
  phase leaves its discard unconfirmed: nothing is deleted by itself, and Keep progress is refused too, since its
  delete may still land, so Discard anyway is the way out. A record whose book cannot be read blocks, or counts
  against, every book; such a block that no hold of this device is finishing is removed only if its phase is
  readably blocked, since its delete was never issued. A playback session record that cannot be read is not sent, until a discard of its book drops its
  listening. Before a reader place recorded when it was made is sent, it checks that it still counts, so one still
  waiting its turn when the user discards anyway is dropped.

  2.30.0 shows nothing that says a given request is done. `local-all` requests for one session run independently,
  and one that finds no progress row creates one, so neither a copy sent again nor the server holding that listening
  proves the original cannot land after the delete. So:

  - if the only deliveries on their way are this tab's own, the discard waits for their answers and finishes;
  - otherwise it is left **unconfirmed**. The item page says "Discarding progress. Progress for this sent earlier is
    not confirmed by the server and could bring the old place back. This finishes by itself if it is confirmed;
    otherwise keep the progress, or discard anyway and accept that the old place may return." and offers **Keep
    progress** (nothing is deleted, and the held listening is delivered) and **Discard anyway** (the delete is sent;
    the old place can come back only if that request still lands, and discarding again then removes it). Any tab of
    the account finishes the discard by itself once the other tab's answers are in. Nothing is decided from time
    passing, and nothing but the user's choice overrides an unconfirmed request.

  If the delete fails, the discard says so where it was asked, the item page shows "Discarding progress. It
  finishes when the server can be reached.", and the hold stays. The next delivery from any tab of that account
  sends the delete again, and the listening is delivered only after it is confirmed. A tab that goes away or stops
  answering mid-delete is finished the same way: where Web Locks exist, as soon as its lock is gone; on plain-HTTP
  origins, after five minutes without its once-a-minute heartbeat. Silence never releases the listening; it only
  lets another tab try to finish the discard, under the same rules. Sending the delete again, or a frozen tab's
  delete arriving late, is safe: it names the old row, and 2.30.0 saves later listening in a new row with a new id
  (`UUIDV4`), and answers 200 for a row that is already gone.

  Limits:

  - A tab that crashed, was closed or froze with a delivery on its way leaves later discards of that book
    unconfirmed until it answers or the user chooses. A request that failed without an answer does so for good,
    until the user chooses Discard anyway.
  - Keep progress does not bring back the unsent listening that step 2 dropped from this device.
  - Reader places have no version guard in 2.30.0: a place whose request failed without an answer can still land
    after a newer one and move the place back, until the next page turn saves it again.
  - Any request that throws, including a proxy's 502 or 504, counts as failed without an answer, since the server
    behind the proxy may still have applied it.
  - The queue in localStorage is rewritten by each tab without a cross-tab lock. A tab removing delivered reports at
    the moment another records one can drop that one report; the next report of the same session (every 15 seconds
    while playing) carries the same totals and more.
  - IndexedDB keeps one small record per playback session ever sent, and one per discard; nothing prunes them.
  - For a discard left by the version before `cc26ec24`, the item page still offers Keep progress, which leaves it
    unconfirmed.
  - A block whose delete may have been issued and that no hold is finishing (one whose book cannot be read holds
    back all of the account's listening) is released only by the restart recovery below. Until then that listening
    waits on this device.
  - A reader place made before a discard and still waiting its turn in a tab that then closes stays recorded, so
    discards of that book are unconfirmed until the user chooses.
  - A browser that refuses IndexedDB delivers no listening and saves no reader place; each attempt fails as an
    outage would, and nothing is sent unrecorded.

  Other books and other accounts stay playable and keep delivering throughout. A storage refusal in steps 1 or 2
  fails the discard before anything is sent, so the server's progress is unchanged. A refusal part-way through
  step 2 can leave this device partly reset (the unsent listening dropped but the saved player place not yet
  written); discarding again once storage accepts writes finishes it.

  **Restart recovery.** 2.30.0 offers no way to learn that a request it is still handling has finished, but a
  restart of the server ends them all. Where a delete may still be running and no discard is left to finish it, the
  shell shows "Progress from this browser is held back", naming the server's origin, with **Restart the server**.
  Recovery has two steps, as in the native apps:

  1. **Restart the server** records, in IndexedDB and before the owner restarts anything, exactly the records the
     restart is to end, with their stored values: those deletes, and every request recorded as sent except this
     page's own still waiting for an answer. The record is bound to the account (whose id names the server) and to
     the server's origin, and a second request does not replace it. The notice then says to restart the server at
     that origin and confirm, and that the browser cannot tell whether it restarted: if it did not, a delete still
     running there can remove progress sent after confirming.
  2. **I restarted the server** retires, in one transaction, only the recorded records whose values are still
     exactly as recorded, and only for the same account and origin; otherwise nothing is retired. Records written or
     changed after the request stay held, since they may have reached the restarted server. Each failure of a request
     is recorded with the attempt it came from, so the same request failing again after the request is a changed
     record and stays held. The request is kept as a `restarted:` record of the values it retired. The queue and
     session records are untouched, so the held listening is then sent as it was recorded. Listening another tab was
     sending under a retired record is sent again, unchanged, as after a failure, since that tab's answer no longer
     finds its record. A retired delete ends as a confirmed one does: listening versions that failed without an
     answer for its book (for every book, if its book cannot be read) are never sent, since they may carry the
     deleted place, and are kept in the `restarted:` record instead; a reader place that waited for it is dropped.
     A request sent again after a renewed sign-in is first recorded as a new attempt, so a restart asked for before
     then does not retire it.

  A restart request is used only if it is this account's own: stored under the account's key, naming the account, and
  covering only the account's own delete and sending records, each stored under the key it names. Any other, like
  one that cannot be read, releases nothing. The notice says so, and **Restart the server** sets it
  aside (kept, as a `restarted:` record) and records a new one, so only a restart after that new request counts.

  Nothing is released by time passing, and the moment of confirming is not taken as the restart. The confirmation
  is the owner's word that the server restarted: 2.30.0 exposes no boot identity the browser could compare. A request
  that failed after the restart request, for a request that was itself covered, is a changed record and stays held,
  so that case needs a second restart. A proxy that holds or retries a request across the restart would defeat it:
  nginx, for one, can retry an idempotent request such as `DELETE` on another upstream server. No proxy's behaviour
  across a restart was tested.

## Ports

QA fixtures use 19880 to 19886 on loopback only:

| Port | Fixture |
| --- | --- |
| 19880 | Server |
| 19881 | Development client |
| 19882 | nginx |
| 19883 | Production client |
| 19884 | OpenID provider |
| 19885 | Podcast feed |
| 19886 | Mail sink |

They overlap with none of the ports reserved for Apple (19765 to 19769, 39765 and 39769, 40765 and up), Android
(28765 and 28769), realtime (26765 and 26769), related (27765) or presentation (25765).
