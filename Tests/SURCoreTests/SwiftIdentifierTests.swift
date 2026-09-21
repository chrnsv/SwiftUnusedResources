import Foundation
import Testing

@testable import SURCore

@Suite("SwiftIdentifier name sanitization and withoutImageAndColor()")
struct SwiftIdentifierTests {
    private func identifier(_ name: String) -> String {
        SwiftIdentifier(name: name).description
    }

    // MARK: - Plain names

    @Test("Keeps a simple lowercase name")
    func simpleName() {
        #expect(identifier("star") == "star")
    }

    @Test("Keeps trailing digits")
    func trailingDigits() {
        #expect(identifier("icon42") == "icon42")
    }

    @Test("Preserves underscores")
    func underscores() {
        #expect(identifier("icon_name") == "icon_name")
    }

    @Test("Returns an empty identifier for an empty name")
    func emptyName() {
        #expect(identifier("").isEmpty)
    }

    // MARK: - Blacklisted characters

    @Test("Camel-cases around a dash")
    func dashSeparated() {
        #expect(identifier("my-icon") == "myIcon")
    }

    @Test("Camel-cases around a space")
    func spaceSeparated() {
        #expect(identifier("icon name") == "iconName")
    }

    @Test("Camel-cases around a period")
    func periodSeparated() {
        #expect(identifier("icon.name") == "iconName")
    }

    // Emoji are deliberately allowed in identifiers rather than treated as separators.
    @Test(
        "Keeps emoji, including the last scalar of each allowed range",
        arguments: [
            "\u{2600}", "\u{27BF}",
            "\u{1F300}", "\u{1F6FF}",
            "\u{1F900}", "\u{1F9FF}",
            "\u{1F1E6}", "\u{1F1FF}",
        ]
    )
    func keepsEmoji(emoji: String) {
        #expect(identifier("icon\(emoji)") == "icon\(emoji)")
    }

    // U+2FFFF is a permanent noncharacter, so it stays blacklisted. Guards against
    // rebuilding the blacklist in a way that drops the supplementary planes.
    @Test("Strips a blacklisted character outside the Basic Multilingual Plane")
    func stripsSupplementaryPlaneCharacter() {
        #expect(identifier("icon\u{2FFFF}") == "icon")
    }

    // MARK: - Leading digits

    @Test("Strips leading digits")
    func leadingDigits() {
        #expect(identifier("42icon") == "icon")
    }

    // MARK: - Casing

    @Test("Lowercases an uppercase acronym prefix")
    func acronymPrefix() {
        #expect(identifier("URLString") == "urlString")
        #expect(identifier("ABCIcon") == "abcIcon")
    }

    @Test("Lowercases only the first character of a regular name")
    func uppercaseFirstCharacter() {
        #expect(identifier("MyIcon") == "myIcon")
    }

    @Test("Keeps casing when lowercaseStartingCharacters is false")
    func keepsCasing() {
        let result = SwiftIdentifier(name: "MyIcon", lowercaseStartingCharacters: false)
        #expect(result.description == "MyIcon")
    }

    // MARK: - Keywords

    @Test("Escapes Swift keywords with backticks")
    func keywords() {
        #expect(identifier("class") == "`class`")
        #expect(identifier("switch") == "`switch`")
    }

    // MARK: - String.withoutImageAndColor()

    @Test("Strips a trailing Color suffix")
    func stripsColorSuffix() {
        #expect("brandColor".withoutImageAndColor() == "brand")
    }

    @Test("Strips a trailing Image suffix")
    func stripsImageSuffix() {
        #expect("heroImage".withoutImageAndColor() == "hero")
    }

    @Test("Strips suffixes case-insensitively")
    func stripsCaseInsensitively() {
        #expect("xCOLOR".withoutImageAndColor() == "x")
    }

    @Test("Strips repeated suffixes")
    func stripsRepeatedSuffixes() {
        #expect("brandImageColor".withoutImageAndColor() == "brand")
    }

    @Test("Leaves non-suffix occurrences untouched")
    func nonSuffixOccurrence() {
        #expect("colorful".withoutImageAndColor() == "colorful")
        #expect("imageView".withoutImageAndColor() == "imageView")
    }
}
