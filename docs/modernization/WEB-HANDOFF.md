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
| (this commit) | Records the full local run on `5710199f` |

## Checks

Run from `web/` on the Studio, against the isolated QA server only:

```sh
npm run lint && npm run typecheck && npm test && npx playwright test
```

Last full run, on `5710199f` (Studio, Chromium; the commit after it changes only this file). The chain was
`npm run lint && npm run typecheck && npm test && npm run build && npm run qa:deploy -- up && npx playwright test`:

- Biome clean (1 info: the `recommended` field in `biome.json` is deprecated);
- `tsc` clean;
- vitest: 84 passed in 17 files;
- production build and deployment image built;
- Playwright: 60 passed and 1 failed in 4.4 minutes, including the 7 deployment journeys against the image built
  from that commit. The failure was the e-reader journey: the QA server took 68 seconds to hand the mail to the
  loopback SMTP sink (its log shows 20:36:50 to 20:37:58), the fixture stall described below. Run alone right after,
  on the same commit, it passed.

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
  background audio and autoplay rules on phones, are unchecked.
- **The owner's server and network.** No deployment beside the owner's server, behind the owner's HTTPS proxy and
  host name. That deployment is the root coordinator's call, following DEPLOYMENT.md.
- **A real identity provider.** Only the loopback provider was used. A real provider adds consent screens, its own
  key rotation and logout.
- **Real e-reader delivery.** This needs the owner's SMTP settings and a device.
- **Physical listening.** Audible output, Bluetooth and lock-screen controls, long sessions and sleep.
- **Release acceptance** (#55 and the parent issue). Compatibility, preservation and the owner's acceptance remain
  required before this client replaces anything. The legacy interface stays served by the server at `/`.

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
- **Podcast fixtures.** The QA server reaches the loopback feed as `host.docker.internal`, which its SSRF filter
  allows through `SSRF_REQUEST_FILTER_WHITELIST`.
- **Latest episodes** lists the newest unfinished episodes across podcasts, from the server's `recent-episodes`
  endpoint.
- **Audio coexistence.** The reader keeps the player playing underneath; a second tab is a second player.
- **RSS feeds** follow the legacy item menu. Administrators open and close them; anyone sees an open feed's address.
  Opening needs an item with audio. The legacy slug cleaning is applied before opening, and the address shown is
  exactly the one used.
- **Discarding progress** is a recorded intent that ends only when the server confirms the delete. For the
  account the discard came from only:
  1. a hold is stored for the book or episode, naming the progress row to delete. While it exists, no tab delivers
     that account's listening for it. Each hold has its own stored entry, so tabs discarding at once never
     overwrite each other's;
  2. this device drops its unsent listening for it, and the player (if it holds that book for that account) goes
     back to the start, paused. A session still being opened for it is let go when it arrives. Playing it again
     while the hold exists starts from the beginning, not from the server's old place;
  3. the old playback session is closed without a final report;
  4. the book is blocked in IndexedDB, and listening for it that any tab of the account recorded as sent must be
     answered (see below);
  5. the server's progress row is deleted;
  6. once the delete is confirmed, the block and the hold end, and listening recorded since step 2 is delivered as
     new progress. The block is marked finished, so a tab waking late neither blocks the book nor deletes again.

  Every tab records the exact reports it is about to send in IndexedDB, checking the blocked books in the same
  transaction, then sends those reports, leaving out any no longer queued or now held. IndexedDB orders these
  transactions across tabs with or without Web Locks, so plain-HTTP origins are covered: a delivery recorded before
  the block counts against the discard, and one recorded after it leaves the book out. A record ends only with the
  server's answer to that request. A request that failed without an answer stays recorded (one entry per report),
  since it may still reach the server, or still be running there.

  2.30.0 shows nothing that says a given request is done. `local-all` requests for one session run independently,
  and one that finds no progress row creates one, so neither a copy of the report sent again nor the server holding
  that listening (any tab may send the same queued report) proves the original cannot land after the delete. So:

  - if the only deliveries on their way are this tab's own, the discard waits for their answers and finishes;
  - otherwise it is left **unconfirmed**. The item page says "Discarding progress. Listening for this that another
    tab sent is not confirmed by the server, and could bring the old position back after the discard. It finishes
    by itself once confirmed." and offers **Keep progress** (nothing is deleted, and the held listening is
    delivered) and **Discard anyway** (the delete is sent; the old place can come back only if that listening still
    lands, and discarding again then removes it). Any tab of the account finishes the discard by itself once the
    other tab's answers are in. Nothing is decided from time passing.

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
    until the user chooses.
  - Keep progress pressed in the moment a waiting discard sends its delete cannot stop that delete.
  - A browser that refuses IndexedDB delivers no listening at all; each delivery fails as an outage would, and
    nothing is sent unrecorded.

  Other books and other accounts stay playable and keep delivering throughout. A storage refusal in steps 1 or 2
  fails the discard before anything is sent, so the server's progress is unchanged. A refusal part-way through
  step 2 can leave this device partly reset (the unsent listening dropped but the saved player place not yet
  written); discarding again once storage accepts writes finishes it.

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
