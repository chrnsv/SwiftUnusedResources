import SwiftSyntax

extension SourceVisitor {
    final class MemberVisitor: SyntaxVisitor {
        private(set) var members: [String] = []

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            members.append(node.baseName.text)

            return super.visit(node)
        }
    }

    /// Collects the expressions of all `return` statements within the visited subtree,
    /// skipping nested scopes (closures, functions, subscripts, nested types) so their
    /// returns are not attributed to the enclosing declaration.
    final class ReturnVisitor: SyntaxVisitor {
        private(set) var expressions: [ExprSyntax] = []

        override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
            if let expression = node.expression {
                expressions.append(expression)
            }

            return .visitChildren
        }

        override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            .skipChildren
        }
    }

    /// Collects the names of bare member accesses (member accesses with no base, e.g. `.assetName`).
    /// Skips children once a bare member is found so the innermost member of a chain is recorded once.
    ///
    /// Function-call arguments are intentionally walked, not skipped: wrapper constructors such as
    /// `Optional.some(.asset)` / `Optional(.asset)` carry the real resource inside the argument, and
    /// missing it would be a false negative — far worse for an unused-resource tool (it could lead to
    /// deleting an actually-used asset) than the harmless over-collection of an unrelated argument.
    final class BareMemberVisitor: SyntaxVisitor {
        private(set) var names: [String] = []

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            guard node.base == nil else {
                return .visitChildren
            }

            names.append(node.declName.baseName.text)

            return .skipChildren
        }
    }
}
