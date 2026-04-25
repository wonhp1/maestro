// swift-tools-version: 6.0
// Maestro — AI 코딩 에이전트 공용 지휘소
// 참조: docs/plans/PLAN_maestro.md (Phase 1)

import PackageDescription

let package = Package(
    name: "Maestro",
    defaultLocalization: "ko",
    platforms: [
        // SEE ALSO: Sources/MaestroCore/MaestroConfig.swift#minimumMacOSVersion.
        // AppLaunchTests.testMacOSVersionInvariantMatchesPackageDeclaration 가 드리프트 감지.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Maestro", targets: ["Maestro"]),
        .library(name: "MaestroCore", targets: ["MaestroCore"]),
        .library(name: "MaestroAdapters", targets: ["MaestroAdapters"]),
    ],
    dependencies: [
        // Phase 1 기준 외부 의존성 없음 — Swift 표준 라이브러리만 사용.
        // 후속 Phase에서 swift-log, swift-argument-parser, SwiftTerm, Sparkle 추가 예정.
    ],
    targets: [
        .executableTarget(
            name: "Maestro",
            dependencies: ["MaestroCore", "MaestroAdapters"],
            path: "Sources/Maestro",
            swiftSettings: [
                .swiftLanguageMode(.v6),  // Strict Concurrency 활성
            ]
        ),
        .target(
            name: "MaestroCore",
            dependencies: [],
            path: "Sources/MaestroCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "MaestroAdapters",
            dependencies: ["MaestroCore"],
            path: "Sources/MaestroAdapters",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MaestroCoreTests",
            dependencies: ["MaestroCore"],
            path: "Tests/MaestroCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MaestroAdaptersTests",
            dependencies: ["MaestroCore", "MaestroAdapters"],
            path: "Tests/MaestroAdaptersTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
