// swift-tools-version:6.0

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
        .package(url: "https://github.com/apple/swift-syntax", from: "600.0.0"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.1"),
        .package(url: "https://github.com/Bouke/Glob.git", from: "1.0.5"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "8.23.7"),
        .package(url: "https://github.com/IBDecodable/IBDecodable.git", from: "0.6.1"),
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.57.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3")
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
                .target(name: "SURBinary"),
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
                .product(name: "Yams", package: "Yams"),
            ],
            plugins: [
                 .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .binaryTarget(
            name: "SURBinary",
            url: "https://github.com/mugabe/SwiftUnusedResources/releases/download/0.0.9/sur-0.0.9.artifactbundle.zip",
            checksum: "bab77e669168544503c47f2f00b249204394f5ca30b88b94583c40ebb075e7e5"
        ),
    ]
)
