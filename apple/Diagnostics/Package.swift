// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NativeDiagnostics",
    platforms: [.iOS(.v14), .macOS(.v11)],
    products: [.library(name: "NativeDiagnostics", targets: ["NativeDiagnostics"])],
    targets: [
        .target(name: "NativeDiagnostics"),
        .testTarget(name: "NativeDiagnosticsTests", dependencies: ["NativeDiagnostics"])
    ]
)
