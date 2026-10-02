import XCTest
import UIKit

/// Journeys for the remaining mobile acceptance gaps, against the synthetic fixture owned by
/// `apple/scripts/verify-remaining-qa.sh` on 57765/57769. Skipped unless that script runs them.
@MainActor class RemainingQAJourney: NativeJourney {
    nonisolated static let server = "http://127.0.0.1:57765/abs"

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ABS_REMAINING_QA"] == "1", "Run through apple/scripts/verify-remaining-qa.sh")
        continueAfterFailure = false
        try await configure("baseline")
    }

    func configure(_ mode: String) async throws {
        var request = URLRequest(url: URL(string: Self.server + "/__fixture__/configure")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["mode": mode])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func observedRequests() async throws -> [ObservedRequest] {
        let (data, response) = try await URLSession.shared.data(from: URL(string: Self.server + "/__fixture__/observations")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode(Observations.self, from: data).requests
    }

    func signIn(arguments: [String] = []) {
        connectSelectAndRestore(serverURL: Self.server, verifyRestoration: false, arguments: arguments)
    }

    func openAccountMenu(_ item: String) {
        let app = XCUIApplication()
        app.buttons["account"].tap()
        XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 5), item)
        app.buttons[item].tap()
    }
}

/// Story 53: automated contrast audit of the main mobile screens in each saved appearance.
@MainActor final class RemainingQAAccessibilityJourney: RemainingQAJourney {
    private struct Finding: CustomStringConvertible {
        let screen: String
        let detail: String
        var description: String { "[\(screen)] \(detail)" }
    }
    private var findings: [Finding] = []

    func testContrastAuditLightAppearance() async throws { try await auditScreens(appearance: "light") }
    func testContrastAuditDarkAppearance() async throws { try await auditScreens(appearance: "dark") }
    func testContrastAuditBlackAppearance() async throws { try await auditScreens(appearance: "black") }

    /// Every contrast issue the audit raises stays a failure unless the screenshot taken just before the audit shows the
    /// element's text at 4.5:1 or more (the WCAG 1.4.3 threshold for normal text), or the element is disabled (WCAG 1.4.3
    /// exempts inactive controls). Each dismissal is printed with its measurement so it can be reviewed.
    private func audit(_ screen: String, appearance: String) throws {
        let app = XCUIApplication()
        let shot = XCUIScreen.main.screenshot()
        let evidence = XCTAttachment(screenshot: shot)
        evidence.name = "\(appearance)-\(screen)"
        evidence.lifetime = .keepAlways
        add(evidence)
        let image = try XCTUnwrap(UIImage(data: shot.pngRepresentation)?.cgImage)
        let scale = Double(image.width) / Double(app.frame.width)
        guard #available(iOS 17, *) else { throw XCTSkip("The accessibility audit needs iOS 17") }
        try app.performAccessibilityAudit(for: .contrast) { issue in
            let place = "\(appearance) \(screen)"
            guard let element = issue.element else {
                self.record(place, "\(issue.compactDescription) with no element"); return true
            }
            let described = "id='\(element.identifier)' label='\(element.label)' frame=\(element.frame)"
            if !element.isEnabled {
                print("AUDIT-DISMISSED [\(place)] disabled control \(described)"); return true
            }
            let measured = ContrastMeasurement(image: image, scale: scale, frame: element.frame)
            if let measured, measured.ratio >= 4.5 {
                print("AUDIT-DISMISSED [\(place)] measured \(measured) \(described): \(issue.compactDescription)"); return true
            }
            self.record(place, "\(issue.compactDescription) measured \(measured.map(String.init(describing:)) ?? "unmeasurable") \(described)")
            return true
        }
    }

    private func record(_ place: String, _ detail: String) {
        let finding = Finding(screen: place, detail: detail)
        print("AUDIT-FINDING \(finding)")
        findings.append(finding)
    }

    private func auditScreens(appearance: String) async throws {
        try await configure("pdf-reader")
        signIn(arguments: ["-previewTheme", appearance])
        let app = XCUIApplication()
        try audit("catalog", appearance: appearance)

        app.buttons["book-book-0"].tap()
        XCTAssertTrue(app.buttons["play-book"].waitForExistence(timeout: 10))
        try audit("details", appearance: appearance)

        app.buttons["Read PDF"].tap()
        XCTAssertTrue(app.staticTexts["Page 1 of 4"].waitForExistence(timeout: 10))
        try audit("pdf-reader", appearance: appearance)
        app.buttons["Close reader"].tap()

        app.buttons["play-book"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 10))
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["pause-playback"].waitForExistence(timeout: 10))
        try audit("player", appearance: appearance)
        // The synthetic book is 20 seconds long and may finish while the audit runs.
        if app.buttons["pause-playback"].exists { app.buttons["pause-playback"].tap() }
        app.buttons["Close playback"].tap()
        app.navigationBars.buttons["BackButton"].tap()

        openAccountMenu("Downloads")
        try audit("downloads", appearance: appearance)
        app.navigationBars.buttons["Done"].tap()

        openAccountMenu("Collections")
        XCTAssertTrue(app.buttons["group-collection-evening"].waitForExistence(timeout: 10))
        try audit("collections", appearance: appearance)
        app.buttons["group-collection-evening"].tap()
        XCTAssertTrue(app.buttons["Play collection"].waitForExistence(timeout: 10))
        try audit("collection-detail", appearance: appearance)

        app.terminate()
        app.launchArguments = ["-previewTheme", appearance]
        app.launch()
        XCTAssertTrue(app.staticTexts["Audiobooks"].firstMatch.waitForExistence(timeout: 10))
        openAccountMenu("Settings")
        try audit("settings", appearance: appearance)

        XCTAssertTrue(findings.isEmpty, "\(findings.count) contrast findings:\n" + findings.map(\.description).joined(separator: "\n"))
    }
}

/// Text contrast inside one element of a screenshot: the most common colour is the background, the text colour is taken at
/// the 90th percentile of contrast among the other pixels, so anti-aliased edges and stray pixels do not decide it. The
/// same method as apple/scripts/measure-contrast.swift.
struct ContrastMeasurement: CustomStringConvertible {
    let background: (Int, Int, Int)
    let foreground: (Int, Int, Int)
    let ratio: Double
    var description: String {
        String(format: "%.2f:1 (#%02X%02X%02X on #%02X%02X%02X)", ratio, foreground.0, foreground.1, foreground.2, background.0, background.1, background.2)
    }

    init?(image: CGImage, scale: Double, frame: CGRect) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let left = max(0, Int(frame.minX * scale)), right = min(width, Int(frame.maxX * scale))
        let top = max(0, Int(frame.minY * scale)), bottom = min(height, Int(frame.maxY * scale))
        guard left < right, top < bottom else { return nil }
        var counts: [Int: Int] = [:]
        var samples: [Int] = []
        for row in top..<bottom {
            for column in left..<right {
                let offset = (row * width + column) * 4
                let color = Int(pixels[offset]) << 16 | Int(pixels[offset + 1]) << 8 | Int(pixels[offset + 2])
                counts[color, default: 0] += 1
                samples.append(color)
            }
        }
        guard let background = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        var ratios: [Int: Double] = [:]
        for color in counts.keys { ratios[color] = Self.ratio(color, background) }
        let opposite = samples.filter { ratios[$0]! > 1.15 }.sorted { ratios[$0]! < ratios[$1]! }
        guard !opposite.isEmpty else { return nil }
        let foreground = opposite[min(opposite.count - 1, Int(Double(opposite.count) * 0.9))]
        self.background = (background >> 16, background >> 8 & 0xFF, background & 0xFF)
        self.foreground = (foreground >> 16, foreground >> 8 & 0xFF, foreground & 0xFF)
        ratio = Self.ratio(foreground, background)
    }

    static func luminance(_ color: Int) -> Double {
        func channel(_ value: Int) -> Double { let s = Double(value) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(color >> 16) + 0.7152 * channel(color >> 8 & 0xFF) + 0.0722 * channel(color & 0xFF)
    }
    static func ratio(_ a: Int, _ b: Int) -> Double {
        let (first, second) = (luminance(a), luminance(b))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
