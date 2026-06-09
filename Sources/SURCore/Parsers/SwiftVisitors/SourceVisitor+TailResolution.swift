import SwiftSyntax

/// Stateless syntax helpers that resolve value-position expressions to the leaf
/// expressions they may evaluate to. Kept separate from the stateful visitor logic.
extension SourceVisitor {
    /// Returns the statements of a property's `get` accessor, covering both the
    /// shorthand `{ ... }` getter and an explicit `get { ... }` accessor.
    func getterStatements(of accessorBlock: AccessorBlockSyntax?) -> CodeBlockItemListSyntax? {
        guard let accessorBlock else {
            return nil
        }

        switch accessorBlock.accessors {
        case .getter(let statements):
            return statements

        case .accessors(let accessors):
            return accessors
                .first { $0.accessorSpecifier.tokenKind == .keyword(.get) }?
                .body?
                .statements
        }
    }

    /// Resolves the implicit-return value of a block: if its last item is an expression,
    /// expand it through control-flow value positions; otherwise nothing.
    func implicitTail(of statements: CodeBlockItemListSyntax) -> [ExprSyntax] {
        guard let last = statements.last, let expression = tailExpression(of: last.item) else {
            return []
        }

        return resolveTail(expression)
    }

    /// The value expression of a trailing code-block item, unwrapping the `ExpressionStmtSyntax`
    /// that wraps a standalone `if` / `switch` used as an implicit-return expression.
    func tailExpression(of item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
        switch item {
        case .expr(let expression):
            return expression

        case .stmt(let statement):
            return statement.as(ExpressionStmtSyntax.self)?.expression

        default:
            return nil
        }
    }

    /// Expands a value-position expression into the leaf value expressions it may evaluate to,
    /// descending through ternary / `if` / `switch` expressions (branch results only) and
    /// unwrapping `try` / `await` / parentheses.
    func resolveTail(_ expression: ExprSyntax) -> [ExprSyntax] {
        if let ternary = expression.as(TernaryExprSyntax.self) {
            return resolveTail(ternary.thenExpression) + resolveTail(ternary.elseExpression)
        }

        if let ifExpr = expression.as(IfExprSyntax.self) {
            return resolveTail(ifExpr)
        }

        if let switchExpr = expression.as(SwitchExprSyntax.self) {
            return switchExpr.cases
                .compactMap { $0.as(SwitchCaseSyntax.self) }
                .flatMap { implicitTail(of: $0.statements) }
        }

        if let tryExpr = expression.as(TryExprSyntax.self) {
            return resolveTail(tryExpr.expression)
        }

        if let awaitExpr = expression.as(AwaitExprSyntax.self) {
            return resolveTail(awaitExpr.expression)
        }

        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1, let only = tuple.elements.first {
            return resolveTail(only.expression)
        }

        return [expression]
    }

    func resolveTail(_ ifExpr: IfExprSyntax) -> [ExprSyntax] {
        var leaves = implicitTail(of: ifExpr.body.statements)

        switch ifExpr.elseBody {
        case .codeBlock(let block):
            leaves += implicitTail(of: block.statements)

        case .ifExpr(let elseIf):
            leaves += resolveTail(elseIf)

        case nil:
            break
        }

        return leaves
    }

    /// `.brand` → "brand"; `.brand.opacity(0.5)` → "brand"; `VStack(...)` / `Color(.x)` /
    /// literals → nil (a call only counts when its callee chain is rooted in a bare member).
    func innermostBareMember(of expression: ExprSyntax) -> String? {
        if let member = expression.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else {
                return member.declName.baseName.text
            }

            return innermostBareMember(of: base)
        }

        if let call = expression.as(FunctionCallExprSyntax.self), call.calledExpression.is(MemberAccessExprSyntax.self) {
            return innermostBareMember(of: call.calledExpression)
        }

        return nil
    }
}
