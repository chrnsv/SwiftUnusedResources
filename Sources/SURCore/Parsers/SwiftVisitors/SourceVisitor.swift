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
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let newUsages = kinds
            .compactMap {
                findR(in: node, with: $0)
                ?? findGeneratedAssetExtension(in: node, with: $0)
            }
        
        guard !newUsages.isEmpty else {
            return .visitChildren
        }
        
        usages.append(contentsOf: newUsages)
        
        return .skipChildren
    }
    
    private func findR(
        in node: DeclReferenceExprSyntax,
        with kind: ExploreKind
    ) -> ExploreUsage? {
        guard node.baseName.text == "R" else {
            return nil
        }
        
        guard let parent = node.parent?.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        
        let usage = sequence(first: parent) { $0.parent?.as(MemberAccessExprSyntax.self) }
            .array()
            .last
        
        guard let usage else {
            return nil
        }
        
        let visitor = MemberVisitor(viewMode: viewMode)
        
        visitor.walk(usage)
        
        let members = visitor.members.dropFirst()
        
        guard members.first == kind.rawValue, let name = members.dropFirst().first else {
            return nil
        }
        
        return .rswift(name, kind)
    }
    
    private func findGeneratedAssetExtension(
        in node: DeclReferenceExprSyntax,
        with kind: ExploreKind
    ) -> ExploreUsage? {
        guard [kind.uiClassName, kind.swiftUIClassName].contains(node.baseName.text) else {
            return nil
        }
        
        if let parent = node.parent?.as(MemberAccessExprSyntax.self) {
            let usage = sequence(first: parent) { $0.parent?.as(MemberAccessExprSyntax.self) }
                .array()
                .last
            
            guard let usage else {
                return nil
            }
            
            let visitor = MemberVisitor(viewMode: viewMode)
            
            visitor.walk(usage)
            
            let members = visitor.members
            
            guard members.count == 2, let name = members.last else {
                return nil
            }
            
            return .generated(name, kind)
        }
        else if let parent = node.parent?.as(FunctionCallExprSyntax.self) {
            guard parent.arguments.count == 1, let member = parent.arguments.last?.expression.as(MemberAccessExprSyntax.self) else {
                return nil
            }
            
            return .generated(member.declName.baseName.text, kind)
        }
        
        return nil
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

private extension SourceVisitor {
    final class MemberVisitor: SyntaxVisitor {
        private(set) var members: [String] = []
        
        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            members.append(node.baseName.text)
            
            return super.visit(node)
        }
    }
}
