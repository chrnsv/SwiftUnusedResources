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
