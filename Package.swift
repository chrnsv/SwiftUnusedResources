// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "SUR",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "sur", targets: ["SUR"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax", from: "508.0.0"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.1"),
        .package(url: "https://github.com/Bouke/Glob.git", from: "1.0.5"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "8.13.0"),
        .package(url: "https://github.com/IBDecodable/IBDecodable.git", from: "0.6.0"),
        .package(url: "https://github.com/benoit-pereira-da-silva/CommandLine.git", from: "4.0.9"),
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.1")
    ],
    targets: [
        .executableTarget(
            name: "SUR",
             dependencies: [
                "PathKit", 
                "Glob",
                "XcodeProj", 
                "IBDecodable", 
                .product(name: "CommandLineKit", package: "CommandLine"), 
                "Rainbow", 
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxParser", package: "swift-syntax")
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
