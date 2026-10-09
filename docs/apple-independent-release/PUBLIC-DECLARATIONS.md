# Public Apple declarations and remaining access

The independent Apple licensing criterion in issue #177 is resolved through actual native-code/resource separation, not a copyright exception granted by silence or by Apple. The release issue remains open. The Cast request remains unresolved, and inherited Android/history are not relicensed.

## Privacy declaration prepared for App Store Connect

The native clients and permissive bundled reader code have no advertising, tracking, analytics or automatic crash-report upload SDK. No developer-operated server receives library credentials or listening history. Connections go to the server/authentication provider the user chooses. The developer and integrated SDK vendors collect no automatic app data. The proposed privacy-label answer is Data Not Collected under Apple's developer/third-party-partner definition, with user-directed server traffic, optional diagnostic sharing and RSS publication disclosed in the separate policy. This is a prepared assessment, not a questionnaire saved by the API.

Policy: https://r4iju.github.io/audiobookshelf-app/apple-privacy.html . Exact published bytes were verified. The URL and TV policy text are saved in App Store Connect. The documented official API has no privacy-questionnaire endpoint; the shared browser redirects to login with authResult=FAILED. Account sign-in is needed to save the declaration. No credentials are requested in chat.

## Age rating and review access

The age questionnaire is still unanswered. The app supplies no catalog content; user-controlled libraries can include mature books. Do not answer all content-frequency questions from synthetic fixtures or assume the server's explicit-content filter is parental control. Complete the questionnaire against the actual supported content/access model before submission; an older source minimum or an internal TestFlight approval does not complete this.

Reviewer access needs an isolated, globally reachable synthetic server with licensed original test media and dedicated review credentials. The owner LAN address and private owner credentials must not be supplied. Current local QA fixtures are not globally reachable. No public review deployment is claimed.

## Store screenshots and acceptance

Existing phone and iPad native captures have limited source and dimension coverage; Android screenshots must not be used for Apple. No new captures were taken under the user's stop-screenshot instruction. This does not waive genuine current phone/tablet/TV store screenshots. The strict contrast failure, complete spoken accessibility and original-minimum execution requirements remain open in #239/#240 and PR #241. No public submission is authorized to be described as verified while those checks are unresolved.

The signed build-3 candidate is independently reviewed and prepared for Apple processing. Uploading an eligible candidate does not publish it, close full release acceptance, or imply App Review approval.
