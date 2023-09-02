import Foundation
import SwiftSyntaxParser
import SwiftSyntax
import PathKit

typealias ImageRegister = (ExploreUsage) -> ()

class SwiftParser {
    @discardableResult
    init(
        _ path: Path,
        _ showWarnings: Bool,
        _ register: @escaping ImageRegister
    ) throws {
        let source = try SyntaxParser.parse(path.url)
        SourceVisitor(showWarnings: showWarnings, path.url, source, register)
    }
}
