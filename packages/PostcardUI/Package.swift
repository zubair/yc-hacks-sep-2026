// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PostcardUI",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PostcardUI", targets: ["PostcardUI"])],
    dependencies: [.package(path: "../PostcardCore"), .package(path: "../PostcardMotion")],
    targets: [
        .target(name: "PostcardUI", dependencies: ["PostcardCore", "PostcardMotion"], resources: [.process("Resources")]),
        .testTarget(name: "PostcardUITests", dependencies: ["PostcardUI"])
    ]
)
