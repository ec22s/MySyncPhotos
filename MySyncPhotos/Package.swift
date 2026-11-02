// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MySyncPhotos",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "MySyncPhotos", targets: ["MySyncPhotos"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/aws-devtools-labs/aws-blocks-swift.git",
            .upToNextMinor(from: "0.1.0")
        ),
    ],
    targets: [
        .target(
            name: "MySyncPhotos",
            dependencies: [
                .product(name: "BlocksRuntime", package: "aws-blocks-swift"),
            ],
            path: "Sources/MySyncPhotos",
            // Swift 5 mode: generated API.swift uses BlocksServer which isn't
            // Sendable-annotated in BlocksRuntime 0.1.x.
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "MySyncPhotosTests",
            dependencies: ["MySyncPhotos"],
            path: "Tests/MySyncPhotosTests"
        ),
    ]
)
