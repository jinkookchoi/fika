// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "fika",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "fika",
            path: "Sources/fika",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
