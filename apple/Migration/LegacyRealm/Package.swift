// swift-tools-version:5.9
import PackageDescription

// Reads the legacy app's Realm (RealmSwift 10.54.6, schema 21). Run ../scripts/prepare-realm-core.sh
// once before building: it supplies the prebuilt realm-core the legacy CocoaPods build uses.
let package = Package(
    name: "LegacyRealm",
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [.library(name: "LegacyRealmExport", targets: ["LegacyRealmExport"])],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/realm/realm-swift.git", exact: "10.54.6"),
    ],
    targets: [
        .target(name: "LegacyRealmExport", dependencies: [
            .product(name: "LegacyMigration", package: "Migration"),
            .product(name: "RealmSwift", package: "realm-swift"),
        ]),
        .testTarget(name: "LegacyRealmExportTests", dependencies: ["LegacyRealmExport"]),
        .testTarget(name: "LegacyAppCompatibilityTests", dependencies: ["LegacyRealmExport", .product(name: "RealmSwift", package: "realm-swift")]),
    ]
)
