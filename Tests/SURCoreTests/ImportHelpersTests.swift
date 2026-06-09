import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import SURCore

@Suite("ImportHelpers (hasImport, insertImport, insertion index)")
struct ImportHelpersTests {
    private func file(_ source: String) -> SourceFileSyntax {
        Parser.parse(source: source)
    }

    // MARK: - hasImport

    @Test("Finds an existing import")
    func findsExistingImport() {
        let source = file("import UIKit\n\nlet x = 1\n")
        #expect(ImportHelpers.hasImport(named: "UIKit", in: source))
    }

    @Test("Reports a missing import")
    func reportsMissingImport() {
        let source = file("import UIKit\n\nlet x = 1\n")
        #expect(!ImportHelpers.hasImport(named: "SwiftUI", in: source))
    }

    @Test("Matches the import path exactly, not by module prefix")
    func submoduleImportDoesNotMatch() {
        let source = file("import UIKit.UIView\n")
        #expect(!ImportHelpers.hasImport(named: "UIKit", in: source))
        #expect(ImportHelpers.hasImport(named: "UIKit.UIView", in: source))
    }

    // MARK: - insertImport

    @Test("Inserts at the top of a file without imports")
    func insertsIntoFileWithoutImports() {
        let source = file("let x = 1\n")
        let result = ImportHelpers.insertImport(named: "SwiftUI", into: source)

        #expect(result.statements.first?.item.is(ImportDeclSyntax.self) == true)
        #expect(ImportHelpers.hasImport(named: "SwiftUI", in: result))
    }

    @Test("Inserts after the last existing import")
    func insertsAfterLastImport() throws {
        let source = file("import A\nimport B\n\nlet x = 1\n")
        let result = ImportHelpers.insertImport(named: "C", into: source)

        let text = result.description
        let importB = try #require(text.range(of: "import B"))
        let importC = try #require(text.range(of: "import C"))
        let letX = try #require(text.range(of: "let x"))

        #expect(importB.lowerBound < importC.lowerBound)
        #expect(importC.lowerBound < letX.lowerBound)
    }

    @Test("Starts the inserted import on a new line")
    func insertsOnNewLine() {
        let source = file("import A\nlet x = 1\n")
        let result = ImportHelpers.insertImport(named: "B", into: source)

        #expect(result.description.contains("\nimport B"))
        #expect(!result.description.contains("import Aimport B"))
    }

    @Test("Round-trips through hasImport")
    func roundTrip() {
        let source = file("import A\n\nlet x = 1\n")
        let result = ImportHelpers.insertImport(named: "SwiftUI", into: source)

        #expect(ImportHelpers.hasImport(named: "SwiftUI", in: result))
    }

    // MARK: - lastImportInsertionIndex

    @Test("Returns zero for a file without imports")
    func insertionIndexWithoutImports() {
        let source = file("let x = 1\n")
        #expect(ImportHelpers.lastImportInsertionIndex(in: source) == 0)
    }

    @Test("Returns the position after the last leading import")
    func insertionIndexAfterImports() {
        let source = file("import A\nimport B\n\nlet x = 1\n")
        #expect(ImportHelpers.lastImportInsertionIndex(in: source) == 2)
    }

    @Test("Follows an import that appears after other code")
    func insertionIndexAfterLateImport() {
        let source = file("import A\nlet x = 1\nimport B\nlet y = 2\n")
        #expect(ImportHelpers.lastImportInsertionIndex(in: source) == 3)
    }

    // MARK: - triviaEndsWithNewline

    @Test("Returns false for nil trivia")
    func nilTrivia() {
        #expect(!ImportHelpers.triviaEndsWithNewline(nil))
    }

    @Test("Returns false for spaces only")
    func spacesOnlyTrivia() {
        #expect(!ImportHelpers.triviaEndsWithNewline(.spaces(2)))
    }

    @Test("Returns true for a trailing newline")
    func trailingNewlineTrivia() {
        #expect(ImportHelpers.triviaEndsWithNewline(.newlines(1)))
    }

    @Test("Ignores spaces after the final newline")
    func spacesAfterNewlineTrivia() {
        let trivia = Trivia(pieces: [.newlines(1), .spaces(4)])
        #expect(ImportHelpers.triviaEndsWithNewline(trivia))
    }
}
