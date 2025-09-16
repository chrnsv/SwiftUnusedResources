//
//  ExprSyntax+parse.swift
//  SUR
//
//  Created by Alexander Chernousov on 16.09.2025.
//

import SwiftParser
import SwiftSyntax

extension ExprSyntax {
    static func parse(_ text: String) -> ExprSyntax {
        // Parse a tiny source text as expression: we wrap it in a dummy file
        let file = Parser.parse(source: text)
        
        if let item = file.statements.first?.item.as(ExprSyntax.self) {
            return item
        }
        
        return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(text)))
    }
}
