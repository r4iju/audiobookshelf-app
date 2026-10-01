// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NativeLocalization",
    defaultLocalization: "en",
    platforms: [.iOS(.v14), .macOS(.v11)],
    products: [.library(name: "NativeLocalization", targets: ["NativeLocalization"])],
    targets: [
        .target(name: "NativeLocalization", resources: [.process("Resources")]),
        .testTarget(name: "NativeLocalizationTests", dependencies: ["NativeLocalization"])
    ]
)
