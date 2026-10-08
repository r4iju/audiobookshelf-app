# Public automatic screen capture controls, read-only evidence

No test, UI replay, new screenshot/video, attachment export or shared source edit occurred. Future execution remains on hold pending the root's effective configured seam review. The observed framework recording/process violation remains preserved; no after-the-fact deletion or unexported-attachment claim makes that run compliant.

Apple primary Xcode15 release notes say XCTest adds automatic recordings, enables them by default in favor of screenshots, and allows disabling through a test plan or scheme Test action options. This support predates actual selected Xcode16.2, so it is not an SDK27-only assumption:

https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes

Downloaded DocC JSON: /tmp/native-older-ci-preparation/apple-xcode15-release-notes.json. Section Testing / New Features, paragraph issue35129014. The nearby issue109908952 discusses choosing screenshots instead of recordings; switching the preferred format alone does NOT disable screen capture.

Apple primary current test-plan documentation defines two distinct controls: Automatic Screen Capture controls capture while tests run as well as deletion for passing tests; Preferred Capture Format chooses video versus screenshots:

https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback

Downloaded JSON: /tmp/native-older-ci-preparation/apple-organizing-tests.json, configuration option definition-list terms Automatic Screen Capture and Preferred Capture Format. Apple public prose documents the options but does not expose the exact serialized JSON key or explicitly explain whether the internal keepNever representation skips creation versus drops storage. No supported disableAutomaticScreenshots/disableAutomaticScreenRecording testplan JSON key was established; do not invent one.

Actual retained runner evidence /tmp/native239-5c4-tv17/extracted/xcodegen.log reports XcodeGen2.46.0. Its pinned official public spec advertises captureScreenshotsAutomatically as the capture-on/off boolean and says the delete-on-success setting is ignored when false. It separately documents preferredScreenCaptureFormat screenshots/screenRecording:

https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md#test-action

Downloaded /tmp/native-older-ci-preparation/xcodegen-2.46.0-project-spec.md lines1078–1081. Exact source mapping:

https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Sources/XcodeGenKit/SchemeGenerator.swift

Downloaded xcodegen-2.46.0-scheme-generator.swift lines564–574: false capture option maps to systemAttachmentLifetime keepNever, independent of deleteScreenshotsWhenEachTestSucceeds. It is an advertised capture-disabled option, not a command to delete result bundles after testing. However the field name is a retention lifetime; this source mapping alone cannot independently prove that no image is instantiated internally.

Its exact dependency XcodeProj9.14.0 is pinned by Package.swift and serializes systemAttachmentLifetime and preferredScreenCaptureFormat into public XCScheme TestAction XML:

https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Package.swift
https://github.com/tuist/XcodeProj/blob/9.14.0/Sources/XcodeProj/Scheme/XCScheme%2BTestAction.swift

Downloaded xcodegen-2.46.0-package.swift line19 and xcodeproj-9.14.0-testaction.swift lines188–193.

Reviewable public scheme-generation route, for the sole writer to apply to every relevant test scheme without changing any assertion:

    test:
      captureScreenshotsAutomatically: false
      preferredScreenCaptureFormat: screenshots

Expected generated public XML attributes:

    <TestAction systemAttachmentLifetime="keepNever"
                preferredScreenCaptureFormat="screenshots" ...>

No deleteScreenshotsWhenEachTestSucceeds workaround is required or offered. Normal test targets/cases remain unchanged. Parent should verify those generated scheme attributes, actual selected scheme/no testplan override, and effective build-for-testing configuration without UI execution before deciding that the advertised capture-off contract satisfies the user's stop instruction. Merely observing absent retained recordings on a green test would not demonstrate disabled failure capture. No passing or failing runtime probe to check capture was run here.

Actual artifact xcodebuild-help.log line94 DOES include collect-test-diagnostics on-failure|never and describes verbose failure diagnostics such as sysdiagnose. Current tvos/scripts/verify-ui.sh line81 retains never. There is no harness-diagnostics.txt evidence of removing the flag for this run. It did not disable the framework recording; the earlier removed-flag inference is withdrawn.

Thirteenth helper is control preparation only. Root must decide/apply/verify this public supported configuration seam before any next old-runtime UI replay. If stronger proof of prevention rather than retention is required beyond these documented capture-off semantics, that exact guarantee remains unestablished by read-only metadata here; do not claim otherwise.

Root followthrough: Apple explicitly distinguishes whether the runner captures from deletion/format. Root accepts the documented public capture-off contract, without claiming proof of every internal allocation. All3 source schemes now captureScreenshotsAutomatically:false, all3 freshly generated XML systemAttachmentLifetime=keepNever, same targets/no TestPlans. Effective build-only proof is in progress; no UI replay is based on mere absent retained attachments. A pre-UI scheme guard is being added.
