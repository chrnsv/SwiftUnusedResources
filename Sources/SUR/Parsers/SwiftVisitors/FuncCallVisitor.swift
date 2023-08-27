import Foundation
import SwiftSyntax

class FuncCallVisitor: SyntaxVisitor {
    private let register: ImageRegister
    
    private var name: String?
    
    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        _ url: URL,
        _ node: FunctionCallExprSyntax,
        _ register: @escaping ImageRegister,
        uiKit: Bool,
        swiftUI: Bool
    ) {
        self.register = register
        super.init(viewMode: viewMode)
        
        walk(node.calledExpression)
        
        if (name == nil) {
            return
        }

        if (name == "UIImage") {
            if (!uiKit && !swiftUI) {
                warn(url: url, node: node, "UIImage used but UIKit not imported")
                return
            }

            if (node.argumentList.count < 1) {
                return
            }
            
            node.argumentList.forEach { tuple in
                if (tuple.label?.text != "named") {
                    return
                }
                
                if let comment = findComment(tuple) {
                    register(.regexp(comment))
                    return
                }
                
                let regex = StringVisitor(tuple).parse()
                if (regex == ".*") {
                    warn(url: url, node: tuple, "Couldn't guess match, please specify pattern")
                    return
                }

                if (regex.contains("*")) {
                    warn(url: url, node: tuple, "Too wide match \"\(regex)\" is generated for resource, please specify pattern")
                }
                
                register(.regexp(regex))
            }
        }
        else if (name == "Image" && swiftUI) {
            if (node.argumentList.count != 1) {
                return
            }
            
            guard let tuple = node.argumentList.first else {
                return
            }
            
            if let comment = findComment(tuple) {
                register(.regexp(comment))
                return
            }
            
            let regex = StringVisitor(tuple).parse()

            if (regex == ".*") {
                warn(url: url, node: tuple, "Couldn't guess match, please specify pattern")
                return
            }

            if (regex.contains("*")) {
                warn(url: url, node: tuple, "Too wide match \"\(regex)\" is generated for resource, please specify pattern")
            }

            register(.regexp(regex))
        }
    }

    private func warn(url: URL, node: SyntaxProtocol, _ message: String) {
        guard showWarnings else {
            return
        }
            
        let source = String(String(describing: node.root).prefix(node.position.utf8Offset))
        let line = source.count(of: "\n") + 1
        let pos = source.distance(from: source.lastIndex(of: "\n") ?? source.endIndex, to: source.endIndex)

        print("\(url.path):\(line):\(pos): warning: \(message)")
    }
    
    private func matchComment(text: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: "^\\s*(?:\\/\\/|\\*+)?\\s*image:\\s*(.*?)\\s*$"),
            let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[range])
    }
    
    private func extractComment(_ trivia: Trivia?) -> String? {
        guard let trivia = trivia else {
            return nil
        }
        
        for piece in trivia {
            if case .lineComment(let c) = piece {
                if let c = self.matchComment(text: c) {
                    return c
                }
            }
            else if case .blockComment(let c) = piece {
                if let c = self.matchComment(text: c) {
                    return c
                }
            }
        }
        
        return nil
    }
    
    private func findComment(_ node: SyntaxProtocol) -> String? {
        var p: SyntaxProtocol = node

        while (p.parent != nil && p.syntaxNodeType != CodeBlockItemSyntax.self) {
            if let comment = extractComment(p.leadingTrivia) {
                return comment
            }

            p = p.parent!
        }
        
        return nil
    }
    
    override func visit(_ node: IdentifierExprSyntax) -> SyntaxVisitorContinueKind {
        name = node.identifier.text
        
        return .skipChildren
    }
}
