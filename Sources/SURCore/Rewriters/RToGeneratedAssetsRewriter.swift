import Foundation
import SwiftParser
import SwiftSyntax

public struct RToGeneratedAssetsRewriter: FileRewriter {
    public init() {}
    
    /// Rewrites the given Swift source file in-place.
    /// - Returns: true if the file changed.
    @discardableResult
    public func rewrite(fileAt url: URL, dryRun: Bool) throws -> Bool {
        let original = try String(contentsOf: url)
        let source = Parser.parse(source: original)
        let rewriter = Rewriter()
        var transformed: Syntax = rewriter.rewrite(source)

        // If we performed any UIKit replacements and UIKit isn't imported, insert it on the transformed file.
        if rewriter.changedModules.contains(.uiKit) {
            let transformedFile = transformed.as(SourceFileSyntax.self) ?? source
            if !ImportHelpers.hasImport(named: "UIKit", in: transformedFile) {
                let withImport = ImportHelpers.insertImport(named: "UIKit", into: transformedFile)
                transformed = Syntax(withImport)
            }
        }

        // If we performed any SwiftUI replacements and SwiftUI isn't imported, insert it too.
        if rewriter.changedModules.contains(.swiftUI) {
            let transformedFile = transformed.as(SourceFileSyntax.self) ?? source
            if !ImportHelpers.hasImport(named: "SwiftUI", in: transformedFile) {
                let withImport = ImportHelpers.insertImport(named: "SwiftUI", into: transformedFile)
                transformed = Syntax(withImport)
            }
        }

        let newText = transformed.description
        
        guard newText != original else {
            return false
        }
        
        if !dryRun {
            try newText.write(to: url, atomically: true, encoding: .utf8)
        }
        
        return true
    }
}

private extension RToGeneratedAssetsRewriter {
    /// Rewriter that converts `R.image.<identifier>()!` -> `UIImage(resource: .<identifier>)`.
    final class Rewriter: SyntaxRewriter {
        private(set) var changedModules: Set<Module> = []

        override func visit(_ node: OptionalChainingExprSyntax) -> ExprSyntax {
            // Match pattern: (FunctionCallExprSyntax)? where call is R.image.<id>()
            if
                let call = node.expression.as(FunctionCallExprSyntax.self),
                let baseReplacement = replaceCall(call)
            {
                // Remove the trailing '?' by returning the base replacement directly,
                // but preserve original trivia of the optional chaining node.
                return baseReplacement
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
            }
            
            return super.visit(node)
        }

        override func visit(_ node: ForceUnwrapExprSyntax) -> ExprSyntax {
            // Match pattern: (FunctionCallExprSyntax)! where call is R.image.<id>()
            if
                let call = node.expression.as(FunctionCallExprSyntax.self),
                let baseReplacement = replaceCall(call)
            {
                // Preserve original trivia around the force-unwrap expression
                return baseReplacement
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
            }
            
            return super.visit(node)
        }

        // Also support replacing direct function calls without force unwrap.
        override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            if let baseReplacement = replaceCall(node) {
                // Preserve original trivia of the function call
                return baseReplacement
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
            }
            
            return super.visit(node)
        }

        // Replace standalone member uses: R.<kind>.<id> -> <ResourceType>Resource.<id>
        override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
            // Skip when this node is the called expression of a function call (UIKit case)
            if
                let parentCall = node.parent?.as(FunctionCallExprSyntax.self),
                parentCall.calledExpression.id == node.id,
                parentCall.arguments.isEmpty
            {
                return super.visit(node)
            }

            // Skip when this node is the base of a trailing `.image` (SwiftUI case)
            if
                let parentMember = node.parent?.as(MemberAccessExprSyntax.self),
                Kind(rawValue: parentMember.declName.baseName.text) != nil
            {
                return super.visit(node)
            }

            // Standalone member uses: R.<kind>.<id> -> <ResourceType>Resource.<id>
            if let (kind, identifier) = matchRKindIdentifier(from: node) {
                // Create replacement expression: <ResourceType>Resource.<id>
                return .parse(kind.resource(with: identifier.withoutImageAndColor()))
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
            }

            return super.visit(node)
        }
    }
}

private extension RToGeneratedAssetsRewriter.Rewriter {
    /// Matches `R.<kind>.<identifier>` returning (kind, identifier) if it matches.
    private func matchRKindIdentifier(from member: MemberAccessExprSyntax) -> (kind: Kind, identifier: String)? {
        guard
            let mid = member.base?.as(MemberAccessExprSyntax.self),
            let first = mid.base?.as(DeclReferenceExprSyntax.self),
            first.baseName.text == "R"
        else {
            return nil
        }
        
        guard let kind = Kind(rawValue: mid.declName.baseName.text) else {
            return nil
        }
        
        let identifier = member.declName.baseName.text
        
        return (kind, identifier)
    }
    
    private func replaceCall(_ call: FunctionCallExprSyntax) -> ExprSyntax? {
        // Ensure no arguments in the call `()`
        if !call.arguments.isEmpty {
            return nil
        }

        // Called expression could be either:
        // A: R.<kind>.<id>
        // B: R.<kind>.<id>.image (SwiftUI accessor)
        guard let called = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return nil
        }

        // SwiftUI accessor case: `.image()` or `.color()` where base is R.<kind>.<id>
        if
            Kind(rawValue: called.declName.baseName.text) != nil,
            let idMember = called.base?.as(MemberAccessExprSyntax.self),
            let match = matchRKindIdentifier(from: idMember)
        {
            // Ensure accessor matches kind for safety
            return expr(for: match.kind, with: match.identifier, from: .swiftUI)
        }

        // Direct UIKit case: called expression is R.<kind>.<id>
        if let match = matchRKindIdentifier(from: called) {
            return expr(for: match.kind, with: match.identifier, from: .uiKit)
        }

        return nil
    }
    
    /// creates an expression for module
    private func expr(for kind: Kind, with identifier: String, from module: Module) -> ExprSyntax {
        changedModules.insert(module)
        let resource = kind.resource(for: module, with: identifier.withoutImageAndColor())
        return .parse(resource)
    }
}

private enum Kind: String {
    case image
    case color
    
    func resource(for module: Module, with identifier: String) -> String {
        switch module {
        case .swiftUI:
            switch self {
            case .image: "Image(.\(identifier))"
            case .color: "Color(.\(identifier))"
            }
            
        case .uiKit:
            switch self {
            case .image: "UIImage(resource: .\(identifier))"
            case .color: "UIColor(resource: .\(identifier))"
            }
        }
    }
    
    func resource(with identifier: String) -> String {
        switch self {
        case .image: "ImageResource.\(identifier)"
        case .color: "ColorResource.\(identifier)"
        }
    }
}

private enum Module {
    case uiKit
    case swiftUI
    
    var name: String {
        switch self {
        case .uiKit: return "UIKit"
        case .swiftUI: return "SwiftUI"
        }
    }
}
