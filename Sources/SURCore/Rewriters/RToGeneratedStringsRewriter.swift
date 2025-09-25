import Foundation
import SwiftParser
import SwiftSyntax

public struct RToGeneratedStringsRewriter: Sendable {
    private let catalogs: Set<String>
    
    public init(projectAt projectURL: URL) {
        catalogs = Self.findXCStringsCatalogs(in: projectURL)
        print("Catalogs found: \(catalogs)")
    }
    
    @discardableResult
    public func rewrite(fileAt fileURL: URL) throws -> Bool {
        let original = try String(contentsOf: fileURL)
        let sourceFile = Parser.parse(source: original)
        
        let rewriter = Rewriter(xcstringCatalogs: catalogs)
        var rewritten = rewriter.visit(sourceFile)
        
        if rewriter.usedSwiftUI && !ImportHelpers.hasImport(named: "SwiftUI", in: rewritten) {
            rewritten = ImportHelpers.insertImport(named: "SwiftUI", into: rewritten)
        }
        
        let rewrittenString = rewritten.description
        guard rewrittenString != original else {
            return false
        }
        try rewrittenString.write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    }
}

private extension RToGeneratedStringsRewriter {
    static func findXCStringsCatalogs(in projectURL: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: nil)
        else { return [] }
        
        var catalogs = Set<String>()
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "xcstrings" {
            catalogs.insert(fileURL.deletingPathExtension().lastPathComponent.lowercased())
        }
        return catalogs
    }
}

private extension RToGeneratedStringsRewriter {
    final class Rewriter: SyntaxRewriter {
        let catalogs: Set<String>
        private(set) var usedSwiftUI = false
        
        init(xcstringCatalogs: Set<String>) {
            self.catalogs = xcstringCatalogs
            
            super.init()
        }
        
        override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            if let calledExpr = node.calledExpression.as(MemberAccessExprSyntax.self) {
                if
                    calledExpr.declName.baseName.text == "text",
                    let baseMember = calledExpr.base?.as(MemberAccessExprSyntax.self),
                    let (catalog, identifier, language) = matchRStringCatalogIdentifier(from: baseMember)
                {
                    return createExpression(
                        type: .text,
                        catalog: catalog,
                        identifier: identifier,
                        arguments: node.arguments,
                        language: language,
                        originalNode: node
                    )
                }
            }
            
            if
                let calledExpr = node.calledExpression.as(MemberAccessExprSyntax.self),
                let (catalog, identifier, language) = matchRStringCatalogIdentifier(from: calledExpr)
            {
                return createExpression(
                    type: .stringLocalized,
                    catalog: catalog,
                    identifier: identifier,
                    arguments: node.arguments,
                    language: language,
                    originalNode: node
                )
            }
            
            return super.visit(node)
        }
        
        override func visit(_ node: OptionalChainingExprSyntax) -> ExprSyntax {
            // Handle optional chaining around calls to R.string or text()
            if let wrappedCall = node.expression.as(FunctionCallExprSyntax.self) {
                let rewrittenCall = visit(wrappedCall)
                if rewrittenCall != ExprSyntax(wrappedCall) {
                    // Return rewritten call without optional chaining, preserving trivia
                    return applyTrivia(from: node, to: rewrittenCall)
                }
            }
            return super.visit(node)
        }
        
        override func visit(_ node: ForceUnwrapExprSyntax) -> ExprSyntax {
            // Handle force unwrap around calls to R.string or text()
            if let wrappedCall = node.expression.as(FunctionCallExprSyntax.self) {
                let rewrittenCall = visit(wrappedCall)
                if rewrittenCall != ExprSyntax(wrappedCall) {
                    // Return rewritten call without force unwrap, preserving trivia
                    return applyTrivia(from: node, to: rewrittenCall)
                }
            }
            return super.visit(node)
        }
    }
}

private extension RToGeneratedStringsRewriter.Rewriter {
    func matchRStringCatalogIdentifier(
        from member: MemberAccessExprSyntax
    ) -> (catalog: String, identifier: String, language: String?)? {
        guard
            let mid = member.base?.as(MemberAccessExprSyntax.self)
        else {
            return nil
        }
        
        let catalog = mid.declName.baseName.text
        let identifier = member.declName.baseName.text
        
        // Check if catalog is valid
        if !catalogs.contains(catalog.lowercased()) {
            return nil
        }
        
        // Check for R.string(preferredLanguages: ...).<catalog>.<identifier> pattern
        if
            let baseExpr = mid.base,
            let call = baseExpr.as(FunctionCallExprSyntax.self),
            let calledMember = call.calledExpression.as(MemberAccessExprSyntax.self),
            let rDecl = calledMember.base?.as(DeclReferenceExprSyntax.self),
            rDecl.baseName.text == "R",
            calledMember.declName.baseName.text == "string",
            let arg = call.arguments.first(where: { $0.label?.text == "preferredLanguages" })
        {
            let languageExpr = arg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
            print("Matched R.string(preferredLanguages: ...).\(catalog).\(identifier)")
            return (catalog.capitalizedFirstLetter(), identifier, languageExpr)
        }
        
        // Check for R.string.<catalog>.<identifier> pattern
        if
            let base = mid.base?.as(MemberAccessExprSyntax.self),
            let declRef = base.base?.as(DeclReferenceExprSyntax.self),
            declRef.baseName.text == "R",
            base.declName.baseName.text == "string"
        {
            print("Matched R.string.\(catalog).\(identifier)")
            return (catalog.capitalizedFirstLetter(), identifier, nil)
        }
        
        return nil
    }
    
    private func createExpression(
        type: ExpressionType,
        catalog: String,
        identifier: String,
        arguments: LabeledExprListSyntax,
        language: String? = nil,
        originalNode: some SyntaxProtocol
    ) -> ExprSyntax {
        if type == .text {
            usedSwiftUI = true
        }
        
        let argsText = formatArguments(arguments)
        let qualifier = createQualifier(for: catalog)
        
        let baseExpression = "\(type.prefix).\(qualifier)\(identifier)\(argsText))"
        let finalExpression: String
        
        if let language {
            finalExpression = "\(baseExpression).with(preferredLanguages: \(language))"
        }
        else {
            finalExpression = baseExpression
        }
        
        let replacement = ExprSyntax.parse(finalExpression)
        return applyTrivia(from: originalNode, to: replacement)
    }
    
    private func createQualifier(for catalog: String) -> String {
        (catalog == "Localizable") ? "" : "\(catalog)."
    }
    
    private func formatArguments(_ arguments: LabeledExprListSyntax) -> String {
        guard !arguments.isEmpty else {
            return ""
        }
        
        return "(" + arguments.description.trimmingCharacters(in: .whitespacesAndNewlines) + ")"
    }
    
    /// Applies leading and trailing trivia (whitespace, comments, etc.) from the original syntax node to the new expression.
    /// This preserves the formatting and comments from the original code in the rewritten expression.
    ///
    /// - Parameters:
    ///   - original: The original syntax node to copy trivia from
    ///   - expr: The new expression to apply trivia to
    /// - Returns: The expression with applied trivia
    private func applyTrivia(
        from original: some SyntaxProtocol,
        to expr: ExprSyntax
    ) -> ExprSyntax {
        expr
            .with(\.leadingTrivia, original.leadingTrivia)
            .with(\.trailingTrivia, original.trailingTrivia)
    }
}

private extension RToGeneratedStringsRewriter.Rewriter {
    enum ExpressionType {
        case text
        case stringLocalized
        
        var prefix: String {
            switch self {
            case .text: "Text("
            case .stringLocalized: "String(localized: "
            }
        }
    }
}

private extension String {
    func capitalizedFirstLetter() -> String {
        guard let first else {
            return self
        }
        
        return String(first).uppercased() + dropFirst()
    }
}
