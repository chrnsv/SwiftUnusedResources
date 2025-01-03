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
        let source = Parser.parse(source: file)
        let visitor = SourceVisitor(showWarnings: showWarnings, kinds: kinds, path, source)
        
        return visitor.usages
    }
}
