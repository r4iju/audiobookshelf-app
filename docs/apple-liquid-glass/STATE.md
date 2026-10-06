# Apple Liquid Glass integration state

The application presentation source is `1064bd6cf34e21f8edd1bda0ab0b4f22303ba32b` on `feature/apple-liquid-glass`. The integration is Apple-only. Android, browser and backend runtime are unchanged.

| Ticket | Integrated commit | Evidence |
| --- | --- | --- |
| #223 sign-in and glass foundation | `be12703ee1e78670e1cd942581dfb8211d0cc9a1` | [Verification](evidence/223/verification.md) |
| #224 adaptive catalog | `c283e5fcc4e683ba018e33f770939c32cc4784cc` | [Verification](evidence/224/verification.md) |
| #225 listening controls | `a67b33be6967a5bae187d52b685fce4bb148ca02` | [Verification](evidence/225/verification.md) |
| #226 reading and utilities | `c71029352e6464f470f98f5de03d5d1b524c30a0` | [Verification](evidence/226/verification.md) |
| #227 Apple TV | `1064bd6cf34e21f8edd1bda0ab0b4f22303ba32b` | [Verification](evidence/227/verification.md) |
| #228 verification harness fixes | `b28fddedc9c0c2105fbc2c106454a347aa05b603` | [Integration checks and candidates](evidence/228/verification.md), [exact results](evidence/228/checks.tsv) |

Existing selected automated checks passed without accepted skips after correcting stale harness assumptions. Final verification evidence is in the commit that adds this state file. No new tests or application/domain runtime changes were added by #228. Final independent review, integration PR merge and tracker completion are owned by the integration coordinator and must be recorded after they happen.

Both private unsigned Release archives were built from the exact application source above, using Xcode 27. iOS source minimum remains 14; the installed SDK requires a build-only 15 override, so this candidate's actual minimum is 15. tvOS candidate minimum is 17. Archive hashes and commands are in [the candidate evidence](evidence/228/verification.md). No Apple binary was uploaded or published.

Acceptance limits remain explicit: actual 375-point compact iPad window rendering was inspected, but its offset confused both available AX/input tooling and the attempted XCTest launch, so compact-window action/retained-detail/player acceptance remains unverified. Full-width iPad, large text, localization and iPhone fallback actions passed. Physical device background/remote/headset/haptics, physical Apple TV glass capability/rendering, actual VoiceOver speech and physical traversal, and older supported OS execution are not established by simulator evidence. Public Apple distribution is still gated by actual rights/terms approval; source integration and private candidate builds do not satisfy that gate.

## Independent integration review

Fresh standards and spec reviewers examined `f1ed5915...1064bd6c`. Neither found a confirmed implementation defect or scope violation. Their search-size and accessibility-fallback concerns were verified through the final passing interactions. The suspected download-row coactivation did not reproduce under Reduce Transparency, so no speculative runtime fix was applied.

The verification-only delta through `b28fdded` was independently reviewed without assertion weakening or restored legacy runtime code. The final evidence delta through `e576f010` was reviewed against the spec; counts and private archive hashes reconcile. Actual compact/wide inspection satisfies the written layout inspection requirement. Compact-window actions remain a residual verification gap, not a demonstrated regression or a claim of complete compact behavioral acceptance.

Integration PR: [#229](https://github.com/r4iju/audiobookshelf-app/pull/229). Its merge and post-merge smoke results will be recorded on the PR.
