// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "fika",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // 순수 시간 계산 로직(테스트 대상). 앱 코드가 의존한다.
        .target(
            name: "FikaCore",
            path: "Sources/FikaCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "fika",
            dependencies: ["FikaCore"],
            path: "Sources/fika",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        // XCTest는 Command Line Tools 환경에 없으므로(이 저장소 방침), 의존성 없는
        // 실행 파일로 테스트한다: `swift run FikaTests` (실패 시 종료코드 1).
        .executableTarget(
            name: "FikaTests",
            dependencies: ["FikaCore"],
            path: "Tests/FikaTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
