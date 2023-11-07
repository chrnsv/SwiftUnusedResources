import Foundation
import SwiftSyntax

class StringVisitor: SyntaxVisitor {
    var value: String = ""

    init(viewMode: SyntaxTreeViewMode = .sourceAccurate, _ node: SyntaxProtocol) {
        super.init(viewMode: viewMode)
        node.children(viewMode: viewMode).forEach { syntax in
            walk(syntax)
        }
    }
    
    func parse() -> String {
        return value
    }
    
    override func visit(_ node: StringSegmentSyntax) -> SyntaxVisitorContinueKind {
        value += node.content.text
        return .skipChildren
    }
    
    override func visit(_ node: LabeledExprSyntax) -> SyntaxVisitorContinueKind {
        value += StringVisitor(node).parse()
        return .skipChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        value += ".*"
        return .skipChildren
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        value += ".*"
        return .skipChildren
    }
    
    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        value += ".*"
        return .skipChildren
    }
    
    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        let first = StringVisitor(node.thenExpression).parse()
        let second = StringVisitor(node.elseExpression).parse()
        
        if first == ".*" || second == ".*" {
            value += ".*"
            return .skipChildren
        }
        
        if first.isEmpty && !second.isEmpty {
            value += "(?:\(second))?"
            return .skipChildren
        }
        
        if !first.isEmpty && second.isEmpty {
            value += "(?:\(first))?"
            return .skipChildren
        }
        
        value += "(?:\(first)|\(second))"
        
        return .skipChildren
    }
}
