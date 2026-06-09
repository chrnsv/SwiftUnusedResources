import Foundation
import SwiftSyntax

final class SourceVisitor: SyntaxVisitor {
    private let url: URL
    private let showWarnings: Bool
    private let kinds: Set<ExploreKind>
    private var hasUIKit = false
    private var hasSwiftUI = false
    
    private(set) var usages: [ExploreUsage] = []
    private var typedLocals: [String: ExploreKind] = [:]

    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        showWarnings: Bool,
        kinds: Set<ExploreKind>,
        _ url: URL,
        _ node: SourceFileSyntax
    ) {
        self.url = url
        self.showWarnings = showWarnings
        self.kinds = kinds
        
        super.init(viewMode: viewMode)
        walk(node)
    }
    
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // TODO: get import name without .description
        let imp = node.path.description
        
        if imp == "UIKit" || imp == "WatchKit" {
            hasUIKit = true
        }
        else if imp == "SwiftUI" {
            hasSwiftUI = true
        }
        
        return .skipChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let newUsages = kinds
            .map { FuncCallVisitor(url, node, kind: $0, uiKit: hasUIKit, swiftUI: hasSwiftUI, showWarnings: showWarnings) }
            .flatMap { $0.usages }
        
        usages.append(contentsOf: newUsages)
        
        return super.visit(node)
    }
    
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        guard let kind = ExploreKind(literal: node.macroName.text) else {
            return .skipChildren
        }
        
        let visitor = LiteralVisitor(node, kind: kind)
        usages.append(contentsOf: visitor.usages)
        
        return .skipChildren
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let newUsages = kinds
            .compactMap { findR(in: node, with: $0) ?? findGeneratedAsset(in: node, with: $0) }

        guard !newUsages.isEmpty else {
            return .visitChildren
        }

        usages.append(contentsOf: newUsages)

        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let kind = typedKind(for: binding.typeAnnotation?.type) else {
                continue
            }

            if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                typedLocals[name] = kind
            }

            if let value = binding.initializer?.value {
                collectValue(value, with: kind)
            }

            if let statements = getterStatements(of: binding.accessorBlock) {
                collectReturnedAssets(in: statements, with: kind)
            }
        }

        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let kind = typedKind(for: node.signature.returnClause?.type), let body = node.body {
            collectReturnedAssets(in: body.statements, with: kind)
        }

        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if let kind = typedKind(for: node.signature?.returnClause?.type) {
            collectReturnedAssets(in: node.statements, with: kind)
        }

        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = node.elements.array()

        guard
            elements.count >= 3,
            elements[1].is(AssignmentExprSyntax.self),
            let lhs = elements.first?.as(DeclReferenceExprSyntax.self),
            let kind = typedLocals[lhs.baseName.text]
        else {
            return .visitChildren
        }

        let rhs = Array(elements.dropFirst(2))

        if rhs.count == 1 {
            collectValue(rhs[0], with: kind)
        }
        else {
            rhs.forEach { collectBareMembers(in: $0, with: kind) }
        }

        return .visitChildren
    }
}

extension SourceVisitor {
    private func findR(
        in node: DeclReferenceExprSyntax,
        with kind: ExploreKind
    ) -> ExploreUsage? {
        guard node.baseName.text == "R" else {
            return nil
        }
        
        let members = members(in: node).dropFirst()
        
        guard members.first == kind.rawValue, let name = members.dropFirst().first else {
            return nil
        }
        
        return .rswift(name, kind)
    }
    
    private func findGeneratedAsset(
        in node: DeclReferenceExprSyntax,
        with kind: ExploreKind
    ) -> ExploreUsage? {
        guard [kind.uiClassName, kind.swiftUIClassName, kind.resourceClassName].contains(node.baseName.text) else {
            return nil
        }
        
        if let parent = node.parent?.as(FunctionCallExprSyntax.self) {
            guard parent.arguments.count == 1, let member = parent.arguments.last?.expression.as(MemberAccessExprSyntax.self) else {
                return nil
            }
            
            return .generated(member.declName.baseName.text, kind)
        }
        else {
            let members = members(in: node)
            
            guard members.count == 2, let name = members.last else {
                return nil
            }
            
            return .generated(name, kind)
        }
    }
    
    private func members(in node: DeclReferenceExprSyntax) -> some RandomAccessCollection<String> {
        guard let parent = node.parent?.as(MemberAccessExprSyntax.self) else {
            return []
        }
        
        let usage = sequence(first: parent) { $0.parent?.as(MemberAccessExprSyntax.self) }
            .array()
            .last
        
        guard let usage else {
            return []
        }
        
        let visitor = MemberVisitor(viewMode: viewMode)

        visitor.walk(usage)

        return visitor.members
    }

    /// Resolves a type annotation/return clause to the resource kind it refers to,
    /// unwrapping `Optional`, implicitly-unwrapped optionals and `Array` (both sugar and generic forms).
    private func typedKind(for type: TypeSyntax?) -> ExploreKind? {
        guard let type else {
            return nil
        }

        if let optional = type.as(OptionalTypeSyntax.self) {
            return typedKind(for: optional.wrappedType)
        }

        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return typedKind(for: optional.wrappedType)
        }

        if let array = type.as(ArrayTypeSyntax.self) {
            return typedKind(for: array.element)
        }

        guard let identifier = type.as(IdentifierTypeSyntax.self) else {
            return nil
        }

        let name = identifier.name.text

        if name == "Array" || name == "Optional" {
            if let argument = identifier.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
                return typedKind(for: argument)
            }
            return nil
        }

        let kind = kinds.first { $0.resourceClassName == name }

        return kind
    }

    /// Returns the statements of a property's `get` accessor, covering both the
    /// shorthand `{ ... }` getter and an explicit `get { ... }` accessor.
    private func getterStatements(of accessorBlock: AccessorBlockSyntax?) -> CodeBlockItemListSyntax? {
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

    /// Collects every asset returned by a body — both explicit `return`s (anywhere in the body,
    /// excluding nested scopes) and the implicit-return trailing expression — resolving through
    /// `if` / `switch` / ternary branches without ever touching conditions or `case` patterns.
    private func collectReturnedAssets(in statements: CodeBlockItemListSyntax, with kind: ExploreKind) {
        let visitor = ReturnVisitor(viewMode: viewMode)
        statements.forEach { visitor.walk($0) }

        let leaves = visitor.expressions.flatMap { resolveTail($0) } + implicitTail(of: statements)

        leaves.forEach { collectBareMembers(in: $0, with: kind) }
    }

    /// Resolves the implicit-return value of a block: if its last item is an expression,
    /// expand it through control-flow value positions; otherwise nothing.
    private func implicitTail(of statements: CodeBlockItemListSyntax) -> [ExprSyntax] {
        guard let last = statements.last, let expression = tailExpression(of: last.item) else {
            return []
        }

        return resolveTail(expression)
    }

    /// The value expression of a trailing code-block item, unwrapping the `ExpressionStmtSyntax`
    /// that wraps a standalone `if` / `switch` used as an implicit-return expression.
    private func tailExpression(of item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
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
    private func resolveTail(_ expression: ExprSyntax) -> [ExprSyntax] {
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

    private func resolveTail(_ ifExpr: IfExprSyntax) -> [ExprSyntax] {
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

    /// Resolves a value expression (initializer / assignment RHS) and records its bare members.
    private func collectValue(_ expression: ExprSyntax, with kind: ExploreKind) {
        resolveTail(expression).forEach { collectBareMembers(in: $0, with: kind) }
    }

    /// Records every bare member access (`.assetName`, i.e. with no base) found in `expression`
    /// as a `.generated` usage. Handles array literals and member chains.
    private func collectBareMembers(in expression: some SyntaxProtocol, with kind: ExploreKind) {
        let visitor = BareMemberVisitor(viewMode: viewMode)
        visitor.walk(expression)

        usages.append(contentsOf: visitor.names.map { .generated($0, kind) })
    }
}

private extension ExploreKind {
    init?(literal: String) {
        switch literal {
        case "imageLiteral": self = .image
        case "colorLiteral": self = .color
        default: return nil
        }
    }
}

private extension SourceVisitor {
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
