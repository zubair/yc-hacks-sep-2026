// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PostcardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PostcardCore", targets: ["PostcardCore"])],
    targets: [
        .target(name: "PostcardCore"),
        .testTarget(name: "PostcardCoreTests", dependencies: ["PostcardCore"])
    ]
)
