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
        if rewriter.didUIKitChange {
            let transformedFile = transformed.as(SourceFileSyntax.self) ?? source
            if !hasImport(named: "UIKit", in: transformedFile) {
                let withImport = insertImport(named: "UIKit", into: transformedFile)
                transformed = Syntax(withImport)
            }
        }

        // If we performed any SwiftUI replacements and SwiftUI isn't imported, insert it too.
        if rewriter.didSwiftUIChange {
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
    private final class Rewriter: SyntaxRewriter {
    private(set) var didUIKitChange = false
    private(set) var didSwiftUIChange = false

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

        // Replace standalone member uses: R.image.<id> -> ImageResource.<id>
        override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
            // Skip when this node is the called expression of a function call (UIKit case)
            if let parentCall = node.parent?.as(FunctionCallExprSyntax.self),
               parentCall.calledExpression.id == node.id,
               parentCall.arguments.isEmpty {
                return ExprSyntax(super.visit(node))
            }

            // Skip when this node is the base of a trailing `.image` (SwiftUI case)
            if let parentMember = node.parent?.as(MemberAccessExprSyntax.self),
               parentMember.declName.baseName.text == "image" {
                return ExprSyntax(super.visit(node))
            }

            // Match R.image.<id>
            if let mid = node.base?.as(MemberAccessExprSyntax.self),
               mid.declName.baseName.text == "image",
               let first = mid.base?.as(DeclReferenceExprSyntax.self),
               first.baseName.text == "R" {
                let identifier = node.declName.baseName.text
                let processed = stripSuffix(identifier, "image")
                let replacement = parseExpr("ImageResource.\(processed)")
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
                return ExprSyntax(replacement)
            }

            // Match R.color.<id>
            if let mid = node.base?.as(MemberAccessExprSyntax.self),
               mid.declName.baseName.text == "color",
               let first = mid.base?.as(DeclReferenceExprSyntax.self),
               first.baseName.text == "R" {
                let identifier = node.declName.baseName.text
                let processed = stripSuffix(identifier, "color")
                let replacement = parseExpr("ColorResource.\(processed)")
                    .with(\.leadingTrivia, node.leadingTrivia)
                    .with(\.trailingTrivia, node.trailingTrivia)
                return ExprSyntax(replacement)
            }

            return ExprSyntax(super.visit(node))
        }

        private func replaceRImageCall(_ call: FunctionCallExprSyntax) -> ExprSyntax? {
            // Ensure no arguments in the call `()`
            if !call.arguments.isEmpty { return nil }

            // Called expression could be either:
            // A: R.image.<id>
            // B: R.image.<id>.image
            guard let called = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }

            // Try SwiftUI patterns first
            // Image: ... .image() where base is R.image.<id>
            if called.declName.baseName.text == "image",
               let idMember = called.base?.as(MemberAccessExprSyntax.self),
               let mid = idMember.base?.as(MemberAccessExprSyntax.self),
               mid.declName.baseName.text == "image",
               let first = mid.base?.as(DeclReferenceExprSyntax.self),
               first.baseName.text == "R" {
                let identifier = idMember.declName.baseName.text
                let processed = stripSuffix(identifier, "image")
                didSwiftUIChange = true
                return parseExpr("Image(.\(processed))")
            }

            // Color: ... .color() where base is R.color.<id>
            if called.declName.baseName.text == "color",
               let idMember = called.base?.as(MemberAccessExprSyntax.self),
               let mid = idMember.base?.as(MemberAccessExprSyntax.self),
               mid.declName.baseName.text == "color",
               let first = mid.base?.as(DeclReferenceExprSyntax.self),
               first.baseName.text == "R" {
                let identifier = idMember.declName.baseName.text
                let processed = stripSuffix(identifier, "color")
                didSwiftUIChange = true
                return parseExpr("Color(.\(processed))")
            }

            // UIKit patterns
            if let lastMember = call.calledExpression.as(MemberAccessExprSyntax.self),
               let mid = lastMember.base?.as(MemberAccessExprSyntax.self),
               let first = mid.base?.as(DeclReferenceExprSyntax.self),
               first.baseName.text == "R" {
                let identifier = lastMember.declName.baseName.text
                if mid.declName.baseName.text == "image" {
                    let processed = stripSuffix(identifier, "image")
                    didUIKitChange = true
                    return parseExpr("UIImage(resource: .\(processed))")
                } else if mid.declName.baseName.text == "color" {
                    let processed = stripSuffix(identifier, "color")
                    didUIKitChange = true
                    return parseExpr("UIColor(resource: .\(processed))")
                }
            }

            return nil
        }

        private func stripSuffix(_ name: String, _ suffix: String) -> String {
            let lower = name.lowercased()
            if lower.hasSuffix(suffix), name.count > suffix.count {
                return String(name.dropLast(suffix.count))
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
        for (i, item) in file.statements.enumerated() {
            if item.item.is(ImportDeclSyntax.self) { lastImportIndex = i }
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
