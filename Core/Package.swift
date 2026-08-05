// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhiteoutCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "WhiteoutCore", targets: ["WhiteoutCore"])
    ],
    targets: [
        .target(
            name: "WhiteoutCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WhiteoutCoreTests",
            dependencies: ["WhiteoutCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
