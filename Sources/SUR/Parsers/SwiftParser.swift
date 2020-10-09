import Foundation
import SwiftSyntax
import PathKit

typealias ImageRegister = (ExploreUsage) -> ()

class SwiftParser {
    @discardableResult
    init(_ path: Path, _ register: @escaping ImageRegister) throws {
        let source = try SyntaxParser.parse(path.url)
        SourceVisitor(path.url, source, register)
    }
}
