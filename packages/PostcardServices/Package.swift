// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PostcardServices",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PostcardServices", targets: ["PostcardServices"])],
    dependencies: [
        .package(path: "../PostcardCore"),
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.2")
    ],
    targets: [
        .target(name: "PostcardServices", dependencies: ["PostcardCore", .product(name: "Supabase", package: "supabase-swift")]),
        .testTarget(name: "PostcardServicesTests", dependencies: ["PostcardServices"])
    ]
)
