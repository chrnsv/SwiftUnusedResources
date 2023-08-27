import Foundation
import SwiftSyntax

class ImageLiteralVisitor: SyntaxVisitor {
    private let register: ImageRegister
    
    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        _ node: MacroExpansionExprSyntax,
        _ register: @escaping ImageRegister
    ) {
        self.register = register
        super.init(viewMode: viewMode)
        walk(node)
    }
    
    override func visit(_ node: TupleExprElementSyntax) -> SyntaxVisitorContinueKind {
        if (node.label?.text != "resourceName") {
            return .skipChildren
        }
        
        register(.string(StringVisitor(node.expression).parse()))
        
        return .skipChildren
    }
}

