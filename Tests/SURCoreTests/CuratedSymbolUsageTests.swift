import Foundation
import Testing

@testable import SURCore

@Suite("Curated symbol detection (modifiers, setters, properties)")
struct CuratedSymbolUsageTests {
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

    // MARK: - SwiftUI modifiers

    @Test("Detects colors passed to SwiftUI modifiers")
    func swiftUIModifiers() {
        #expect(generatedIdentifiers("let v = text.foregroundColor(.brand)", kind: .color) == ["brand"])
        #expect(generatedIdentifiers("let v = view.tint(.accent)", kind: .color) == ["accent"])
        #expect(generatedIdentifiers("let v = view.foregroundStyle(.brand)", kind: .color) == ["brand"])
        #expect(generatedIdentifiers("let v = view.background(.brand)", kind: .color) == ["brand"])
        #expect(generatedIdentifiers("let v = row.listRowSeparatorTint(.brand)", kind: .color) == ["brand"])
        #expect(generatedIdentifiers("let v = row.listItemTint(.brand)", kind: .color) == ["brand"])
    }

    @Test("Detects color in labeled color: argument")
    func labeledColorArgument() {
        let ids = generatedIdentifiers("let v = view.shadow(color: .glow, radius: 4)", kind: .color)
        #expect(ids == ["glow"])
    }

    @Test("Detects color in a modifier chain")
    func modifierChain() {
        let source = """
        let v = Text("hi").foregroundColor(.brand).padding()
        """
        let ids = generatedIdentifiers(source, kind: .color)
        #expect(ids == ["brand"])
    }

    @Test("Detects the root of a chained modifier argument")
    func chainedModifierArgument() {
        let ids = generatedIdentifiers("let v = view.foregroundColor(.brand.opacity(0.5))", kind: .color)
        #expect(ids == ["brand"])
    }

    @Test("Ignores members inside view-builder arguments of curated calls")
    func ignoresViewBuilderArguments() {
        let source = """
        let v = view.background(VStack(alignment: .leading) { Text(t).font(.title) })
        """
        let ids = generatedIdentifiers(source, kind: .color)
        #expect(ids.isEmpty)
    }

    @Test("Detects both ternary branches in a modifier argument")
    func ternaryModifierArgument() {
        let ids = generatedIdentifiers("let v = view.foregroundColor(flag ? .a : .b)", kind: .color)
        #expect(Set(ids) == ["a", "b"])
    }

    @Test("Modifier arguments are recorded as colors only")
    func modifierKindIsColor() {
        let ids = generatedIdentifiers("let v = view.foregroundColor(.brand)", kind: .image)
        #expect(ids.isEmpty)
    }

    // MARK: - UIKit setters

    @Test("Detects color in setTitleColor, ignoring the state label")
    func setTitleColor() {
        let source = "button.setTitleColor(.brand, for: .normal)"
        let ids = generatedIdentifiers(source, kind: .color)
        #expect(ids == ["brand"])
        #expect(!ids.contains("normal"))
    }

    @Test("Detects image in setImage, ignoring the state label")
    func setImage() {
        let ids = generatedIdentifiers("button.setImage(.star, for: .normal)", kind: .image)
        #expect(ids == ["star"])
        #expect(!ids.contains("normal"))
    }

    @Test("Detects images in slider and page-control setters")
    func sliderAndPageControlSetters() {
        #expect(generatedIdentifiers("slider.setThumbImage(.knob, for: .normal)", kind: .image) == ["knob"])
        #expect(generatedIdentifiers("pages.setIndicatorImage(.dot, forPage: 0)", kind: .image) == ["dot"])
    }

    // MARK: - UIKit property assignments

    @Test("Detects assets assigned to well-known UIKit properties")
    func propertyAssignments() {
        #expect(generatedIdentifiers("label.textColor = .brand", kind: .color) == ["brand"])
        #expect(generatedIdentifiers("view.backgroundColor = .bg", kind: .color) == ["bg"])
        #expect(generatedIdentifiers("slider.minimumTrackTintColor = .track", kind: .color) == ["track"])
        #expect(generatedIdentifiers("tabBar.unselectedItemTintColor = .dim", kind: .color) == ["dim"])
        #expect(generatedIdentifiers("imageView.image = .star", kind: .image) == ["star"])
        #expect(generatedIdentifiers("imageView.highlightedImage = .hl", kind: .image) == ["hl"])
        #expect(generatedIdentifiers("progressView.progressImage = .bar", kind: .image) == ["bar"])
    }

    @Test("Detects asset assigned to a self-qualified property")
    func selfQualifiedAssignment() {
        let ids = generatedIdentifiers("self.tintColor = .accent", kind: .color)
        #expect(ids == ["accent"])
    }

    @Test("Detects asset assigned through a chained base")
    func chainedBaseAssignment() {
        let ids = generatedIdentifiers("cell.titleLabel.textColor = .brand", kind: .color)
        #expect(ids == ["brand"])
    }

    @Test("Detects both ternary branches in a property assignment")
    func ternaryAssignment() {
        let ids = generatedIdentifiers("label.textColor = flag ? .a : .b", kind: .color)
        #expect(Set(ids) == ["a", "b"])
    }

    @Test("Ignores assignment to a bare local that shares a curated property name")
    func ignoresBareLocalAssignment() {
        let source = """
        func render() {
            var image: Avatar = .placeholder
            image = .remote
        }
        """
        let ids = generatedIdentifiers(source, kind: .image)
        #expect(ids.isEmpty)
    }

    @Test("Ignores calls outside the curated modifier list")
    func ignoresUncuratedCalls() {
        #expect(generatedIdentifiers("let v = view.padding(.horizontal)", kind: .color).isEmpty)
        #expect(generatedIdentifiers("let v = view.padding(.horizontal)", kind: .image).isEmpty)
    }

    @Test("Ignores control labels of curated calls")
    func ignoresControlLabels() {
        let ids = generatedIdentifiers("let v = view.background(alignment: .top) { overlay }", kind: .color)
        #expect(!ids.contains("top"))
    }

    @Test("Ignores assignment to properties outside the curated list")
    func ignoresUncuratedProperty() {
        let ids = generatedIdentifiers("foo.delegate = .none", kind: .image)
        #expect(ids.isEmpty)
    }

    // MARK: - Custom symbol tables (sur.yml `symbols`)

    @Test("Detects arguments of a user-supplied call name")
    func customCallTable() {
        let parser = SwiftParser(
            showWarnings: false,
            kinds: [.color],
            memberCallKinds: ["neonGlow": .color]
        )
        let usages = parser.parse(source: "let v = view.neonGlow(.brandPink)")
        #expect(usages == [.generated("brandPink", .color)])

        // The default tables do not know `neonGlow`.
        #expect(generatedIdentifiers("let v = view.neonGlow(.brandPink)", kind: .color).isEmpty)
    }

    @Test("Detects assignment to a user-supplied property name")
    func customPropertyTable() {
        let parser = SwiftParser(
            showWarnings: false,
            kinds: [.color],
            propertyKinds: ["brandColor": .color]
        )
        let usages = parser.parse(source: "theme.brandColor = .accent")
        #expect(usages == [.generated("accent", .color)])

        #expect(generatedIdentifiers("theme.brandColor = .accent", kind: .color).isEmpty)
    }

    @Test("Decodes the symbols section of a configuration")
    func configurationSymbols() throws {
        let json = """
        {
            "symbols": {
                "calls": { "color": ["neonGlow"], "image": ["setCustomIcon"] },
                "properties": { "color": ["brandColor"] }
            }
        }
        """
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        #expect(configuration.symbols?.calls?.color == ["neonGlow"])
        #expect(configuration.symbols?.calls?.image == ["setCustomIcon"])
        #expect(configuration.symbols?.properties?.color == ["brandColor"])
        #expect(configuration.symbols?.properties?.image == nil)
    }
}
