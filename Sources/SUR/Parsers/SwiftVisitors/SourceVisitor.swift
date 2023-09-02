import Foundation
import SwiftSyntax

class SourceVisitor: SyntaxVisitor {
    private let url: URL
    private let register: ImageRegister
    private let showWarnings: Bool
    private var hasUIKit = false
    private var hasSwiftUI = false
    
    
    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        showWarnings: Bool,
        _ url: URL,
        _ node: SourceFileSyntax,
        _ register: @escaping ImageRegister
    ) {
        self.url = url
        self.register = register
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
            base1x.name.text == "image",
            let base2 = base1x.base,
            base2.syntaxNodeType == IdentifierExprSyntax.self,
            let base2x = IdentifierExprSyntax(base2._syntaxNode),
            base2x.identifier.text == "R"
        else {
            return .visitChildren
        }
        
        let name = node.name.text
        
        register(.rswift(name))
        
        return .skipChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        FuncCallVisitor(url, node, register, uiKit: hasUIKit, swiftUI: hasSwiftUI, showWarnings: showWarnings)

        return super.visit(node)
    }
    
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        if (node.macro.text != "imageLiteral") {
            return .skipChildren
        }

        ImageLiteralVisitor(node, register)

        return .skipChildren
    }
}
