import Foundation
import Testing

@testable import SURCore

@Suite("String pattern extraction for UIImage(named:) and Image(_:)")
struct StringPatternUsageTests {
    private func patterns(_ source: String, kind: ExploreKind = .image) -> [String] {
        let parser = SwiftParser(showWarnings: false, kinds: [kind])

        return parser.parse(source: source).compactMap { usage in
            if case let .regexp(pattern, usageKind) = usage, usageKind == kind {
                return pattern
            }
            return nil
        }
    }

    // MARK: - Plain literals

    @Test("Extracts a literal name from UIImage(named:)")
    func uiImageLiteral() {
        let result = patterns("""
        import UIKit

        let image = UIImage(named: "icon")
        """)

        #expect(result == ["icon"])
    }

    @Test("Extracts a literal name from SwiftUI Image")
    func swiftUIImageLiteral() {
        let result = patterns("""
        import SwiftUI

        let view = Image("icon")
        """)

        #expect(result == ["icon"])
    }

    // MARK: - Interpolations

    @Test("Replaces a trailing interpolation with a wildcard")
    func trailingInterpolation() {
        let result = patterns("""
        import SwiftUI

        let view = Image("icon_\\(index)")
        """)

        #expect(result == ["icon_.*"])
    }

    @Test("Keeps literal segments around an interpolation")
    func midInterpolation() {
        let result = patterns("""
        import SwiftUI

        let view = Image("ic_\\(index)_large")
        """)

        #expect(result == ["ic_.*_large"])
    }

    @Test("Replaces a function-call interpolation with a wildcard")
    func functionCallInterpolation() {
        let result = patterns("""
        import SwiftUI

        let view = Image("ic_\\(name())")
        """)

        #expect(result == ["ic_.*"])
    }

    // MARK: - Concatenation

    @Test("Builds a prefix pattern from literal + variable")
    func literalPlusVariable() {
        let result = patterns("""
        import UIKit

        let image = UIImage(named: "icon" + suffix)
        """)

        #expect(result == ["icon.*"])
    }

    @Test("Builds a suffix pattern from variable + literal")
    func variablePlusLiteral() {
        let result = patterns("""
        import UIKit

        let image = UIImage(named: prefix + "_icon")
        """)

        #expect(result == [".*_icon"])
    }

    @Test("Joins adjacent literals")
    func literalPlusLiteral() {
        let result = patterns("""
        import SwiftUI

        let view = Image("ic_" + "star")
        """)

        #expect(result == ["ic_star"])
    }

    @Test("Builds a prefix pattern from a subscript")
    func literalPlusSubscript() {
        let result = patterns("""
        import SwiftUI

        let view = Image("ic_" + names[0])
        """)

        #expect(result == ["ic_.*"])
    }

    // MARK: - Ternaries

    @Test("Builds an alternation from a ternary")
    func ternary() {
        let result = patterns("""
        import SwiftUI

        let view = Image(flag ? "a" : "b")
        """)

        #expect(result == ["(?:a|b)"])
    }

    @Test("Builds an optional group when the else branch is empty")
    func ternaryEmptyElse() {
        let result = patterns("""
        import SwiftUI

        let view = Image(flag ? "on" : "")
        """)

        #expect(result == ["(?:on)?"])
    }

    @Test("Builds an optional group when the then branch is empty")
    func ternaryEmptyThen() {
        let result = patterns("""
        import SwiftUI

        let view = Image(flag ? "" : "off")
        """)

        #expect(result == ["(?:off)?"])
    }

    @Test("Drops a ternary with a fully dynamic branch")
    func ternaryDynamicBranch() {
        let result = patterns("""
        import SwiftUI

        let view = Image(flag ? "a" : dynamicName)
        """)

        #expect(result.isEmpty)
    }

    @Test("Nests alternations for nested ternaries")
    func nestedTernary() {
        let result = patterns("""
        import SwiftUI

        let view = Image(a ? "x" : (b ? "y" : "z"))
        """)

        #expect(result == ["(?:x|(?:y|z))"])
    }

    // MARK: - Dynamic names

    @Test("Drops a fully dynamic name")
    func fullyDynamicName() {
        let result = patterns("""
        import SwiftUI

        let view = Image(dynamicName)
        """)

        #expect(result.isEmpty)
    }

    @Test("Ignores UIImage(named:) when neither UIKit nor SwiftUI is imported")
    func missingImport() {
        let result = patterns("""
        let image = UIImage(named: "icon")
        """)

        #expect(result.isEmpty)
    }

    // MARK: - Comment overrides

    @Test("Uses the pattern from a leading image: comment")
    func leadingCommentOverride() {
        let result = patterns("""
        import SwiftUI

        // image: ic_\\d+
        let view = Image(dynamicName)
        """)

        #expect(result == ["ic_\\d+"])
    }

    @Test("Uses the comment pattern instead of the guessed one")
    func commentOverridesGuess() {
        let result = patterns("""
        import UIKit

        // image: icon(Small|Large)
        let image = UIImage(named: "icon" + size())
        """)

        #expect(result == ["icon(Small|Large)"])
    }
}
