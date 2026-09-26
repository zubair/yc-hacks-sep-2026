// swift-tools-version: 6.0
import PackageDescription

// The measuring logic on its own, so `swift test` runs on any Mac or Linux box with no
// Xcode 27.1 or iPhone Duo. The app target compiles the same files from FoldGonio/Core.
let package = Package(
    name: "GonioCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GonioCore", targets: ["GonioCore"]),
    ],
    targets: [
        .target(name: "GonioCore", path: "FoldGonio/Core"),
        .testTarget(name: "GonioCoreTests", dependencies: ["GonioCore"], path: "Tests/GonioCoreTests"),
    ]
)
