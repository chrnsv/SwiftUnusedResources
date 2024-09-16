import Foundation
import SwiftSyntax

class SourceVisitor: SyntaxVisitor {
    private let url: URL
    private let showWarnings: Bool
    private let kinds: Set<ExploreKind>
    private var hasUIKit = false
    private var hasSwiftUI = false
    
    private(set) var usages: [ExploreUsage] = []
    
    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        showWarnings: Bool,
        kinds: Set<ExploreKind>,
        _ url: URL,
        _ node: SourceFileSyntax
    ) {
        self.url = url
        self.showWarnings = showWarnings
        self.kinds = kinds
        
        super.init(viewMode: viewMode)
        walk(node)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // TODO: get import name without .description
        let imp = node.path.description

        if imp == "UIKit" || imp == "WatchKit" {
            hasUIKit = true
        }
        else if imp == "SwiftUI" {
            hasSwiftUI = true
        }

        return .skipChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let newUsages = kinds
            .compactMap { findR(in: node, with: $0) }
        
        guard !newUsages.isEmpty else {
            return .visitChildren
        }
        
        usages.append(contentsOf: newUsages)
        
        return .skipChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let newUsages = kinds
            .map { FuncCallVisitor(url, node, kind: $0, uiKit: hasUIKit, swiftUI: hasSwiftUI, showWarnings: showWarnings) }
            .flatMap { $0.usages }
        
        usages.append(contentsOf: newUsages)

        return super.visit(node)
    }
    
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        guard let kind = ExploreKind(literal: node.macroName.text) else {
            return .skipChildren
        }
        
        let visitor = LiteralVisitor(node, kind: kind)
        usages.append(contentsOf: visitor.usages)

        return .skipChildren
    }
    
    private func findR(
        in node: MemberAccessExprSyntax,
        with kind: ExploreKind
    ) -> ExploreUsage? {
        guard
            let possibleKind = node.base?.as(MemberAccessExprSyntax.self),
            possibleKind.declName.baseName.text == kind.rawValue,
            let possibleR = possibleKind.base?.as(DeclReferenceExprSyntax.self),
            possibleR.baseName.text == "R"
        else {
            return nil
        }
        
        let name = node.declName.baseName.text
        
        return .rswift(name, kind)
    }
}

private extension ExploreKind {
    init?(literal: String) {
        switch literal {
        case "imageLiteral": self = .image
        case "colorLiteral": self = .color
        default: return nil
        }
    }
}
