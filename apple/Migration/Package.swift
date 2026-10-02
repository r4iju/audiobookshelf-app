// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LegacyMigration",
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [.library(name: "LegacyMigration", targets: ["LegacyMigration"])],
    targets: [
        .target(name: "LegacyMigration"),
        .testTarget(name: "LegacyMigrationTests", dependencies: ["LegacyMigration"]),
    ]
)
