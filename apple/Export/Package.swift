// swift-tools-version: 5.9
import PackageDescription

// Standalone harness for renderer checks. The app target compiles Sources/YearExport directly.
let package = Package(
    name: "YearExport",
    platforms: [.iOS(.v14)],
    products: [.library(name: "YearExport", targets: ["YearExport"])],
    dependencies: [.package(name: "TVCore", path: "../../tvos/Core")],
    targets: [
        .target(name: "YearExport", dependencies: [.product(name: "TVCore", package: "TVCore")]),
        .testTarget(name: "YearExportTests", dependencies: ["YearExport"])
    ]
)
