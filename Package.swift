// swift-tools-version:6.2

import PackageDescription
import Foundation

let skipSwiftLint = ProcessInfo.processInfo.environment["SKIP_SWIFTLINT"] != nil

let package = Package(
    name: "SUR",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "sur", targets: ["SUR"]),
        .plugin(name: "SURBuildToolPlugin", targets: ["SURBuildToolPlugin"]),
        .library(name: "SURCore", targets: ["SURCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "603.0.0"),
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "1.0.1"),
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "1.0.5"),
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "9.13.0"),
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "0.6.1"),
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "4.2.1"),
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "1.8.0"),
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "0.63.0"),
        .package(url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip", from: "6.2.0")
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
                .product(name: "Glob", package: "Glob"),
                .product(name: "XcodeProj", package: "XcodeProj"),
                .product(name: "IBDecodable", package: "IBDecodable"),
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
        .binaryTarget(
            name: "SURBinary",
            url: "https://github.com/chrnsv/SwiftUnusedResources/releases/download/untagged-567c4aaf90d28950ccd1/sur-0.3.1.artifactbundle.zip",
            checksum: "67d32be6efaf859ed6fed31f3afddf7e19a8ab2b0e37ec71b6937d90e4becda7"
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
    ]
)
