import Foundation
import PathKit
import SwiftParser
import SwiftSyntax

class SwiftParser {
    private let showWarnings: Bool
    
    init(showWarnings: Bool) {
        self.showWarnings = showWarnings
    }
    
    func parse(
        _ path: Path
    ) throws -> [ExploreUsage] {
        let file = try String(contentsOf: path.url)
        let source = Parser.parse(source: file)
        let visitor = SourceVisitor(showWarnings: showWarnings, path.url, source)
        
        return visitor.usages
    }
}
