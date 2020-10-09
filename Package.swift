// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "SUR",
    platforms: [.macOS(.v10_12)],
    products: [
        .executable(name: "sur", targets: ["SUR"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax", from: "0.50300.0"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.0"),
        .package(url: "https://github.com/Bouke/Glob.git", from: "1.0.4"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "7.14.0"),
        .package(url: "https://github.com/IBDecodable/IBDecodable.git", from: "0.4.2"),
        .package(url: "https://github.com/benoit-pereira-da-silva/CommandLine.git", from: "4.0.9"),
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "3.2.0")
    ],
    targets: [
        .target(name: "SUR", dependencies: ["PathKit", "Glob", "XcodeProj", "IBDecodable", "CommandLineKit", "Rainbow", "SwiftSyntax"]),
    ],
    swiftLanguageVersions: [.v5]
)
