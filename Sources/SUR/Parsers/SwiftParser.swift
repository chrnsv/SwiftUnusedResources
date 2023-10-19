import Foundation
import SwiftParser
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
        let file = try String(contentsOf: path.url)
        let source = Parser.parse(source: file)
        SourceVisitor(showWarnings: showWarnings, path.url, source, register)
    }
}
