import Foundation
import SwiftSyntax

final class SourceVisitor: SyntaxVisitor {
    private let url: URL
    private let showWarnings: Bool
    private let kinds: Set<ExploreKind>
    private var hasUIKit = false
    private var hasSwiftUI = false
    
    private(set) var usages: [ExploreUsage] = []

    /// Lexical scope stack of resource-typed variables, used to attribute assignments
    /// (`local = .asset`) to the right kind. The root scope holds file/type-level names;
    /// a new scope is pushed per function-like / type body so a local in one scope does
    /// not leak into same-named variables elsewhere.
    private var scopes: [[String: ExploreKind]] = [[:]]

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

        collectMemberCallArguments(of: node)

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
                declareTypedVariable(name, kind)
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
        pushScope()

        if let kind = typedKind(for: node.signature.returnClause?.type), let body = node.body {
            collectReturnedAssets(in: body.statements, with: kind)
        }

        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        pushScope()

        if let kind = typedKind(for: node.signature?.returnClause?.type) {
            collectReturnedAssets(in: node.statements, with: kind)
        }

        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        popScope()
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = node.elements.array()

        guard
            elements.count >= 3,
            elements[1].is(AssignmentExprSyntax.self),
            let lhs = elements.first,
            let kind = assignedKind(of: lhs)
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

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        popScope()
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popScope()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popScope()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popScope()
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
        guard kind.generatedClassNames.contains(node.baseName.text) else {
            return nil
        }

        if let call = initializerCall(of: node) {
            guard call.arguments.count == 1, let member = call.arguments.last?.expression.as(MemberAccessExprSyntax.self) else {
                return nil
            }

            return .generated(member.declName.baseName.text, kind)
        }
        else {
            var members = members(in: node).array()

            if let first = members.first, Self.assetModules.contains(first) {
                members.removeFirst()
            }

            // `members.first == baseName` rejects chains rooted in an unknown namespace:
            // in `MyKit.Image.star` the first member is `MyKit`, so `Image` there is some
            // custom type, not the SwiftUI one.
            guard members.count >= 2, members.first == node.baseName.text else {
                return nil
            }

            let name = members[1]

            // Asset symbols can never be named `init`; `UIImage.init(named:)` is not an asset.
            guard name != "init" else {
                return nil
            }

            return .generated(name, kind)
        }
    }

    /// Records bare members passed to known color/image-taking member calls. Only unlabeled
    /// arguments and arguments labeled `color` are collected, so control labels
    /// (`for:`, `alignment:`, `in:`, …) are never mistaken for assets.
    private func collectMemberCallArguments(of node: FunctionCallExprSyntax) {
        guard
            let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            let kind = Self.memberCallKinds[member.declName.baseName.text],
            kinds.contains(kind)
        else {
            return
        }

        for argument in node.arguments {
            guard argument.label == nil || argument.label?.text == "color" else {
                continue
            }

            collectValue(argument.expression, with: kind)
        }
    }

    /// The call node when `node` is the called type of an initializer call — either plain
    /// `UIImage(...)` or module-qualified `SwiftUI.Image(...)`.
    private func initializerCall(of node: DeclReferenceExprSyntax) -> FunctionCallExprSyntax? {
        if let call = node.parent?.as(FunctionCallExprSyntax.self) {
            return call
        }

        guard
            let member = node.parent?.as(MemberAccessExprSyntax.self),
            member.declName.id == node.id,
            let base = member.base?.as(DeclReferenceExprSyntax.self),
            Self.assetModules.contains(base.baseName.text)
        else {
            return nil
        }

        return member.parent?.as(FunctionCallExprSyntax.self)
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

    private func pushScope() {
        scopes.append([:])
    }

    private func popScope() {
        if scopes.count > 1 {
            scopes.removeLast()
        }
    }

    /// Records a resource-typed variable in the current (innermost) scope.
    private func declareTypedVariable(_ name: String, _ kind: ExploreKind) {
        scopes[scopes.count - 1][name] = kind
    }

    /// Looks a variable up from the innermost scope outwards, so a local shadows
    /// an enclosing declaration and names do not leak between sibling scopes.
    private func resolveTypedVariable(_ name: String) -> ExploreKind? {
        for scope in scopes.reversed() {
            if let kind = scope[name] {
                return kind
            }
        }

        return nil
    }

    /// The resource kind an assignment target carries: a tracked resource-typed variable,
    /// or a well-known UIKit color/image property on any object — `label.textColor`,
    /// chained `cell.titleLabel.textColor`, explicit `self.tintColor` or implicit-self
    /// `textColor`.
    private func assignedKind(of expression: ExprSyntax) -> ExploreKind? {
        if let name = assignmentTargetName(expression), let kind = resolveTypedVariable(name) {
            return kind
        }

        let name: String? =
            if let member = expression.as(MemberAccessExprSyntax.self) {
                member.declName.baseName.text
            }
            else if let reference = expression.as(DeclReferenceExprSyntax.self) {
                reference.baseName.text
            }
            else {
                nil
            }

        guard let name, let kind = Self.propertyKinds[name], kinds.contains(kind) else {
            return nil
        }

        return kind
    }

    /// The tracked variable name an assignment targets: a bare `name` or an implicit-self
    /// `self.name`. Other member-access targets (`other.name`) are ignored, as they refer
    /// to a different object and would otherwise be misattributed to a same-named local.
    private func assignmentTargetName(_ expression: ExprSyntax) -> String? {
        if let declReference = expression.as(DeclReferenceExprSyntax.self) {
            return declReference.baseName.text
        }

        guard let member = expression.as(MemberAccessExprSyntax.self) else {
            return nil
        }

        if let base = member.base?.as(DeclReferenceExprSyntax.self), base.baseName.text == "self" {
            return member.declName.baseName.text
        }

        return nil
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
            return memberTypedKind(for: type)
        }

        let name = identifier.name.text

        if name == "Array" || name == "Optional" {
            if let argument = identifier.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
                return typedKind(for: argument)
            }
            return nil
        }

        let kind = kinds.first { $0.generatedClassNames.contains(name) }

        return kind
    }

    /// Resolves a module-qualified type annotation like `SwiftUI.Image` or `UIKit.UIColor`.
    private func memberTypedKind(for type: TypeSyntax) -> ExploreKind? {
        guard
            let member = type.as(MemberTypeSyntax.self),
            let base = member.baseType.as(IdentifierTypeSyntax.self),
            Self.assetModules.contains(base.name.text)
        else {
            return nil
        }

        return kinds.first { $0.generatedClassNames.contains(member.name.text) }
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
