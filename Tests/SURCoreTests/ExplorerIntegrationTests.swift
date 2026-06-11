import Foundation
import PathKit
import Testing

@testable import SURCore

@Suite("Explorer end-to-end analysis of fixture projects")
struct ExplorerIntegrationTests {
    private func unusedNames(in fixture: FixtureProject, target: String) async throws -> Set<String> {
        let explorer = try Explorer(
            projectPath: fixture.projectPath,
            sourceRoot: fixture.root,
            target: target,
            showWarnings: false
        )

        try await explorer.explore()

        return Set(await explorer.storage.unused.map(\.name))
    }

    @Test("Reports an asset image that no source references")
    func unusedImageDetected() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["star", "lonely"])
        try fixture.addSource("Main.swift", """
        import UIKit

        let image = UIImage(named: "star")
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Main.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["lonely"])
    }

    @Test("Does not report an image used via a SwiftUI literal")
    func usedImageNotReported() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["star"])
        try fixture.addSource("Main.swift", """
        import SwiftUI

        let view = Image("star")
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Main.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused.isEmpty)
    }

    @Test("Does not report a color used via its generated symbol")
    func colorUsedViaGeneratedSymbol() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", colorSets: ["brandColor"])
        try fixture.addSource("Main.swift", """
        import SwiftUI

        let color: ColorResource = .brand
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Main.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused.isEmpty)
    }

    @Test("Honors exclude.resources from sur.yml")
    func excludedResourceNotReported() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["lonely"])
        try fixture.setSurYML("""
        exclude:
          resources:
            - lonely
        """)
        try fixture.write(targets: [
            .init(name: "App", resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused.isEmpty)
    }

    @Test("Processes only the requested target")
    func targetFiltering() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("AAssets.xcassets", imageSets: ["aOnly"])
        try fixture.addAssetCatalog("BAssets.xcassets", imageSets: ["bOnly"])
        try fixture.write(targets: [
            .init(name: "TargetA", resources: ["AAssets.xcassets"]),
            .init(name: "TargetB", resources: ["BAssets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "TargetA")
        #expect(unused == ["aOnly"])
    }

    @Test("Counts resource usage declared in a xib")
    func xibUsageCounted() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["header", "lonely"])
        try fixture.addXib("View.xib", """
        <?xml version="1.0" encoding="UTF-8"?>
        <document type="com.apple.InterfaceBuilder3.CocoaTouch.XIB.XMLIB" version="3.0" \
        toolsVersion="22155" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES">
            <resources>
                <image name="header" width="100" height="100"/>
            </resources>
        </document>
        """)
        try fixture.write(targets: [
            .init(name: "App", resources: ["Assets.xcassets", "View.xib"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["lonely"])
    }

    @Test("Counts an image passed to a struct init defined in another file")
    func crossFileStructInitUsage() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["star", "lonely"])
        try fixture.addSource("Style.swift", """
        struct CardStyle { let icon: ImageResource }
        """)
        try fixture.addSource("Use.swift", """
        let card = CardStyle(icon: .star)
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Style.swift", "Use.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["lonely"])
    }

    @Test("Counts an image nested in an inferred .init across files")
    func crossFileNestedInitUsage() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["cat", "lonely"])
        try fixture.addSource("Models.swift", """
        struct Test { let image: ImageResource; let text: String }
        struct Foo { let test: Test }
        """)
        try fixture.addSource("Use.swift", """
        let foo = Foo(test: .init(image: .cat, text: "AAA"))
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Models.swift", "Use.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["lonely"])
    }

    @Test("Counts a color passed to a struct init across files")
    func crossFileColorInitUsage() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", colorSets: ["brand", "unusedColor"])
        try fixture.addSource("Theme.swift", """
        struct Theme { let bg: ColorResource; let name: String }
        """)
        try fixture.addSource("Use.swift", """
        let theme = Theme(bg: .brand, name: "x")
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Theme.swift", "Use.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["unusedColor"])
    }

    @Test("Counts images via static factories and factory bodies across files")
    func crossFileStaticFactoryUsage() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["dog", "frog", "lonely"])
        try fixture.addSource("Test.swift", """
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
        """)
        try fixture.addSource("Use.swift", """
        let foo = Foo(test: .image(.frog))
        let bar = Foo(test: .text("bar"))
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Test.swift", "Use.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["lonely"])
    }

    @Test("Counts images via a constrained protocol extension across files")
    func crossFileProtocolFactoryUsage() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["dog", "frog", "lonely"])
        try fixture.addSource("Test.swift", """
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
        """)
        try fixture.addSource("Use.swift", """
        let foo = Foo(test: .image(.frog))
        let bar = Foo(test: .text("bar"))
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Test.swift", "Use.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["lonely"])
    }

    @Test("Does not count a bare member passed to a String parameter")
    func stringParameterDoesNotCount() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addAssetCatalog("Assets.xcassets", imageSets: ["lonely"])
        try fixture.addSource("Main.swift", """
        struct Label { let text: String }
        let label = Label(text: .lonely)
        """)
        try fixture.write(targets: [
            .init(name: "App", sources: ["Main.swift"], resources: ["Assets.xcassets"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["lonely"])
    }

    @Test("Reports an unused loose image file")
    func looseImageReported() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }

        try fixture.addLooseImage("banner.png")
        try fixture.write(targets: [
            .init(name: "App", resources: ["banner.png"]),
        ])

        let unused = try await unusedNames(in: fixture, target: "App")
        #expect(unused == ["banner"])
    }
}
