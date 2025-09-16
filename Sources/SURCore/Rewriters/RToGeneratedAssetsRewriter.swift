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

        /// Matches `R.<kind>.<identifier>` returning (kind, identifier) if it matches.
        private func matchRKindIdentifier(from member: MemberAccessExprSyntax) -> (kind: String, identifier: String)? {
            guard let mid = member.base?.as(MemberAccessExprSyntax.self),
                  let first = mid.base?.as(DeclReferenceExprSyntax.self),
                  first.baseName.text == "R" else { return nil }
            let kind = mid.declName.baseName.text
            let identifier = member.declName.baseName.text
            return (kind, identifier)
        }

        /// Builds a SwiftUI expression for a given kind and identifier, setting the appropriate flag.
        private func swiftUIExpr(for kind: String, identifier: String) -> ExprSyntax? {
            switch kind {
            case "image":
                didSwiftUIChange = true
                let processed = stripSuffix(identifier, "image")
                return parseExpr("Image(.\(processed))")
            case "color":
                didSwiftUIChange = true
                let processed = stripSuffix(identifier, "color")
                return parseExpr("Color(.\(processed))")
            default:
                return nil
            }
        }

        /// Builds a UIKit expression for a given kind and identifier, setting the appropriate flag.
        private func uiKitExpr(for kind: String, identifier: String) -> ExprSyntax? {
            switch kind {
            case "image":
                didUIKitChange = true
                let processed = stripSuffix(identifier, "image")
                return parseExpr("UIImage(resource: .\(processed))")
            case "color":
                didUIKitChange = true
                let processed = stripSuffix(identifier, "color")
                return parseExpr("UIColor(resource: .\(processed))")
            default:
                return nil
            }
        }

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

        // Replace standalone member uses: R.<kind>.<id> -> <ResourceType>Resource.<id>
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

            // Standalone member uses: R.<kind>.<id> -> <ResourceType>Resource.<id>
            if let (kind, identifier) = matchRKindIdentifier(from: node) {
                let processed: String
                let resourceType: String
                switch kind {
                case "image":
                    processed = stripSuffix(identifier, "image")
                    resourceType = "ImageResource"
                case "color":
                    processed = stripSuffix(identifier, "color")
                    resourceType = "ColorResource"
                default:
                    return ExprSyntax(super.visit(node))
                }
                let replacement = parseExpr("\(resourceType).\(processed)")
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
            // A: R.<kind>.<id>
            // B: R.<kind>.<id>.image (SwiftUI accessor)
            guard let called = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }

            // SwiftUI accessor case: `.image()` or `.color()` where base is R.<kind>.<id>
            if (called.declName.baseName.text == "image" || called.declName.baseName.text == "color"),
               let idMember = called.base?.as(MemberAccessExprSyntax.self),
               let match = matchRKindIdentifier(from: idMember) {
                // Ensure accessor matches kind for safety
                if let expr = swiftUIExpr(for: match.kind, identifier: match.identifier) {
                    return expr
                }
            }

            // Direct UIKit case: called expression is R.<kind>.<id>
            if let match = matchRKindIdentifier(from: called) {
                return uiKitExpr(for: match.kind, identifier: match.identifier)
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

