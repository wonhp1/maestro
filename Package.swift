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
        // Phase 26 — Sparkle 자동 업데이트.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        // v0.5.1 — SwiftUI Markdown 렌더 (헤더/리스트/코드/표/인용 모두 지원).
        // 자체 MarkdownRenderer 가 plain Text 한계로 가독성 떨어졌던 문제 해결.
        .package(
            url: "https://github.com/gonzalezreal/swift-markdown-ui.git",
            from: "2.4.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Maestro",
            dependencies: [
                "MaestroCore",
                "MaestroAdapters",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
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
