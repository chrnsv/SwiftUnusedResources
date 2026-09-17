import Testing

@testable import SURCore

@Suite("unusedResources pure matching")
struct UnusedResourcesTests {
    private func image(_ name: String) -> ExploreResource {
        ExploreResource(name: name, type: .file, kind: .image, path: "/tmp/\(name).png")
    }

    private func color(_ name: String) -> ExploreResource {
        ExploreResource(name: name, type: .asset(assets: "/tmp/A.xcassets"), kind: .color, path: "/tmp/A.xcassets/\(name).colorset")
    }

    private func names(_ resources: [ExploreResource]) -> [String] {
        resources.map(\.name)
    }

    @Test("String usage matches by exact name")
    func stringUsage() throws {
        let unused = try unusedResources(
            in: [image("star"), image("moon")],
            usages: [.string("star", .image)],
            excluding: []
        )
        #expect(names(unused) == ["moon"])
    }

    @Test("Regexp usage is anchored on both ends")
    func regexpUsage() throws {
        let unused = try unusedResources(
            in: [image("step1"), image("step22"), image("misstep1")],
            usages: [.regexp("step.*", .image)],
            excluding: []
        )
        #expect(names(unused) == ["misstep1"])
    }

    @Test("R.swift usage matches the sanitized identifier")
    func rswiftUsage() throws {
        let unused = try unusedResources(
            in: [image("icon-home"), image("icon-away")],
            usages: [.rswift("iconHome", .image)],
            excluding: []
        )
        #expect(names(unused) == ["icon-away"])
    }

    @Test("Generated usage ignores a trailing Image/Color suffix of the resource name")
    func generatedUsage() throws {
        let unused = try unusedResources(
            in: [color("brandColor"), color("accentColor"), image("heroImage")],
            usages: [.generated("brand", .color), .generated("hero", .image)],
            excluding: []
        )
        #expect(names(unused) == ["accentColor"])
    }

    @Test("A usage of another kind does not count")
    func kindMismatch() throws {
        let unused = try unusedResources(
            in: [image("brand"), color("brand")],
            usages: [.string("brand", .color)],
            excluding: []
        )
        #expect(unused.map(\.kind) == [.image])
    }

    @Test("Excluded resources are never reported")
    func exclusions() throws {
        let unused = try unusedResources(in: [image("star"), image("moon")], usages: [], excluding: ["moon"])
        #expect(names(unused) == ["star"])
    }

    @Test("Result keeps the order of the input resources")
    func order() throws {
        let unused = try unusedResources(in: [image("c"), image("a"), image("b")], usages: [], excluding: [])
        #expect(names(unused) == ["c", "a", "b"])
    }

    @Test("An invalid regexp pattern throws")
    func invalidPattern() {
        #expect(throws: (any Error).self) {
            try unusedResources(in: [image("star")], usages: [.regexp("(", .image)], excluding: [])
        }
    }
}
