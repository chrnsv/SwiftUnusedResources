import Foundation
import SwiftSyntax

class SourceVisitor: SyntaxVisitor {
    private let url: URL
    private let register: ImageRegister
    private var hasUIKit = false
    private var hasSwiftUI = false
    
    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        _ url: URL,
        _ node: SourceFileSyntax,
        _ register: @escaping ImageRegister
    ) {
        self.url = url
        self.register = register
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
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        FuncCallVisitor(url, node, register, uiKit: hasUIKit, swiftUI: hasSwiftUI)

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
