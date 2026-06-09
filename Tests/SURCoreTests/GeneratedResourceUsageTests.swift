import Foundation
import Testing

@testable import SURCore

@Suite("ImageResource / ColorResource usage detection")
struct GeneratedResourceUsageTests {
    private func generatedIdentifiers(
        _ source: String,
        kind: ExploreKind
    ) -> [String] {
        let parser = SwiftParser(showWarnings: false, kinds: [kind])

        return parser.parse(source: source).compactMap { usage in
            if case .generated(let identifier, let usageKind) = usage, usageKind == kind {
                return identifier
            }
            return nil
        }
    }

    // MARK: - Explicit type-prefixed access

    @Test("Detects ImageResource.assetName")
    func explicitImageAccess() {
        let ids = generatedIdentifiers("let value = ImageResource.star", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects ColorResource.assetName")
    func explicitColorAccess() {
        let ids = generatedIdentifiers("let value = ColorResource.brand", kind: .color)
        #expect(ids == ["brand"])
    }

    // MARK: - Type-annotated bindings

    @Test("Detects bare member in type-annotated binding")
    func annotatedBinding() {
        let ids = generatedIdentifiers("let icon: ImageResource = .star", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects bare members in array-typed binding")
    func arrayTypedBinding() {
        let ids = generatedIdentifiers("let icons: [ImageResource] = [.a, .b]", kind: .image)
        #expect(ids == ["a", "b"])
    }

    @Test("Detects bare member in optional-typed binding")
    func optionalTypedBinding() {
        let ids = generatedIdentifiers("let icon: ImageResource? = .star", kind: .image)
        #expect(ids == ["star"])
    }

    // MARK: - Computed properties

    @Test("Detects bare member in computed property")
    func computedProperty() {
        let ids = generatedIdentifiers("var icon: ImageResource { .star }", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects both ternary branches in computed property")
    func computedPropertyTernary() {
        let source = "var badge: ColorResource { flag ? .on : .off }"
        let ids = generatedIdentifiers(source, kind: .color)
        #expect(Set(ids) == ["on", "off"])
    }

    @Test("Detects bare member in explicit get accessor")
    func explicitGetAccessor() {
        let source = "var icon: ImageResource { get { .star } }"
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }

    // MARK: - Function / closure return types

    @Test("Detects bare member in implicit function return")
    func functionImplicitReturn() {
        let ids = generatedIdentifiers("func makeIcon() -> ImageResource { .star }", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects bare member in explicit function return")
    func functionExplicitReturn() {
        let source = "func makeIcon() -> ImageResource { return .star }"
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects bare member in closure return type")
    func closureReturnType() {
        let source = "let make = { () -> ImageResource in .star }"
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }

    // MARK: - Control flow: explicit returns

    @Test("Detects assets returned from switch cases")
    func switchExplicitReturns() {
        let source = """
        func icon(for state: State) -> ImageResource {
            switch state {
            case .loading: return .spinner
            case .done: return .check
            }
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["spinner", "check"])
    }

    @Test("Detects assets returned from if/else branches")
    func ifElseExplicitReturns() {
        let source = """
        func icon(flag: Bool) -> ImageResource {
            if flag { return .foo } else { return .bar }
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["foo", "bar"])
    }

    @Test("Detects early return plus trailing return")
    func earlyAndTrailingReturn() {
        let source = """
        func icon(flag: Bool) -> ImageResource {
            if flag { return .foo }
            return .bar
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["foo", "bar"])
    }

    @Test("Detects asset returned from guard else")
    func guardElseReturn() {
        let source = """
        func icon(value: Int?) -> ImageResource {
            guard value != nil else { return .fallback }
            return .main
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["fallback", "main"])
    }

    // MARK: - Control flow: implicit returns (expressions)

    @Test("Detects assets in implicit-return switch expression, ignoring case patterns")
    func switchImplicitReturn() {
        let source = """
        var icon: ImageResource {
            switch state {
            case .loading: .spinner
            case .done: .check
            }
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["spinner", "check"])
        // Case patterns must not be collected as assets.
        #expect(!ids.contains("loading"))
        #expect(!ids.contains("done"))
    }

    @Test("Detects assets in implicit-return if/else expression")
    func ifElseImplicitReturn() {
        let source = """
        var icon: ImageResource {
            if flag { .foo } else { .bar }
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["foo", "bar"])
    }

    @Test("Detects assets in if nested inside a switch case")
    func nestedIfInsideSwitch() {
        let source = """
        var icon: ImageResource {
            switch state {
            case .a: flag ? .one : .two
            case .b: .three
            }
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["one", "two", "three"])
    }

    // MARK: - Assignment dataflow

    @Test("Detects assets assigned to a resource-typed local across branches")
    func assignmentDataflow() {
        let source = """
        func icon(for state: State) -> ImageResource {
            var result: ImageResource = .placeholder
            switch state {
            case .a: result = .foo
            default: result = .bar
            }
            return result
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["placeholder", "foo", "bar"])
    }

    // MARK: - Precision

    @Test("Ignores bare members passed as function-call arguments in a resource return")
    func ignoresCallArguments() {
        let source = """
        func icon(for screen: Screen) -> ImageResource {
            resolve(for: .settingsScreen)
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids.isEmpty)
    }

    @Test("Confines resource-typed locals to their own scope")
    func scopedTypedLocals() {
        let source = """
        func a() -> ImageResource {
            var icon: ImageResource = .home
            return icon
        }
        func b() {
            icon = .somethingElse
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["home"])
        #expect(!ids.contains("somethingElse"))
    }

    @Test("Detects assignment to a resource-typed stored property from a method")
    func storedPropertyAssignment() {
        let source = """
        class Library {
            var icon: ImageResource = .seed

            func update() {
                icon = .reassigned
            }
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(Set(ids) == ["seed", "reassigned"])
    }

    // MARK: - Negative

    @Test("Ignores switch over unrelated enum in non-resource context")
    func ignoresUnrelatedSwitch() {
        let source = """
        func describe(_ state: State) -> String {
            switch state {
            case .success: "ok"
            case .failure: "no"
            }
        }
        """
        let imageIds = generatedIdentifiers(source, kind: .image)
        let colorIds = generatedIdentifiers(source, kind: .color)
        #expect(imageIds.isEmpty)
        #expect(colorIds.isEmpty)
    }

    @Test("Ignores bare member in non-resource-typed context")
    func ignoresUnrelatedEnum() {
        let imageIds = generatedIdentifiers("let value: SomeEnum = .caseA", kind: .image)
        let colorIds = generatedIdentifiers("let value: SomeEnum = .caseA", kind: .color)
        #expect(imageIds.isEmpty)
        #expect(colorIds.isEmpty)
    }

    // MARK: - Regression: existing detection still works

    @Test("Still detects SwiftUI Image(.assetName)")
    func swiftUIImageGenerated() {
        let source = """
        import SwiftUI
        let view = Image(.star)
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Still detects UIImage(resource: .assetName)")
    func uiKitImageGenerated() {
        let source = """
        import UIKit
        let image = UIImage(resource: .star)
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }
}
