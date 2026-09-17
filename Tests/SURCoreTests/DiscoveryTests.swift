import PathKit
import Testing

@testable import SURCore

@Suite("File discovery")
struct DiscoveryTests {
    @Test("Finds resources and sources, skipping catalog internals and .icon bundles")
    func synchronizedGroup() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("App/Main.swift", "")
        try tmp.write("App/Images/logo.png", "x")
        try tmp.write("App/Views/Main.storyboard", "<document/>")
        try tmp.write("App/Assets.xcassets/star.imageset/star.png", "x")
        try tmp.write("App/AppIcon.icon/Assets/front.png", "x")

        let root = tmp.path + "App"
        let discovered = discoverFiles(inSynchronizedGroup: root)

        #expect(discovered.sources == [root + "Main.swift"])
        #expect(discovered.resources == [
            root + "Images/logo.png",
            root + "Assets.xcassets",
            root + "Views/Main.storyboard",
        ])
    }

    @Test("Expands a catalog into image and color resources")
    func catalog() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("Assets.xcassets/Group/star.imageset/Contents.json", "{}")
        try tmp.write("Assets.xcassets/brand.colorset/Contents.json", "{}")

        let resources = assetResources(in: tmp.path + "Assets.xcassets", kinds: [.image, .color], excludedAssets: [])

        #expect(Set(resources.map(\.name)) == ["star", "brand"])
        #expect(resources.first { $0.name == "star" }?.kind == .image)
        #expect(resources.first { $0.name == "brand" }?.kind == .color)
    }

    @Test("An excluded catalog yields nothing")
    func excludedCatalog() throws {
        let tmp = try TemporaryDirectory()
        defer { tmp.remove() }

        try tmp.write("Palette.xcassets/brand.colorset/Contents.json", "{}")

        let resources = assetResources(in: tmp.path + "Palette.xcassets", kinds: [.color], excludedAssets: ["Palette"])

        #expect(resources.isEmpty)
    }
}
