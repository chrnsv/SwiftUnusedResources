import Foundation
import Testing
import Yams

@testable import SURCore

@Suite("sur.yml configuration decoding")
struct ConfigurationTests {
    private func decode(_ yaml: String) throws -> Configuration {
        try YAMLDecoder().decode(Configuration.self, from: yaml)
    }

    // MARK: - Full configuration

    @Test("Decodes a complete configuration")
    func fullConfiguration() throws {
        let configuration = try decode("""
        exclude:
          sources:
            - Sources/Generated/*
            - Pods/**
          resources:
            - placeholder
          assets:
            - ThirdPartyAssets
        kinds:
          - image
        symbols:
          calls:
            color:
              - neonGlow
            image:
              - setCustomIcon
          properties:
            color:
              - brandColor
            image:
              - profileImage
        """)

        #expect(configuration.exclude?.sources == ["Sources/Generated/*", "Pods/**"])
        #expect(configuration.exclude?.resources == ["placeholder"])
        #expect(configuration.exclude?.assets == ["ThirdPartyAssets"])
        #expect(configuration.kinds == [.image])
        #expect(configuration.symbols?.calls?.color == ["neonGlow"])
        #expect(configuration.symbols?.calls?.image == ["setCustomIcon"])
        #expect(configuration.symbols?.properties?.color == ["brandColor"])
        #expect(configuration.symbols?.properties?.image == ["profileImage"])
    }

    // MARK: - Partial configurations

    @Test("Leaves unspecified sections nil")
    func partialConfiguration() throws {
        let configuration = try decode("""
        exclude:
          resources:
            - placeholder
        """)

        #expect(configuration.exclude?.resources == ["placeholder"])
        #expect(configuration.exclude?.sources == nil)
        #expect(configuration.exclude?.assets == nil)
        #expect(configuration.kinds == nil)
        #expect(configuration.symbols == nil)
    }

    @Test("Decodes both kinds")
    func bothKinds() throws {
        let configuration = try decode("""
        kinds:
          - image
          - color
        """)

        #expect(configuration.kinds == [.image, .color])
    }

    @Test("Leaves a null exclude section nil")
    func nullExclude() throws {
        let configuration = try decode("""
        exclude:
        """)

        #expect(configuration.exclude == nil)
    }

    @Test("Ignores unknown top-level keys")
    func unknownKeys() throws {
        let configuration = try decode("""
        unknown_option: true
        kinds:
          - color
        """)

        #expect(configuration.kinds == [.color])
    }

    // MARK: - Invalid configurations

    @Test("Throws for an unknown kind value")
    func invalidKind() {
        #expect(throws: DecodingError.self) {
            try decode("""
            kinds:
              - gradient
            """)
        }
    }

    @Test("Throws for an empty document, so Explorer falls back to defaults")
    func emptyDocument() {
        #expect(throws: (any Error).self) {
            try decode("")
        }
    }
}
