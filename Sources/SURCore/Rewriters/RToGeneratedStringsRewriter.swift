import Foundation
import SwiftParser
import SwiftSyntax

public struct RToGeneratedStringsRewriter: Sendable {
    private let catalogs: Set<String>
    
    public init(projectAt projectURL: URL) {
        catalogs = Self.findXCStringsCatalogs(in: projectURL)
        print("Catalogs found: \(catalogs)")
    }
    
    private static func findXCStringsCatalogs(in projectURL: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: nil)
        else { return [] }
        
        var catalogs = Set<String>()
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "xcstrings" {
            catalogs.insert(fileURL.deletingPathExtension().lastPathComponent.lowercased())
        }
        return catalogs
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
                    let (catalog, identifier) = matchRStringCatalogIdentifier(from: baseMember)
                {
                    if node.arguments.isEmpty {
                        return createTextExpression(catalog: catalog, identifier: identifier, originalNode: node)
                    }
                }
            }
            
            if
                let calledExpr = node.calledExpression.as(MemberAccessExprSyntax.self),
                let (catalog, identifier, language) = matchRStringCatalogIdentifierAndPreferredLanguage(from: calledExpr)
            {
                return createStringLocalizedWithPreferredLanguagesExpression(
                    catalog: catalog,
                    identifier: identifier,
                    language: language,
                    arguments: node.arguments,
                    originalNode: node
                )
            }
            
            if
                let calledExpr = node.calledExpression.as(MemberAccessExprSyntax.self),
                let (catalog, identifier) = matchRStringCatalogIdentifier(from: calledExpr)
            {
                return createStringLocalizedExpression(
                    catalog: catalog,
                    identifier: identifier,
                    arguments: node.arguments,
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
    func matchRStringCatalogIdentifierAndPreferredLanguage(
        from member: MemberAccessExprSyntax
    ) -> (catalog: String, identifier: String, languageExpr: String)? {
        // Expect member like: R.string(preferredLanguages: <language>).<catalog>.<identifier>
        guard
            let mid = member.base?.as(MemberAccessExprSyntax.self),
            let baseExpr = mid.base
        else {
            return nil
        }
        // baseExpr should be a call: R.string(preferredLanguages: ...)
        guard
            let call = baseExpr.as(FunctionCallExprSyntax.self),
            let calledMember = call.calledExpression.as(MemberAccessExprSyntax.self),
            let rDecl = calledMember.base?.as(DeclReferenceExprSyntax.self),
            rDecl.baseName.text == "R",
            calledMember.declName.baseName.text == "string"
        else {
            return nil
        }
        
        // Find preferredLanguages argument
        guard let arg = call.arguments.first(where: { $0.label?.text == "preferredLanguages" }) else {
            return nil
        }
        let languageExpr = arg.expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let catalog = mid.declName.baseName.text
        let identifier = member.declName.baseName.text
        
        if !catalogs.contains(catalog.lowercased()) {
            return nil
        }
        
        print("Matched R.string(preferredLanguages: ...).\(catalog).\(identifier)")
        
        return (catalog.capitalizedFirstLetter(), identifier, languageExpr)
    }
    
    func matchRStringCatalogIdentifier(
        from member: MemberAccessExprSyntax
    ) -> (catalog: String, identifier: String)? {
        // Expect member like: R.string.<catalog>.<identifier>
        guard
            let mid = member.base?.as(MemberAccessExprSyntax.self),
            let base = mid.base?.as(MemberAccessExprSyntax.self),
            let declRef = base.base?.as(DeclReferenceExprSyntax.self),
            declRef.baseName.text == "R",
            base.declName.baseName.text == "string"
        else {
            return nil
        }
        
        let catalog = mid.declName.baseName.text
        let identifier = member.declName.baseName.text
        
        if !catalogs.contains(catalog.lowercased()) {
            return nil
        }
        
        print("Matched R.string.\(catalog).\(identifier)")
        
        return (catalog.capitalizedFirstLetter(), identifier)
    }
    
    private func createTextExpression(
        catalog: String,
        identifier: String,
        originalNode: some SyntaxProtocol
    ) -> ExprSyntax {
        usedSwiftUI = true
        let qualifier = createQualifier(for: catalog)
        let replacement = ExprSyntax.parse("Text(.\(qualifier)\(identifier))")
        return applyTrivia(from: originalNode, to: replacement)
    }
    
    private func createStringLocalizedExpression(
        catalog: String,
        identifier: String,
        arguments: LabeledExprListSyntax,
        originalNode: some SyntaxProtocol
    ) -> ExprSyntax {
        let argsText = formatArguments(arguments)
        let qualifier = createQualifier(for: catalog)
        let replacement = ExprSyntax.parse("String(localized: .\(qualifier)\(identifier)\(argsText))")
        return applyTrivia(from: originalNode, to: replacement)
    }
    
    private func createStringLocalizedWithPreferredLanguagesExpression(
        catalog: String,
        identifier: String,
        language: String,
        arguments: LabeledExprListSyntax,
        originalNode: some SyntaxProtocol
    ) -> ExprSyntax {
        let argsText = formatArguments(arguments)
        let qualifier = createQualifier(for: catalog)
        let replacement = ExprSyntax.parse("String(localized: .\(qualifier)\(identifier)\(argsText).with(preferredLanguages: \(language)))")
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
    
    private func applyTrivia(
        from original: some SyntaxProtocol,
        to expr: ExprSyntax
    ) -> ExprSyntax {
        let leading = original.leadingTrivia
        let trailing = original.trailingTrivia
        
        if var call = expr.as(FunctionCallExprSyntax.self) {
            call = call
                .with(\.leadingTrivia, leading)
                .with(\.trailingTrivia, trailing)
            
            return ExprSyntax(call)
        }
        
        if var member = expr.as(MemberAccessExprSyntax.self) {
            member = member
                .with(\.leadingTrivia, leading)
                .with(\.trailingTrivia, trailing)
            
            return ExprSyntax(member)
        }
        
        if var declRef = expr.as(DeclReferenceExprSyntax.self) {
            declRef = declRef
                .with(\.leadingTrivia, leading)
                .with(\.trailingTrivia, trailing)
            
            return ExprSyntax(declRef)
        }
        
        // Fallback: return as-is if we can't set trivia
        return expr
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
