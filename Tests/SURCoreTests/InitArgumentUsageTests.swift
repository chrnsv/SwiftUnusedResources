import Foundation
import Testing

@testable import SURCore

@Suite("Resource usage through struct/class initializer arguments")
struct InitArgumentUsageTests {
    private let kinds: Set<ExploreKind> = [.image, .color]

    /// Parses a single source, then resolves its pending initializer calls against its own
    /// declared registry — mirroring what `Explorer` does across files for one file's worth.
    private func usages(_ source: String) -> [ExploreUsage] {
        let result = SwiftParser(showWarnings: false, kinds: kinds).parseDetailed(source: source)
        return InitArgumentResolver(typeRegistry: result.typeRegistry, kinds: kinds).resolve(result.pendingInits)
    }

    private func images(_ source: String) -> [String] {
        identifiers(in: source, of: .image)
    }

    private func colors(_ source: String) -> [String] {
        identifiers(in: source, of: .color)
    }

    private func identifiers(in source: String, of kind: ExploreKind) -> [String] {
        usages(source).compactMap { usage in
            guard case let .generated(identifier, usageKind) = usage, usageKind == kind else {
                return nil
            }
            return identifier
        }
    }

    // MARK: - Memberwise initializer

    @Test("Resolves a resource passed to a struct's memberwise init")
    func memberwiseInit() {
        let source = """
        struct S { let icon: ImageResource }
        let x = S(icon: .star)
        """
        #expect(images(source) == ["star"])
    }

    @Test("Resolves image and color args, ignoring a String arg")
    func mixedArguments() {
        let source = """
        struct S { let icon: ImageResource; let bg: ColorResource; let title: String }
        let x = S(icon: .star, bg: .brand, title: "Hi")
        """
        #expect(images(source) == ["star"])
        #expect(colors(source) == ["brand"])
    }

    @Test("Resolves an array-typed resource parameter")
    func arrayParameter() {
        let source = """
        struct S { let icons: [ImageResource] }
        let x = S(icons: [.a, .b])
        """
        #expect(Set(images(source)) == ["a", "b"])
    }

    @Test("Resolves an optional-typed resource parameter")
    func optionalParameter() {
        let source = """
        struct S { let icon: ImageResource? }
        let x = S(icon: .star)
        """
        #expect(images(source) == ["star"])
    }

    @Test("Resolves both branches of a ternary argument")
    func ternaryArgument() {
        let source = """
        struct S { let icon: ImageResource }
        let x = S(icon: flag ? .a : .b)
        """
        #expect(Set(images(source)) == ["a", "b"])
    }

    // MARK: - Explicit initializers

    @Test("Resolves an explicit init's external parameter label")
    func explicitInitLabel() {
        let source = """
        struct S { let stored: ImageResource; init(pic: ImageResource) { stored = pic } }
        let x = S(pic: .star)
        """
        #expect(images(source) == ["star"])
    }

    @Test("Resolves a positional (unlabeled) init parameter")
    func positionalParameter() {
        let source = """
        struct S { let stored: ImageResource; init(_ icon: ImageResource) { stored = icon } }
        let x = S(.star)
        """
        #expect(images(source) == ["star"])
    }

    @Test("Distinguishes multiple positional parameters of different kinds")
    func multiplePositionalParameters() {
        let source = """
        struct S { let img: ImageResource; let col: ColorResource; init(_ img: ImageResource, _ col: ColorResource) { self.img = img; self.col = col } }
        let x = S(.cat, .brand)
        """
        #expect(images(source) == ["cat"])
        #expect(colors(source) == ["brand"])
    }

    @Test("Resolves a type whose name has a leading underscore")
    func underscorePrefixedType() {
        let source = """
        struct _InternalStyle { let icon: ImageResource }
        let x = _InternalStyle(icon: .star)
        """
        #expect(images(source) == ["star"])
    }

    @Test("Resolves a class initializer argument")
    func classInit() {
        let source = """
        final class S { let icon: ImageResource; init(icon: ImageResource) { self.icon = icon } }
        let x = S(icon: .star)
        """
        #expect(images(source) == ["star"])
    }

    @Test("Resolves an actor initializer argument")
    func actorInit() {
        let source = """
        actor S { let icon: ImageResource; init(icon: ImageResource) { self.icon = icon } }
        let x = S(icon: .star)
        """
        #expect(images(source) == ["star"])
    }

    // MARK: - Nested / inferred initializers

    @Test("Resolves the user's nested inferred .init example")
    func nestedInferredInit() {
        let source = """
        struct Test { let image: ImageResource; let text: String }
        struct Foo { let test: Test }
        let foo = Foo(test: .init(image: .cat, text: "AAA"))
        """
        #expect(images(source) == ["cat"])
    }

    @Test("Resolves a nested explicit-type init argument")
    func nestedExplicitInit() {
        let source = """
        struct Test { let image: ImageResource }
        struct Foo { let test: Test }
        let foo = Foo(test: Test(image: .cat))
        """
        #expect(images(source) == ["cat"])
    }

    @Test("Resolves .init through a typed binding annotation")
    func typedContextInit() {
        let source = """
        struct Test { let image: ImageResource }
        struct Foo { let test: Test }
        let x: Foo = .init(test: .init(image: .cat))
        """
        #expect(images(source) == ["cat"])
    }

    @Test("Resolves a nested-type initializer (Outer.Inner)")
    func nestedTypeInit() {
        let source = """
        struct Outer { struct Inner { let icon: ImageResource } }
        let x = Outer.Inner(icon: .star)
        """
        #expect(images(source) == ["star"])
    }

    // MARK: - Static factory methods

    @Test("Resolves a resource passed to an inferred static factory")
    func staticFactoryArgument() {
        let source = """
        struct Test { let image: ImageResource; let text: String }
        extension Test {
            static func image(_ image: ImageResource) -> Self { .init(image: image, text: "Default") }
        }
        struct Foo { let test: Test }
        let foo = Foo(test: .image(.frog))
        """
        #expect(images(source) == ["frog"])
    }

    @Test("Resolves a literal inside a Self-returning factory body")
    func factoryBodyLiteral() {
        let source = """
        struct Test { let image: ImageResource; let text: String }
        extension Test {
            static func text(_ text: String) -> Self { .init(image: .dog, text: text) }
        }
        """
        #expect(images(source) == ["dog"])
    }

    @Test("Resolves the full static-factory example to dog and frog")
    func staticFactoryFullExample() {
        let source = """
        struct Test {
            let image: ImageResource
            let text: String
        }

        extension Test {
            static func image(_ image: ImageResource) -> Self {
                .init(image: image, text: "Default")
            }

            static func text(_ text: String) -> Self {
                .init(image: .dog, text: text)
            }
        }

        struct Foo {
            let test: Test
        }

        let foo = Foo(test: .image(.frog))
        let bar = Foo(test: .text("bar"))
        """
        #expect(Set(images(source)) == ["dog", "frog"])
    }

    @Test("Resolves factories from a constrained protocol extension via an existential")
    func protocolExtensionFactories() {
        let source = """
        protocol TestProtocol {
            var image: ImageResource { get }
            var text: String { get }
        }

        struct Test: TestProtocol {
            let image: ImageResource
            let text: String
        }

        extension TestProtocol where Self == Test {
            static func image(_ image: ImageResource) -> Self {
                .init(image: image, text: "Default")
            }

            static func text(_ text: String) -> Self {
                .init(image: .dog, text: text)
            }
        }

        struct Foo {
            let test: any TestProtocol
        }

        let foo = Foo(test: .image(.frog))
        let bar = Foo(test: .text("bar"))
        """
        #expect(Set(images(source)) == ["dog", "frog"])
    }

    // MARK: - Exclusions

    @Test("A computed property is not treated as a memberwise label")
    func computedPropertyExcluded() {
        let source = """
        struct S { let icon: ImageResource; var derived: ImageResource { .x } }
        let s = S(derived: .y)
        """
        #expect(images(source).isEmpty)
    }

    @Test("A `let` with a default value is absent from the memberwise init")
    func letWithDefaultExcluded() {
        let source = """
        struct S { let b: ImageResource = .def }
        let s = S(b: .star)
        """
        #expect(images(source).isEmpty)
    }

    // MARK: - Negatives

    @Test("A non-resource type's init resolves nothing")
    func nonResourceInit() {
        let source = """
        struct Point { let x: Int; let y: Int }
        let p = Point(x: 1, y: 2)
        """
        #expect(usages(source).isEmpty)
    }

    @Test("A bare member in a String argument is not recorded")
    func stringArgumentIgnored() {
        let source = """
        struct Label { let text: String }
        let l = Label(text: .lonely)
        """
        #expect(usages(source).isEmpty)
    }

    @Test("A trailing closure argument contributes nothing")
    func trailingClosureIgnored() {
        let source = """
        struct S { let make: () -> Void }
        let x = S { print("hi") }
        """
        #expect(usages(source).isEmpty)
    }
}
