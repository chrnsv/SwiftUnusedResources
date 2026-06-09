import Foundation
import SwiftOperators
import SwiftSyntax

final class StringVisitor: SyntaxVisitor {
    var value: String = ""

    init(viewMode: SyntaxTreeViewMode = .sourceAccurate, _ node: SyntaxProtocol) {
        super.init(viewMode: viewMode)

        node.children(viewMode: viewMode).forEach { syntax in
            walk(syntax)
        }
    }

    /// Walks `expression` itself (not just its children) so that bare
    /// references like the branches of `flag ? "a" : name` count as dynamic.
    private init(viewMode: SyntaxTreeViewMode = .sourceAccurate, expression: ExprSyntax) {
        super.init(viewMode: viewMode)

        walk(expression)
    }
    
    func parse() -> String {
        value
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
        if node.parent?.is(MemberAccessExprSyntax.self) != true {
            value += ".*"
        }
        
        return .skipChildren
    }
    
    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        value += ".*"
        return .skipChildren
    }
    
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        // The parser leaves operators unfolded, so ternaries arrive as flat
        // sequences; fold them to make the TernaryExprSyntax handling reachable.
        let folded = OperatorTable.standardOperators.foldAll(node) { _ in }

        guard !folded.is(SequenceExprSyntax.self) else {
            return .visitChildren
        }

        walk(folded)

        return .skipChildren
    }

    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        let first = StringVisitor(expression: node.thenExpression).parse()
        let second = StringVisitor(expression: node.elseExpression).parse()
        
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
