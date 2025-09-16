import Foundation
import SwiftParser
import SwiftSyntax

public struct RToGeneratedStringsRewriter: Sendable {
    private let catalogs: Set<String>
    
    public init(projectAt projectURL: URL) {
        catalogs = {
            guard let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: nil)
            else { return [] }
            var catalogs = Set<String>()
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "xcstrings" {
                    catalogs.insert(fileURL.deletingPathExtension().lastPathComponent.lowercased())
                }
            }
            return catalogs
        }()
        
        print("Catalogs found: \(catalogs)")
    }
    
    @discardableResult
    public func rewrite(fileAt fileURL: URL) throws -> Bool {
        let original = try String(contentsOf: fileURL)
        let sourceFile = Parser.parse(source: original)
        
        let rewriter = Rewriter(xcstringCatalogs: catalogs)
        var rewritten = rewriter.visit(sourceFile)
        
        if rewriter.usedSwiftUI && !hasImport(named: "SwiftUI", in: rewritten) {
            rewritten = insertImport(named: "SwiftUI", into: rewritten)
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
                        usedSwiftUI = true
                        var replacement = ExprSyntax.parse("Text(.\(catalog).\(identifier))")
                        replacement = applyTrivia(from: node, to: replacement)
                        return replacement
                    }
                }
            }
            
            if
                let calledExpr = node.calledExpression.as(MemberAccessExprSyntax.self),
                let (catalog, identifier) = matchRStringCatalogIdentifier(from: calledExpr)
            {
                if node.arguments.isEmpty {
                    var replacement = ExprSyntax.parse("String(localized: .\(catalog).\(identifier))")
                    replacement = applyTrivia(from: node, to: replacement)
                    return replacement
                }
            }
            return super.visit(node)
        }
        
        override func visit(_ node: OptionalChainingExprSyntax) -> ExprSyntax {
            // Handle optional chaining around calls to R.string or text()
            if let wrappedCall = node.expression.as(FunctionCallExprSyntax.self) {
                let rewrittenCall = visit(wrappedCall)
                if rewrittenCall != ExprSyntax(wrappedCall) {
                    // Return rewritten call without optional chaining, preserving trivia
                    let withTrivia = applyTrivia(from: node, to: rewrittenCall)
                    return withTrivia
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
                    let withTrivia = applyTrivia(from: node, to: rewrittenCall)
                    return withTrivia
                }
            }
            return super.visit(node)
        }
    }
}

private extension RToGeneratedStringsRewriter.Rewriter {
    func matchRStringCatalogIdentifier(from member: MemberAccessExprSyntax) -> (catalog: String, identifier: String)? {
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
    
    private func applyTrivia(from original: some SyntaxProtocol, to expr: ExprSyntax) -> ExprSyntax {
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

// MARK: - Import Helpers
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

private extension String {
    func capitalizedFirstLetter() -> String {
        guard let first else {
            return self
        }
        
        return String(first).uppercased() + dropFirst()
    }
}
