import Foundation
import SwiftSyntax

final class SourceVisitor: SyntaxVisitor {
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
            .compactMap { $0.toAsset() }
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
            .compactMap { $0.toAsset() }
            .compactMap { findR(in: node, with: $0) ?? findGeneratedAsset(in: node, with: $0) }
        
        guard !newUsages.isEmpty else {
            return .visitChildren
        }
        
        usages.append(contentsOf: newUsages)
        
        return .skipChildren
    }
    
    private func findR(
        in node: MemberAccessExprSyntax,
        with kind: ExploreKind
    ) -> ExploreUsage? {
        switch kind {
        case .asset:
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
            
        case .string:
            guard
                let possibleFileName = node.base?.as(MemberAccessExprSyntax.self),
                let possibleKind = possibleFileName.base?.as(MemberAccessExprSyntax.self),
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
}

private extension ExploreKind {
    init?(literal: String) {
        switch literal {
        case "imageLiteral": self = .asset(.image)
        case "colorLiteral": self = .asset(.color)
        default: return nil
        }
    }
}

extension SourceVisitor {
    private func findR(
        in node: DeclReferenceExprSyntax,
        with kind: ExploreKind.Asset
    ) -> ExploreUsage? {
        guard node.baseName.text == "R" else {
            return nil
        }
        
        let members = members(in: node).dropFirst()
        
        guard members.first == kind.rawValue, let name = members.dropFirst().first else {
            return nil
        }
        
        return .rswift(name, .asset(kind))
    }
    
    private func findGeneratedAsset(
        in node: DeclReferenceExprSyntax,
        with kind: ExploreKind.Asset
    ) -> ExploreUsage? {
        guard [kind.uiClassName, kind.swiftUIClassName].contains(node.baseName.text) else {
            return nil
        }
        
        if let parent = node.parent?.as(FunctionCallExprSyntax.self) {
            guard parent.arguments.count == 1, let member = parent.arguments.last?.expression.as(MemberAccessExprSyntax.self) else {
                return nil
            }
            
            return .generated(member.declName.baseName.text, .asset(kind))
        }
        else {
            let members = members(in: node)
            
            guard members.count == 2, let name = members.last else {
                return nil
            }
            
            return .generated(name, .asset(kind))
        }
    }
    
    private func members(in node: DeclReferenceExprSyntax) -> some RandomAccessCollection<String> {
        guard let parent = node.parent?.as(MemberAccessExprSyntax.self) else {
            return []
        }
        
        let usage = sequence(first: parent) { $0.parent?.as(MemberAccessExprSyntax.self) }
            .toArray()
            .last
        
        guard let usage else {
            return []
        }
        
        let visitor = MemberVisitor(viewMode: viewMode)
        
        visitor.walk(usage)
        
        return visitor.members
    }
}

private extension ExploreKind.Asset {
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

private extension Sequence {
    func toArray() -> [Element] { Array(self) }
}
