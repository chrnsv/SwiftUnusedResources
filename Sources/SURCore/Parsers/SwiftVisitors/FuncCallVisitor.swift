import Foundation
import SwiftSyntax

final class FuncCallVisitor: SyntaxVisitor {
    private let kind: ExploreKind
    private let showWarnings: Bool
    
    private var name: String?
    
    private(set) var usages: [ExploreUsage] = []
    
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        _ url: URL,
        _ node: FunctionCallExprSyntax,
        kind: ExploreKind,
        uiKit: Bool,
        swiftUI: Bool,
        showWarnings: Bool
    ) {
        self.kind = kind
        self.showWarnings = showWarnings
        
        super.init(viewMode: viewMode)
        
        walk(node.calledExpression)
        
        if name == nil {
            return
        }

        if name == kind.uiClassName {
            if !uiKit && !swiftUI {
                warn(url: url, node: node, "\(kind.uiClassName) used but UIKit not imported")
                return
            }

            if node.arguments.count < 1 {
                return
            }
            
            node.arguments.forEach { tuple in
                if tuple.label?.text != "named" {
                    return
                }
                
                if let comment = findComment(tuple) {
                    usages.append(.regexp(comment, kind))
                    return
                }
                
                let regex = StringVisitor(tuple).parse()
                if regex == ".*" {
                    warn(url: url, node: tuple, "Couldn't guess match, please specify pattern")
                    return
                }

                if regex.contains("*") {
                    warn(url: url, node: tuple, "Too wide match \"\(regex)\" is generated for resource, please specify pattern")
                }
                
                usages.append(.regexp(regex, kind))
            }
        }
        else if name == kind.swiftUIClassName && swiftUI {
            if node.arguments.count != 1 {
                return
            }
            
            guard let tuple = node.arguments.first else {
                return
            }
            
            if tuple.label?.text != nil {
                return
            }
            
            if let comment = findComment(tuple) {
                usages.append(.regexp(comment, kind))
                return
            }
            
            let regex = StringVisitor(tuple).parse()

            if regex == ".*" {
                warn(url: url, node: tuple, "Couldn't guess match, please specify pattern")
                return
            }

            if regex.contains("*") {
                warn(url: url, node: tuple, "Too wide match \"\(regex)\" is generated for resource, please specify pattern")
            }
            
            usages.append(.regexp(regex, kind))
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
        guard let trivia else {
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

        while p.parent != nil && p.syntaxNodeType != CodeBlockItemSyntax.self {
            if let comment = extractComment(p.leadingTrivia) {
                return comment
            }

            p = p.parent!
        }
        
        return nil
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        name = node.baseName.text
        
        return .skipChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        return .skipChildren
    }
}
