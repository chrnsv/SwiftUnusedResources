// swift-tools-version:6.3

import PackageDescription
import Foundation

let skipSwiftLint = ProcessInfo.processInfo.environment["SKIP_SWIFTLINT"] != nil

let package = Package(
    name: "SUR",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "sur", targets: ["SUR"]),
        .plugin(name: "SURBuildToolPlugin", targets: ["SURBuildToolPlugin"]),
        .library(name: "SURCore", targets: ["SURCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.1"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "9.17.4"),
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", from: "0.65.1"),
    ],
    targets: [
        .executableTarget(
            name: "SUR",
            dependencies: [
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "Rainbow", package: "Rainbow"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "SURCore"),
            ],
            plugins: skipSwiftLint ? [] : [
                 .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .plugin(
            name: "SURBuildToolPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "SURBinary"),
            ]
        ),
        .target(
            name: "SURCore",
            dependencies:[
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "XcodeProj", package: "XcodeProj"),
                .product(name: "Rainbow", package: "Rainbow"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
                .product(name: "Yams", package: "Yams"),
            ],
            plugins: skipSwiftLint ? [] : [
                 .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .target(
            name: "SURBenchmarkSupport",
            dependencies: [
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ],
            plugins: skipSwiftLint ? [] : [
                 .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .executableTarget(
            name: "SURBenchmarks",
            dependencies: [
                .target(name: "SURCore"),
                .target(name: "SURBenchmarkSupport"),
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "XcodeProj", package: "XcodeProj"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            plugins: skipSwiftLint ? [] : [
                 .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .binaryTarget(
            name: "SURBinary",
            url: "https://github.com/mugabe/SwiftUnusedResources/releases/download/0.4.0/sur-0.4.0.artifactbundle.zip",
            checksum: "be08ec4a61e1772189a04c93e5caf8012f23cf981e55a34756ed2bf1dc2ce8d8"
        ),
        .testTarget(
            name: "SURCoreTests",
            dependencies: [
                .target(name: "SURCore"),
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "XcodeProj", package: "XcodeProj"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            plugins: skipSwiftLint ? [] : [
                 .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "SURBenchmarkSupportTests",
            dependencies: [
                .target(name: "SURBenchmarkSupport"),
                .target(name: "SURCore"),
                .product(name: "PathKit", package: "PathKit"),
            ]
        ),
    ]
)
