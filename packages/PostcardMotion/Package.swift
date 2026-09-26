// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PostcardMotion",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PostcardMotion", targets: ["PostcardMotion"])],
    targets: [.target(name: "PostcardMotion")]
)
