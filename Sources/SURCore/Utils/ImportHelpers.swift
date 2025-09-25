//
//  ImportHelpers.swift
//  SUR
//
//  Created by Aleksandr Chernousov on 25/09/2025.
//

import Foundation
import SwiftParser
import SwiftSyntax

enum ImportHelpers {
    static func hasImport(named module: String, in file: SourceFileSyntax) -> Bool {
        for item in file.statements {
            if let imp = item.item.as(ImportDeclSyntax.self) {
                if imp.path.description == module {
                    return true
                }
            }
        }
        return false
    }
    
    static func insertImport(named module: String, into file: SourceFileSyntax) -> SourceFileSyntax {
        // Build an import decl item by parsing text to keep formatting correct.
        let parsed = Parser.parse(source: "import \(module)\n")
        guard var importItem = parsed.statements.first else {
            return file
        }
        
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
    
    static func lastImportInsertionIndex(in file: SourceFileSyntax) -> Int {
        var insertIndex = 0
        var lastImportIndex: Int?
        for (i, item) in file.statements.enumerated() where item.item.is(ImportDeclSyntax.self) {
            lastImportIndex = i
        }
        if let idx = lastImportIndex { insertIndex = idx + 1 }
        return insertIndex
    }

    static func triviaEndsWithNewline(_ trivia: Trivia?) -> Bool {
        guard let trivia else {
            return false
        }
        
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
