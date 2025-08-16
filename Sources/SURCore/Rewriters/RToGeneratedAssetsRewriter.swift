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
        let transformed = rewriter.rewrite(source)
        let newText = String(describing: transformed)

        if newText != original {
            try newText.write(to: url, atomically: true, encoding: .utf8)
            return true
        }
        return false
    }

    /// Rewriter that converts `R.image.<identifier>()!` -> `UIImage(resource: .<identifier>)`.
    private final class Rewriter: SyntaxRewriter {
        override func visit(_ node: ForceUnwrapExprSyntax) -> ExprSyntax {
            // Match pattern: (FunctionCallExprSyntax)! where call is R.image.<id>()
            if let call = node.expression.as(FunctionCallExprSyntax.self),
               let replacement = replaceRImageCall(call) {
                return ExprSyntax(replacement)
            }
            return ExprSyntax(super.visit(node))
        }

        // Also support replacing direct function calls without force unwrap.
        override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            if let replacement = replaceRImageCall(node) {
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
