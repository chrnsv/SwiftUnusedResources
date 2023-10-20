import Foundation
import SwiftParser
import SwiftSyntax
import PathKit

class SwiftParser {
    func parse(
        _ path: Path,
        _ showWarnings: Bool
    ) throws -> [ExploreUsage] {
        let file = try String(contentsOf: path.url)
        let source = Parser.parse(source: file)
        let visitor = SourceVisitor(showWarnings: showWarnings, path.url, source)
        
        return visitor.usages
    }
}
