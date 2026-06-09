import Foundation
import SwiftParser
import SwiftSyntax

struct SwiftParser: Sendable {
    private let showWarnings: Bool
    private let kinds: Set<ExploreKind>
    
    init(showWarnings: Bool, kinds: Set<ExploreKind>) {
        self.showWarnings = showWarnings
        self.kinds = kinds
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
        let visitor = SourceVisitor(showWarnings: showWarnings, kinds: kinds, path, tree)

        return visitor.usages
    }
}
