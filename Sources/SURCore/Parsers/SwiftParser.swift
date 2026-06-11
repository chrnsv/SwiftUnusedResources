import Foundation
import SwiftParser
import SwiftSyntax

struct SwiftParser: Sendable {
    private let showWarnings: Bool
    private let kinds: Set<ExploreKind>
    private let memberCallKinds: [String: ExploreKind]
    private let propertyKinds: [String: ExploreKind]

    init(
        showWarnings: Bool,
        kinds: Set<ExploreKind>,
        memberCallKinds: [String: ExploreKind] = SourceVisitor.defaultMemberCallKinds,
        propertyKinds: [String: ExploreKind] = SourceVisitor.defaultPropertyKinds
    ) {
        self.showWarnings = showWarnings
        self.kinds = kinds
        self.memberCallKinds = memberCallKinds
        self.propertyKinds = propertyKinds
    }

    func parse(
        _ path: URL
    ) throws -> [ExploreUsage] {
        try parseDetailed(path).usages
    }

    func parse(
        source: String,
        at path: URL = URL(fileURLWithPath: "<source>")
    ) -> [ExploreUsage] {
        parseDetailed(source: source, at: path).usages
    }

    /// Parses a file, returning not just the proven usages but also the initializer signatures
    /// it declares and the initializer call sites awaiting cross-file resolution.
    func parseDetailed(
        _ path: URL
    ) throws -> SwiftParseResult {
        let file = try String(contentsOf: path)
        return parseDetailed(source: file, at: path)
    }

    func parseDetailed(
        source: String,
        at path: URL = URL(fileURLWithPath: "<source>")
    ) -> SwiftParseResult {
        let tree = Parser.parse(source: source)
        let visitor = SourceVisitor(
            showWarnings: showWarnings,
            kinds: kinds,
            memberCallKinds: memberCallKinds,
            propertyKinds: propertyKinds,
            path,
            tree
        )

        return SwiftParseResult(
            usages: visitor.usages,
            typeRegistry: visitor.typeRegistry,
            pendingInits: visitor.pendingInits
        )
    }
}
