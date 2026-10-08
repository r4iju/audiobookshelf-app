# Private Apple release preparation, not accepted or installed

Runtime source `f9224289337a399d3d5c072b8eaf4b27bb0a533b`, tree `bdabc605c324680ce0ceec446cc53a2cedfd6f9d`. Test/CI/evidence descendant38 retains byte-identical Apple runtime. Ticket240 remains dependent on unresolved239 acceptance; no merge, owner replacement, public upload or invitation occurred.

Both projects were generated from an exact committed Git archive into `/tmp/native240-frozen.pxYeiD`, then clean Release device builds used existing valid development signing profiles and bounded jobs2. The combined phone profile covers the known phone and Pad; the TV profile covers the known TV. Stable bundle identities, explicit keychain contract and phone OAuth callback are retained. Audiobookshelf origins and inherited notices remain intact.

The independent parent verifier recomputed the exact Git tree/archive digest and all2074 archived source hashes. All46phone and36TV product files match their manifests, and both deep strict signature checks pass. Extracted signing certificate matches the embedded valid profile and local signing identity. Signed team/application identifiers, profile expiration, device coverage, callback and keychain identities verify. No failed seal was repaired or re-signed. Version1.0.0/build1 remains disclosed.

The SDK27 private phone build explicitly overrides original source minimum14 to binary15.0; both Info and Mach-O minimum15 verify. TV Info and Mach-O minimum17 verify. These signed builds cannot substitute for original-minimum hosted binary or older-runtime execution checks.

| Artifact | Exact private location |
| --- | --- |
| Phone/Pad candidate | `/tmp/native240-frozen.pxYeiD/phone-build/Build/Products/Release-iphoneos/AudiobookshelfNative.app` |
| TV candidate | `/tmp/native240-frozen.pxYeiD/tv-build/Build/Products/Release-appletvos/AudiobookshelfTV.app` |
| Independent verification | `/tmp/native240-frozen.pxYeiD/parent-candidate-verification.json` |
| Full source/build/product provenance | `/tmp/native240-preparation/PREACCEPTANCE-f9224289-RESULT.md` and candidate directory manifests/logs |

Archive SHA256: `17f9415b1d2eb9b74433e2baf63a9c0a69b9a7553b91cf14c65b31ef96a29159`.

Clean baseline77 rollback products are independently verified in `/tmp/native240-frozen.9xMX03`; they are separate historical artifacts, not redesigned candidates. Distinct synthetic QA identities and profiles isolate prior physical tests from stable owner apps. No owner container was copied, reset or uninstalled. Preparation does not establish hardware playback, background behavior or spoken accessibility.

Required next work is acceptance239, independent review, merge, representative merged-source QA and matching private owner installation, preserving owner data. Public App Store/TestFlight distribution remains separately blocked on actual rights/terms clearance; store processing, private signing and silence provide no copyright permission. No Cast, license, Android, web or backend changes are part of this preparation.

## Sourcebc121113 private experiment

Fresh `/tmp/native240-frozen.AOinzS` candidates come from exact `bc1211135df900d4658d5d0b69de483b6044222f`, tree436bac061ff8331b8fb4a237c5478dd43ad6a360, archive9e9ce96cb050c514b00eb827468a51f440531fcf038fbbea67f131e232fbe7a0. Both clean Release builds pass. Parent independently verifies2117 archived source hashes, all46phone/36TV product hashes, strict signatures, valid certificate/profile/team/device coverage, stable callback/keychain/identity contracts and actual binary minima15phone(local override, source14)/17TV. `parent-candidate-verification.json` retains exact proof.

The TV Library navigation path is a new production experiment after actual older-navigation failures. The phone production source is unchanged, but earlier TV artifacts do not represent this source. Both candidates remain NOT ACCEPTED and NOT INSTALLED; actual navigation, accessibility, older-system, review and merged-source acceptance remain separate. No owner data, capture or public upload operation occurred.
