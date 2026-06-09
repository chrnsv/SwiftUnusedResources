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

    // MARK: - Negative

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
