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

    @Test("R.swift usage keeps underscores in the identifier")
    func rswiftUsageOfSnakeCaseName() throws {
        let unused = try unusedResources(
            in: [image("icon_name"), image("iconName")],
            usages: [.rswift("icon_name", .image)],
            excluding: []
        )
        #expect(names(unused) == ["iconName"])
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

    @Test("Generated usage matches a snake_case resource by its camel-cased Xcode symbol")
    func generatedUsageOfSnakeCaseName() throws {
        let unused = try unusedResources(
            in: [image("mascot_bear_review_avatar"), image("bear_shy"), image("lion_shy")],
            usages: [.generated("mascotBearReviewAvatar", .image), .generated("bearShy", .image)],
            excluding: []
        )
        #expect(names(unused) == ["lion_shy"])
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

    @Test("An invalid pattern still throws when every resource of its kind is matched exactly")
    func invalidPatternWithMatchedResources() {
        #expect(throws: (any Error).self) {
            try unusedResources(
                in: [image("star")],
                usages: [.string("star", .image), .regexp("(", .image)],
                excluding: []
            )
        }
    }

    @Test("An invalid pattern does not throw when no resource of its kind is checked")
    func invalidPatternWithoutResourcesOfItsKind() throws {
        let unused = try unusedResources(
            in: [color("brand"), image("excluded")],
            usages: [.regexp("(", .image)],
            excluding: ["excluded"]
        )
        #expect(names(unused) == ["brand"])
    }

    @Test("A literal pattern matches only the exact name")
    func literalPattern() throws {
        let unused = try unusedResources(
            in: [image("star"), image("stars"), image("Star")],
            usages: [.regexp("star", .image)],
            excluding: []
        )
        #expect(names(unused) == ["stars", "Star"])
    }

    @Test("A pattern with a metacharacter is a regexp, not a literal")
    func metacharacterPattern() throws {
        let unused = try unusedResources(
            in: [image("star"), image("st.r"), image("stab")],
            usages: [.regexp("st.r", .image)],
            excluding: []
        )
        #expect(names(unused) == ["stab"])
    }

    @Test("A non-ASCII literal pattern matches exactly like a regexp would")
    func nonASCIIPattern() throws {
        // Precomposed "é" vs. "e" + combining acute: equal as Swift Strings, different for a regex.
        let unused = try unusedResources(
            in: [image("caf\u{E9}"), image("cafe\u{301}")],
            usages: [.regexp("caf\u{E9}", .image)],
            excluding: []
        )
        #expect(names(unused) == ["cafe\u{301}"])
    }
}
