// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TVCore",
    platforms: [.macOS(.v13), .tvOS(.v17)],
    products: [.library(name: "TVCore", targets: ["TVCore"])],
    targets: [
        .target(name: "TVCore"),
        .testTarget(name: "TVCoreTests", dependencies: ["TVCore"])
    ]
)
