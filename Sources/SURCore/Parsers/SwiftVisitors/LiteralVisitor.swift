import Foundation
import SwiftSyntax

class LiteralVisitor: SyntaxVisitor {
    private(set) var usages: [ExploreUsage] = []
    private let kind: ExploreKind
    
    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        _ node: MacroExpansionExprSyntax,
        kind: ExploreKind
    ) {
        self.kind = kind
        
        super.init(viewMode: viewMode)
        
        walk(node)
    }
    
    override func visit(_ node: LabeledExprSyntax) -> SyntaxVisitorContinueKind {
        if node.label?.text != "resourceName" {
            return .skipChildren
        }
        
        usages.append(.string(StringVisitor(node.expression).parse(), kind))
        
        return .skipChildren
    }
}
