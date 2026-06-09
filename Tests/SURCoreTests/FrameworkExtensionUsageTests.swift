import Foundation
import Testing

@testable import SURCore

@Suite("UIKit / SwiftUI generated asset symbol detection")
struct FrameworkExtensionUsageTests {
    private func generatedIdentifiers(
        _ source: String,
        kind: ExploreKind
    ) -> [String] {
        let parser = SwiftParser(showWarnings: false, kinds: [kind])

        return parser.parse(source: source).compactMap { usage in
            if case let .generated(identifier, usageKind) = usage, usageKind == kind {
                return identifier
            }
            return nil
        }
    }

    private func usages(
        _ source: String,
        kind: ExploreKind
    ) -> [ExploreUsage] {
        SwiftParser(showWarnings: false, kinds: [kind]).parse(source: source)
    }

    // MARK: - Explicit type-prefixed access

    @Test("Detects UIImage.assetName")
    func explicitUIImageAccess() {
        let ids = generatedIdentifiers("let image = UIImage.star", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects UIColor.assetName")
    func explicitUIColorAccess() {
        let ids = generatedIdentifiers("let color = UIColor.brand", kind: .color)
        #expect(ids == ["brand"])
    }

    @Test("Detects SwiftUI Image.assetName")
    func explicitSwiftUIImageAccess() {
        let ids = generatedIdentifiers("let image = Image.star", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects SwiftUI Color.assetName")
    func explicitSwiftUIColorAccess() {
        let ids = generatedIdentifiers("let color = Color.brand", kind: .color)
        #expect(ids == ["brand"])
    }

    @Test("Detects module-qualified access")
    func moduleQualifiedAccess() {
        #expect(generatedIdentifiers("let image = SwiftUI.Image.star", kind: .image) == ["star"])
        #expect(generatedIdentifiers("let image = UIKit.UIImage.star", kind: .image) == ["star"])
    }

    // MARK: - Chained access

    @Test("Detects asset in UIImage method chain")
    func uiImageMethodChain() {
        let source = "let image = UIImage.star.withRenderingMode(.alwaysTemplate)"
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects asset in Color method chain")
    func colorMethodChain() {
        let ids = generatedIdentifiers("let color = Color.brand.opacity(0.5)", kind: .color)
        #expect(ids == ["brand"])
    }

    @Test("Detects asset in long property chain")
    func longPropertyChain() {
        let ids = generatedIdentifiers("let width = UIImage.star.size.width", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Chain fix also applies to ImageResource")
    func imageResourceChain() {
        let ids = generatedIdentifiers("let value = ImageResource.star.foo()", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects chained UIImage(resource:) initializer")
    func chainedResourceInitializer() {
        let source = "let image = UIImage(resource: .star).withRenderingMode(.alwaysTemplate)"
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects chained Image(.assetName) initializer")
    func chainedImageInitializer() {
        let source = """
        import SwiftUI
        let view = Image(.star).resizable()
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects module-qualified SwiftUI.Image(.assetName) initializer")
    func moduleQualifiedInitializer() {
        let ids = generatedIdentifiers("let view = SwiftUI.Image(.star)", kind: .image)
        #expect(ids == ["star"])
        #expect(!ids.contains("Image"))
    }

    @Test("Detects both branches of a ternary initializer argument")
    func branchedInitializerArgument() {
        let resourceIds = generatedIdentifiers("let image = UIImage(resource: flag ? .a : .b)", kind: .image)
        #expect(Set(resourceIds) == ["a", "b"])

        let imageIds = generatedIdentifiers("let view = Image(flag ? .dark : .light)", kind: .image)
        #expect(Set(imageIds) == ["dark", "light"])
    }

    @Test("Module-qualified string initializers still produce a regexp usage")
    func moduleQualifiedNamedInitializer() {
        let uiKitSource = """
        import UIKit
        let image = UIKit.UIImage(named: "star")
        """
        let uiKitUsages = usages(uiKitSource, kind: .image)
        #expect(uiKitUsages == [.regexp("star", .image)])

        let swiftUISource = """
        import SwiftUI
        let view = SwiftUI.Image("banner")
        """
        let swiftUIUsages = usages(swiftUISource, kind: .image)
        #expect(swiftUIUsages == [.regexp("banner", .image)])
    }

    // MARK: - Typed contexts

    @Test("Detects bare member in framework-typed bindings")
    func frameworkTypedBindings() {
        #expect(generatedIdentifiers("let icon: UIImage = .star", kind: .image) == ["star"])
        #expect(generatedIdentifiers("let icon: UIImage? = .star", kind: .image) == ["star"])
        #expect(generatedIdentifiers("let icon: UIImage! = .star", kind: .image) == ["star"])
    }

    @Test("Detects bare members in array-typed bindings")
    func arrayTypedBindings() {
        #expect(generatedIdentifiers("let icons: [Image] = [.a, .b]", kind: .image) == ["a", "b"])
        #expect(generatedIdentifiers("let colors: Array<UIColor> = [.x]", kind: .color) == ["x"])
    }

    @Test("Detects bare member in framework-typed computed property")
    func computedProperty() {
        #expect(generatedIdentifiers("var bg: UIColor { .brand }", kind: .color) == ["brand"])
        #expect(generatedIdentifiers("var bg: Color { get { .brand } }", kind: .color) == ["brand"])
    }

    @Test("Detects bare member in framework-typed function return")
    func functionReturn() {
        #expect(generatedIdentifiers("func tint() -> Color { .accent }", kind: .color) == ["accent"])
        #expect(generatedIdentifiers("func tint() -> UIColor { return .accent }", kind: .color) == ["accent"])
    }

    @Test("Detects bare member in framework-typed closure return")
    func closureReturn() {
        let ids = generatedIdentifiers("let make = { () -> Image in .star }", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Detects assets in parameter default values")
    func parameterDefaults() {
        let funcIds = generatedIdentifiers("func makeBadge(icon: UIImage = .star) {}", kind: .image)
        #expect(funcIds == ["star"])

        let initSource = """
        struct Palette {
            init(colors: [ColorResource] = [.a, .b]) {}
        }
        """
        let initIds = generatedIdentifiers(initSource, kind: .color)
        #expect(initIds == ["a", "b"])
    }

    @Test("Detects bare members returned from subscripts")
    func subscriptReturns() {
        let implicitSource = """
        struct IconSet {
            subscript(index: Int) -> UIImage { .star }
        }
        """
        #expect(generatedIdentifiers(implicitSource, kind: .image) == ["star"])

        let explicitSource = """
        struct IconSet {
            subscript(state: State) -> ImageResource {
                switch state {
                case .loading: return .spinner
                case .done: return .check
                }
            }
        }
        """
        #expect(Set(generatedIdentifiers(explicitSource, kind: .image)) == ["spinner", "check"])
    }

    @Test("Detects assets in control flow with framework return type")
    func controlFlow() {
        let source = """
        func icon(for state: State) -> UIImage {
            switch state {
            case .loading: return .spinner
            case .done: return .check
            }
        }
        var badge: UIImage {
            if flag { .foo } else { .bar }
        }
        var tone: UIColor { flag ? .on : .off }
        """
        #expect(Set(generatedIdentifiers(source, kind: .image)) == ["spinner", "check", "foo", "bar"])
        #expect(Set(generatedIdentifiers(source, kind: .color)) == ["on", "off"])
    }

    @Test("Detects assets assigned to a framework-typed local across branches")
    func assignmentDataflow() {
        let source = """
        func icon(for state: State) -> UIImage {
            var result: UIImage = .placeholder
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

    @Test("Detects bare member in module-qualified annotation")
    func moduleQualifiedAnnotation() {
        let ids = generatedIdentifiers("let icon: SwiftUI.Image = .star", kind: .image)
        #expect(ids == ["star"])
    }

    @Test("Records system members in framework-typed contexts (accepted over-match)")
    func systemMemberOverMatch() {
        // `.red` is a system color, but marking an asset named "red" as used is the safe
        // direction — it can never cause a used asset to be reported as unused.
        let ids = generatedIdentifiers("let c: Color = .red", kind: .color)
        #expect(ids == ["red"])
    }

    // MARK: - Negative

    @Test("Ignores Image(systemName:)")
    func ignoresSystemName() {
        let source = """
        import SwiftUI
        let view = Image(systemName: "gear")
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids.isEmpty)
    }

    @Test("UIImage(named:) still produces a regexp usage, not a generated one")
    func namedStaysRegexp() {
        let source = """
        import UIKit
        let image = UIImage(named: "star")
        """
        let all = usages(source, kind: .image)
        let generated = all.filter { usage in
            if case .generated = usage {
                return true
            }
            return false
        }
        let regexps = all.filter { usage in
            if case .regexp = usage {
                return true
            }
            return false
        }
        #expect(generated.isEmpty)
        #expect(regexps.count == 1)
    }

    @Test("Ignores bare member in non-resource-typed context")
    func ignoresUnrelatedEnum() {
        #expect(generatedIdentifiers("let value: SomeEnum = .caseA", kind: .image).isEmpty)
        #expect(generatedIdentifiers("let value: SomeEnum = .caseA", kind: .color).isEmpty)
    }

    @Test("Ignores types in custom namespaces")
    func ignoresCustomNamespace() {
        #expect(generatedIdentifiers("let image = MyKit.Image.star", kind: .image).isEmpty)
        #expect(generatedIdentifiers("let icon: MyKit.Image = .star", kind: .image).isEmpty)
    }

    @Test("Ignores explicit initializer reference")
    func ignoresInitReference() {
        let ids = generatedIdentifiers("let make = UIImage.init(named: \"x\")", kind: .image)
        #expect(!ids.contains("init"))
    }

    @Test("Ignores member access on unrelated types")
    func ignoresUnrelatedTypes() {
        #expect(generatedIdentifiers("let value = Foo.star.bar()", kind: .image).isEmpty)
    }

    @Test("Detects Image(.assetName) exactly once")
    func noDoubleCount() {
        let source = """
        import SwiftUI
        let view = Image(.star)
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids == ["star"])
    }
}
