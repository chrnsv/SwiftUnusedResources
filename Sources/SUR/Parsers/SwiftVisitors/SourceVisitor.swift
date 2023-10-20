import Foundation
import SwiftSyntax

class SourceVisitor: SyntaxVisitor {
    private let url: URL
    private let showWarnings: Bool
    private var hasUIKit = false
    private var hasSwiftUI = false
    
    private(set) var usages: [ExploreUsage] = []
    
    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        showWarnings: Bool,
        _ url: URL,
        _ node: SourceFileSyntax
    ) {
        self.url = url
        self.showWarnings = showWarnings
        
        super.init(viewMode: viewMode)
        walk(node)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // TODO: get import name without .description
        let imp = node.path.description

        if (imp == "UIKit" || imp == "WatchKit") {
            hasUIKit = true
        }
        else if (imp == "SwiftUI") {
            hasSwiftUI = true
        }

        return .skipChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard
            let base1 = node.base,
            base1.syntaxNodeType == MemberAccessExprSyntax.self,
            let base1x = MemberAccessExprSyntax(base1._syntaxNode),
            base1x.declName.baseName.text == "image",
            let base2 = base1x.base,
            base2.syntaxNodeType == DeclReferenceExprSyntax.self,
            let base2x = DeclReferenceExprSyntax(base2._syntaxNode),
            base2x.baseName.text == "R"
        else {
            return .visitChildren
        }
        
        let name = node.declName.baseName.text
        
        usages.append(.rswift(name))
        
        return .skipChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let visitor = FuncCallVisitor(url, node, uiKit: hasUIKit, swiftUI: hasSwiftUI, showWarnings: showWarnings)
        usages.append(contentsOf: visitor.usages)

        return super.visit(node)
    }
    
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        if (node.macroName.text != "imageLiteral") {
            return .skipChildren
        }

        let visitor = ImageLiteralVisitor(node)
        usages.append(contentsOf: visitor.usages)

        return .skipChildren
    }
}
