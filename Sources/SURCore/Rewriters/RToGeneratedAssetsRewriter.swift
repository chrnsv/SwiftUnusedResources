import Foundation
import SwiftParser
import SwiftSyntax

public struct RToGeneratedAssetsRewriter: Sendable {
    public init() {}

    /// Rewrites the given Swift source file in-place.
    /// - Returns: true if the file changed.
    @discardableResult
    public func rewrite(fileAt url: URL) throws -> Bool {
        let original = try String(contentsOf: url)
        let source = Parser.parse(source: original)
        let rewriter = Rewriter()
        var transformed: Syntax = rewriter.rewrite(source)

        // If we performed any UIKit replacements and UIKit isn't imported, insert it on the transformed file.
        if rewriter.changedModules.contains(.uiKit) {
            let transformedFile = transformed.as(SourceFileSyntax.self) ?? source
            if !hasImport(named: "UIKit", in: transformedFile) {
                let withImport = insertImport(named: "UIKit", into: transformedFile)
                transformed = Syntax(withImport)
            }
        }

        // If we performed any SwiftUI replacements and SwiftUI isn't imported, insert it too.
        if rewriter.changedModules.contains(.swiftUI) {
            let transformedFile = transformed.as(SourceFileSyntax.self) ?? source
            if !hasImport(named: "SwiftUI", in: transformedFile) {
                let withImport = insertImport(named: "SwiftUI", into: transformedFile)
                transformed = Syntax(withImport)
            }
        }

        let newText = transformed.description

        if newText != original {
            try newText.write(to: url, atomically: true, encoding: .utf8)
            return true
        }
        return false
    }

    /// Rewriter that converts `R.image.<identifier>()!` -> `UIImage(resource: .<identifier>)`.
}

private extension RToGeneratedAssetsRewriter {
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
                return parseExpr(kind.resource(with: identifier.withoutImageAndColor()))
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
            }

            return super.visit(node)
        }
    }
}

private extension RToGeneratedAssetsRewriter {
    func hasImport(named module: String, in file: SourceFileSyntax) -> Bool {
        for item in file.statements {
            if let imp = item.item.as(ImportDeclSyntax.self) {
                if imp.path.description == module { return true }
            }
        }
        return false
    }

    func insertImport(named module: String, into file: SourceFileSyntax) -> SourceFileSyntax {
        // Build an import decl item by parsing text to keep formatting correct.
        let parsed = Parser.parse(source: "import \(module)\n")
        guard var importItem = parsed.statements.first else { return file }

        let insertIndex = lastImportInsertionIndex(in: file)

        // If inserting after an existing statement and that statement doesn't end
        // with a newline, ensure the new import starts on a new line.
        if insertIndex > 0 {
            let prev = file.statements[file.statements.index(file.statements.startIndex, offsetBy: insertIndex - 1)]
            if !triviaEndsWithNewline(prev.trailingTrivia) {
                importItem = importItem.with(\.leadingTrivia, .newlines(1))
            }
        }

        let newStatements = file.statements.inserting(importItem, at: insertIndex)
        return file.with(\.statements, newStatements)
    }

    func lastImportInsertionIndex(in file: SourceFileSyntax) -> Int {
        var insertIndex = 0
        var lastImportIndex: Int?
        for (i, item) in file.statements.enumerated() where item.item.is(ImportDeclSyntax.self) {
            lastImportIndex = i
        }
        if let idx = lastImportIndex { insertIndex = idx + 1 }
        return insertIndex
    }

    func triviaEndsWithNewline(_ trivia: Trivia?) -> Bool {
        guard let trivia else { return false }
        for piece in trivia.reversed() {
            switch piece {
            case .newlines(let n): return n > 0
            case .carriageReturns(let n): return n > 0
            case .carriageReturnLineFeeds(let n): return n > 0
            case .spaces, .tabs, .verticalTabs, .formfeeds: continue
            default: return false
            }
        }
        return false
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
    
    /// Creates an expression for module.
    private func expr(for kind: Kind, with identifier: String, from module: Module) -> ExprSyntax {
        changedModules.insert(module)
        let resource = kind.resource(for: module, with: identifier.withoutImageAndColor())
        return parseExpr(resource)
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

    private func parseExpr(_ text: String) -> ExprSyntax {
        // Parse a tiny source text as expression: we wrap it in a dummy file
        let file = Parser.parse(source: text)
        if let item = file.statements.first?.item.as(ExprSyntax.self) {
            return item
        }
        return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(text)))
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
