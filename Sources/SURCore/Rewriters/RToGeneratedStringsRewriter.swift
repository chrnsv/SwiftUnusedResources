import Foundation
import SwiftParser
import SwiftSyntax

public struct RToGeneratedStringsRewriter: FileRewriter {
    private let catalogs: Set<String>
    
    public init(stringCatalogs: Set<String>) {
        self.catalogs = stringCatalogs
        print("Using provided catalogs: \(catalogs)")
    }
    
    @discardableResult
    public func rewrite(fileAt fileURL: URL) throws -> Bool {
        try rewrite(fileAt: fileURL, dryRun: false)
    }
    
    @discardableResult
    public func rewrite(fileAt fileURL: URL, dryRun: Bool) throws -> Bool {
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
        
        if !dryRun {
            try rewrittenString.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        return true
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
            guard let calledExpr = node.calledExpression.as(MemberAccessExprSyntax.self) else {
                return super.visit(node)
            }
            
            // Determine expression type and target member to analyze
            let (expressionType, targetMember): (ExpressionType, MemberAccessExprSyntax)
            
            if
                calledExpr.declName.baseName.text == "text",
                let baseMember = calledExpr.base?.as(MemberAccessExprSyntax.self)
            {
                // Handle .text() calls: R.string.<catalog>.<identifier>.text()
                (expressionType, targetMember) = (.text, baseMember)
            }
            else {
                // Handle direct R.string calls: R.string.<catalog>.<identifier>()
                (expressionType, targetMember) = (.stringLocalized, calledExpr)
            }
            
            // Try to match and transform R.string pattern
            guard let (catalog, identifier, language) = matchRStringCatalogIdentifier(from: targetMember) else {
                return super.visit(node)
            }
            
            return createExpression(
                type: expressionType,
                catalog: catalog,
                identifier: identifier,
                arguments: node.arguments,
                language: language,
                originalNode: node
            )
        }
        
        override func visit(_ node: OptionalChainingExprSyntax) -> ExprSyntax {
            // Handle optional chaining around R.string calls
            // Since String(localized:) and Text() don't return optionals, ? can be safely removed
            let rewrittenExpression = visit(node.expression)
            
            if rewrittenExpression != node.expression {
                // R.string was transformed, remove optional chaining and preserve trivia
                return applyTrivia(from: node, to: rewrittenExpression)
            }
            
            return super.visit(node)
        }
        
        override func visit(_ node: ForceUnwrapExprSyntax) -> ExprSyntax {
            // Handle force unwrap around R.string calls  
            // Since String(localized:) and Text() don't return optionals, ! can be safely removed
            let rewrittenExpression = visit(node.expression)
            
            if rewrittenExpression != node.expression {
                // R.string was transformed, remove force unwrap and preserve trivia
                return applyTrivia(from: node, to: rewrittenExpression)
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
