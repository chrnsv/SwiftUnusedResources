import Foundation
import PathKit
import SwiftParser
import SwiftSyntax

class SwiftParser {
    private let showWarnings: Bool
    private let kinds: Set<ExploreKind>
    
    init(showWarnings: Bool, kinds: Set<ExploreKind>) {
        self.showWarnings = showWarnings
        self.kinds = kinds
    }
    
    func parse(
        _ path: Path
    ) throws -> [ExploreUsage] {
        let file = try String(contentsOf: path.url)
        let source = Parser.parse(source: file)
        let visitor = SourceVisitor(showWarnings: showWarnings, kinds: kinds, path.url, source)
        
        return visitor.usages
    }
}
