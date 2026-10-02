# Apple save-again download recovery (#15)

## Focused acceptance (2026-10-03)

When an existing download failed or was cancelled, choosing Save again changed its transfer
generation but retained its failed/cancelled state. The queue only starts queued entries, so
that user action never recovered the unfinished files. Save again now queues the entry and
clears its previous error. Completed parts remain retained.

The new `DownloadRecoveryTests.testSavingFailedDownloadAgainRestoresPDFWithoutDownloadingFinishedAudio`
was written first. On source `9c8cfca1`, its focused RED run failed: state stayed failed,
the HTTP 503 message persisted, PDF requests stayed at one, and the PDF was unavailable
before and after store relaunch. The fix then passed all four DownloadRecoveryTests.
The new scenario verifies actual saved audio/PDF bytes, one audio request, two PDF requests,
and ready state plus available files after relaunch.

This is synthetic native-store acceptance on leased Pool iPhone 1 (iOS 27.0), UDID
`75FA9768-B15C-40B6-ACC7-790D7FCAD29C`, using URLProtocol fixture responses.
It is not a UI journey, physical-device, background transfer, or real-server acceptance.
No signed packages or owner devices/server were changed. Existing packaged-server,
localization and physical-control evidence remains separate.

Reproduce after `sim acquire iphone` and `xcodegen generate --quiet --spec apple/project.yml`:

```sh
xcodebuild -project apple/AudiobookshelfNative.xcodeproj -scheme NativeTests \
  -destination "id=<leased-udid>" -derivedDataPath <owned-derived-data> \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual IPHONEOS_DEPLOYMENT_TARGET=15.0 \
  -resultBundlePath <new-results.xcresult> -collect-test-diagnostics never \
  -only-testing:NativeTests/DownloadRecoveryTests test
sim release <leased-udid>
```

Private local logs and result bundles are retained separately. Log SHA-256:

- RED: `b7b752b2c42a7446e4792d3ed5a9ac08be872f208d3c00a5a0238fd4bb83a374`.
- GREEN (4/4): `ca48ba649a577c9b60c552cae9ae477ac859fb12c04303571b4e8c6bdfe0c276`.
