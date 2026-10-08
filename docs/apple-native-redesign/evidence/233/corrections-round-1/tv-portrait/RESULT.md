# Missing portrait-detail focus pair for checkpoint 233

Production source: `5acca8c1a39cdcf9525e67874583651eef9e6900`. Disposable source archive includes committed tvos/apple/verification directories, no shared source, test, docs, index or tracker changes. Only disposable `tvos/UITests/ShellJourney.swift` gained capture-only focus/capture steps after its existing archive-detail capture: focus Library, capture archive-detail-unfocused, focus play-item, capture archive-detail-focused. No assertions were removed or new behavior implemented.

Actual pooled device `9ACC6F5B-180D-44C3-823B-F8796813D69D`, Apple TV 4K third generation, tvOS27.0 (24J360), Xcode27.0. T3 device_list omitted TV and device_open explicitly reported no matching TV device. Interaction used the established native XCTest/XCUIRemote platform seam. App minimum remains tvOS17.0; this is execution on27 only. Newly rebuilt unchanged-runtime app binary hashes differ from the earlier artifact because the disposable build paths differ; build-record.json pins exact installed and build hashes and confirms equality. Capture manifest records timestamps and source/binary/raster hashes. Both PNGs are unprocessed actual2048x1152 XCTest rasters.

ShellJourney passed 1 test, 0 failures in55.359seconds. Existing twelve-library selection, Back focus and all-library Search assertions remain intact. Runtime emitted `_UIReplicantView`/UIHostingController hierarchy warning, attached as Complete Issue Description; this was not an XCTest failure. No broad acceptance or warning-free claim is made. Both images were opened with view_image: the unfocused primary Resume has orange text on a dark orange fill while Library holds native focus; focused Resume has bright orange fill with dark glyph/text. Full-fit portrait artwork remains the same in both.

Reproduction:
```sh
git archive 5acca8c1a39cdcf9525e67874583651eef9e6900 tvos apple verification | tar -x -C /tmp/native-tv-233-portrait-unfocused/source
# Insert the capture-only focus steps described above in the disposable ShellJourney.
ABS_QA_COVER_DIRECTORY=/tmp/232-covers \
ABS_TV_QA_SIMULATOR=9ACC6F5B-180D-44C3-823B-F8796813D69D \
ABS_TV_RESULT_BUNDLE=/tmp/native-tv-233-portrait-unfocused/capture.xcresult \
/tmp/native-tv-233-portrait-unfocused/source/tvos/scripts/verify-ui.sh CODE_SIGN_IDENTITY=- -only-testing:TVJourneyTests/ShellJourney
xcrun xcresulttool export attachments --path /tmp/native-tv-233-portrait-unfocused/capture.xcresult --output-path /tmp/native-tv-233-portrait-unfocused/attachments
```
Synthetic covers are existing generated `/tmp/232-covers/0.jpg` and `1.jpg`, reproducible with committed232 fixture-covers/generate.swift. Owned fixture processes stopped via verify-ui cleanup; final bind checks confirm no listener20765/20767. TV lease released. No owner data, signers, licenses, public upload or app distribution touched.

Curatable files: archive-detail-unfocused.png, archive-detail-focused.png, capture-manifest.json, build-record.json and this RESULT.md. Raw source/build/log/xcresult/attachment export remains only under /tmp.
