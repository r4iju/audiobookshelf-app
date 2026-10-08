# Native Apple redesign task graph

Spec: [#230](https://github.com/r4iju/audiobookshelf-app/issues/230). Shared integration checkout, one writer at a time. Dependants start after verified commit integration. Parent spec remains unchanged.

| Ticket | Delivery | Blocked by |
| --- | --- | --- |
| [#231](https://github.com/r4iju/audiobookshelf-app/issues/231) | Apple native 01: Native phone and tablet design slice | None |
| [#232](https://github.com/r4iju/audiobookshelf-app/issues/232) | Apple native 02: Native TV design slice | #231 |
| [#233](https://github.com/r4iju/audiobookshelf-app/issues/233) | Apple native 03: Independent native design checkpoint | #231, #232 |
| [#234](https://github.com/r4iju/audiobookshelf-app/issues/234) | Apple native 04: Complete catalog and system search | #233 |
| [#235](https://github.com/r4iju/audiobookshelf-app/issues/235) | Apple native 05: Complete integrated listening experience | #234 |
| [#236](https://github.com/r4iju/audiobookshelf-app/issues/236) | Apple native 06: Complete readers, downloads and saved groups | #235 |
| [#237](https://github.com/r4iju/audiobookshelf-app/issues/237) | Apple native 07: Complete connection, settings and utilities | #236 |
| [#238](https://github.com/r4iju/audiobookshelf-app/issues/238) | Apple native 08: Complete TV presentation and remote journeys | #233 |
| [#239](https://github.com/r4iju/audiobookshelf-app/issues/239) | Apple native 09: Resolve adaptive and accessibility acceptance | #237, #238 |
| [#240](https://github.com/r4iju/audiobookshelf-app/issues/240) | Apple native 10: Verify, review, merge and install private Apple candidates | #239 |

Current integration:231–238 are implemented on the draft integration PR241. Ticket239 remains incomplete after final clean modernTV49/49, TV17 seven/seven and fresh mobileConnection1/1 pass; strict combined contrast, full spoken accessibility and original-minimum mobile execution are genuine remaining acceptance blockers. Ticket240 has fresh verified B64 private candidates but remains blocked by239 before acceptance/merge/owner installation/merged QA. Public Apple distribution additionally requires written rights clearance. No parent/spec ticket is closed or changed.
