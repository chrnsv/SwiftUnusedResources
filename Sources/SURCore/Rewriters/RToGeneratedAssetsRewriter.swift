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

        // If we performed any replacements and UIKit isn't imported, insert it on the transformed file.
        if rewriter.didChange {
            let transformedFile = transformed.as(SourceFileSyntax.self) ?? source
            if !hasUIKitImport(in: transformedFile) {
                let withImport = insertUIKitImport(into: transformedFile)
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
    private final class Rewriter: SyntaxRewriter {
    private(set) var didChange = false

        override func visit(_ node: OptionalChainingExprSyntax) -> ExprSyntax {
            // Match pattern: (FunctionCallExprSyntax)? where call is R.image.<id>()
            if let call = node.expression.as(FunctionCallExprSyntax.self),
               let baseReplacement = replaceRImageCall(call) {
                // Remove the trailing '?' by returning the base replacement directly,
                // but preserve original trivia of the optional chaining node.
                let replacement = baseReplacement
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
                return ExprSyntax(replacement)
            }
            return ExprSyntax(super.visit(node))
        }

        override func visit(_ node: ForceUnwrapExprSyntax) -> ExprSyntax {
            // Match pattern: (FunctionCallExprSyntax)! where call is R.image.<id>()
            if let call = node.expression.as(FunctionCallExprSyntax.self),
               let baseReplacement = replaceRImageCall(call) {
                // Preserve original trivia around the force-unwrap expression
                let replacement = baseReplacement
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
                return ExprSyntax(replacement)
            }
            return ExprSyntax(super.visit(node))
        }

        // Also support replacing direct function calls without force unwrap.
        override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            if let baseReplacement = replaceRImageCall(node) {
                // Preserve original trivia of the function call
                let replacement = baseReplacement
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
                return ExprSyntax(replacement)
            }
            return ExprSyntax(super.visit(node))
        }

        private func replaceRImageCall(_ call: FunctionCallExprSyntax) -> ExprSyntax? {
            // Ensure no arguments in the call `()`
            if !call.arguments.isEmpty { return nil }

            // calledExpression must be a member access like `R.image.<id>`
            guard let lastMember = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }

            let identifier = lastMember.declName.baseName.text

            // Base must be `R.image`
            guard let mid = lastMember.base?.as(MemberAccessExprSyntax.self),
                  mid.declName.baseName.text == "image",
                  let first = mid.base?.as(DeclReferenceExprSyntax.self),
                  first.baseName.text == "R" else {
                return nil
            }

            let processed = stripImageSuffix(identifier)

            // Build `UIImage(resource: .<processed>)` expression via parsing
            let exprText = "UIImage(resource: .\(processed))"
            didChange = true
            return parseExpr(exprText)
        }

        private func stripImageSuffix(_ name: String) -> String {
            let lower = name.lowercased()
            if lower.hasSuffix("image"), name.count > 5 {
                return String(name.dropLast(5))
            }
            return name
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
}

private extension RToGeneratedAssetsRewriter {
    func hasUIKitImport(in file: SourceFileSyntax) -> Bool {
        for item in file.statements {
            if let imp = item.item.as(ImportDeclSyntax.self) {
                if imp.path.description == "UIKit" { return true }
            }
        }
        return false
    }

    func insertUIKitImport(into file: SourceFileSyntax) -> SourceFileSyntax {
        // Build an import decl item by parsing text to keep formatting correct.
        let parsed = Parser.parse(source: "import UIKit\n")
        guard var importItem = parsed.statements.first else { return file }

        var insertIndex = 0
        var lastImportIndex: Int?
        for (i, item) in file.statements.enumerated() {
            if item.item.is(ImportDeclSyntax.self) { lastImportIndex = i }
        }
        if let idx = lastImportIndex { insertIndex = idx + 1 }

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
