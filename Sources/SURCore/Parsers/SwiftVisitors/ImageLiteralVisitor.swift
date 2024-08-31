import Foundation
import SwiftSyntax

class ImageLiteralVisitor: SyntaxVisitor {
    private(set) var usages: [ExploreUsage] = []
    
    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        _ node: MacroExpansionExprSyntax
    ) {
        super.init(viewMode: viewMode)
        walk(node)
    }
    
    override func visit(_ node: LabeledExprSyntax) -> SyntaxVisitorContinueKind {
        if node.label?.text != "resourceName" {
            return .skipChildren
        }
        
        usages.append(.string(StringVisitor(node.expression).parse(), .image))
        
        return .skipChildren
    }
}
