// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClientJourney",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "client-journey", targets: ["ClientJourney"])],
    dependencies: [.package(path: "../../tvos/Core")],
    targets: [.executableTarget(name: "ClientJourney", dependencies: [.product(name: "TVCore", package: "Core")])]
)
