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
        let file = try String(contentsOf: path)
        return parse(source: file, at: path)
    }

    func parse(
        source: String,
        at path: URL = URL(fileURLWithPath: "<source>")
    ) -> [ExploreUsage] {
        let tree = Parser.parse(source: source)
        let visitor = SourceVisitor(
            showWarnings: showWarnings,
            kinds: kinds,
            memberCallKinds: memberCallKinds,
            propertyKinds: propertyKinds,
            path,
            tree
        )

        return visitor.usages
    }
}
