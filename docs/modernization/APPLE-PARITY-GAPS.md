# Apple parity gaps before cutover

Reconciled on October 2, 2026, against `8c1e94a5`, the Apple docs in this directory, `apple/README.md`, `tvos/QA.md` and the local logs they cite. The evidence is recorded per row in `verification/parity.json`. Nearly all of it comes from simulators, unit tests or a signed local install against synthetic fixtures. No row has hardware or live-server acceptance, and no row is claimed complete.

This does not include results from work still running at reconciliation: the progress-reset durability worker and the UI QA worker. Root's item-actions iPad run finished 4/4 (`/tmp/abs-root-item-actions-ipad.log`, committed as `315183c1`) and is recorded.

## Code or automation root still needs

1. **Interruptions and route changes (story-34).** These are implemented according to `apple/README.md`, but neither iPhone/iPad nor TV has a test or recorded observation.
2. **TV diagnostics, accessibility and localization (story-52, 53, 54).** Nothing is recorded for the TV. Implement them where applicable, or record why they don't apply.
3. **Migration, in-place route (story-58).** Not built yet:
   - a compatible-identity build (legacy bundle ID, team and Keychain group)
   - reading a Realm written by an actual legacy 0.14.2-beta build
   - reader settings from WebView localStorage
   Owner/private data has not been tested on either route.
4. **Collections and playlists (story-22).** Still missing:
   - permission denial
   - partial membership failure and retry
   - unavailable or deleted members
   - collection editing
   - podcast playlist membership editing

   `CollectionJourney.testCreateReorderRemoveAndDeletePlaylistThroughRelaunch` failed in 3 of 4 runs on the pre-correction realtime wiring, and no cause was found. Rerun it on the integrated app.
5. **Token renewal during playback (story-12) and server-side revocation (story-14).** Only contract tests cover these. The fixture has no mode that revokes a token mid-session.
6. **Downloads (story-42, 43).** Untested:
   - background transfer interruption
   - device restart
   - insufficient storage
   - actual cellular transitions
7. **Localization (story-54).** Each language is 18–27% translated. Playback and network alerts stay English.
8. **Accessibility (story-53).** Untested:
   - VoiceOver walkthroughs
   - contrast
   - a reduced-motion check
9. **Realtime (`upstream-realtime`).**
   - iPad has not been rerun on the corrected wiring.
   - Behaviour with queued unsent progress during a reconnection is unproven.
   - The item page does not follow `rss_feed_open`/`rss_feed_closed` events.
   - Server 2.30 has no replay, so changes made before the first `init` or while suspended are missed.
10. **Integrated rerun.** Most journeys passed on the slice that introduced them. Before cutover, run the full iPhone and iPad journey suite once on the final integration commit. Presentation journeys have never run on iPad.
11. **iOS 14 runtime.** Only typechecking has been done, because Xcode 27 needs a build-only iOS 15 override. An older runtime or SDK must run the app before the supported audience is confirmed.

## Physical and live-server gates (none performed)

- **iPhone and iPad:**
  - lock screen, headset and Bluetooth controls
  - background playback and background sleep timer
  - audio interruptions
  - real codecs
  - offline listening in airplane mode
  - PDF on a device
  - cross-device progress
  - realtime with a second client
  - year image sharing and Save Image
  - haptic vibration
- **Live server, with owner approval:**
  - OpenID provider
  - opening and closing an RSS feed
  - sending an ebook through SMTP
  - large libraries
  - authors with more than 60 titles
- **Migration on devices:**
  - legacy export saved through Files and imported
  - adopted audio playing offline
  - PDF reopening on the same page
  - pending sessions accepted by the server
  - rollback to the legacy app
- **Apple TV:** the ten checks in `tvos/QA.md`, including remote sign-in, readability, playback, system controls, durability and login expiry.

## Deferred, not gating Apple readiness

- Remaining EPUB acceptance, including hardware volume navigation, and the MOBI, AZW3, CBZ and CBR readers are deferred until after Phase 2 (#65, `scopeAmendments`).
- Migration must keep their files and locations.
- Auto-sleep window, shake reset, chime and the local folder workflow are Android-only in the baseline.
