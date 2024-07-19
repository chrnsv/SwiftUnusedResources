// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "SUR",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "sur", targets: ["SUR"]),
        .plugin(name: "SURBuildToolPlugin", targets: ["SURBuildToolPlugin"]),
        .library(name: "SURCore", targets: ["SURCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax", from: "510.0.2"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.1"),
        .package(url: "https://github.com/Bouke/Glob.git", from: "1.0.5"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "8.22.0"),
        .package(url: "https://github.com/IBDecodable/IBDecodable.git", branch: "master"),
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.55.1"),
    ],
    targets: [
        .executableTarget(
            name: "SUR",
             dependencies: [
                "PathKit",
                "Rainbow",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "SURCore"),
             ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .plugin(
            name: "SURBuildToolPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "SUR"),
            ]
        ),
        .target(
            name: "SURCore",
            dependencies:[
                "PathKit",
                "Glob",
                "XcodeProj",
                "IBDecodable",
                "Rainbow",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
             ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
