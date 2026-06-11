import Foundation
import SwiftSyntax

final class SourceVisitor: SyntaxVisitor {
    private let url: URL
    private let showWarnings: Bool
    let kinds: Set<ExploreKind>
    private let memberCallKinds: [String: ExploreKind]
    let propertyKinds: [String: ExploreKind]
    private var hasUIKit = false
    private var hasSwiftUI = false

    private(set) var usages: [ExploreUsage] = []

    /// User-type constructor signatures declared in this file: `typeName → selector → (label → type)`.
    /// Aggregated across files and used to resolve `pendingInits`. Mutated from the
    /// `SourceVisitor+InitArguments` extension, so it carries an internal (not private) setter.
    var typeRegistry: InitializerRegistry = [:]

    /// Explicit-type constructor call sites whose arguments may carry resources, resolved against
    /// `typeRegistry` once every file has contributed.
    var pendingInits: [PendingInitCall] = []

    /// Stack of enclosing type names (struct/class/actor/extension), used to resolve `Self` in a
    /// return clause back to the concrete type so `static func make() -> Self { .init(...) }` resolves.
    /// An entry is `nil` when the enclosing type's name can't be resolved, so `Self` there resolves
    /// to nothing rather than colliding on a shared empty-string sentinel.
    var enclosingTypeNames: [String?] = []

    /// Lexical scope stack of resource-typed variables, used to attribute assignments
    /// (`local = .asset`) to the right kind. The root scope holds file/type-level names;
    /// a new scope is pushed per function-like / type body so a local in one scope does
    /// not leak into same-named variables elsewhere.
    var scopes: [[String: ExploreKind]] = [[:]]

    @discardableResult
    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        showWarnings: Bool,
        kinds: Set<ExploreKind>,
        memberCallKinds: [String: ExploreKind] = SourceVisitor.defaultMemberCallKinds,
        propertyKinds: [String: ExploreKind] = SourceVisitor.defaultPropertyKinds,
        _ url: URL,
        _ node: SourceFileSyntax
    ) {
        self.url = url
        self.showWarnings = showWarnings
        self.kinds = kinds
        self.memberCallKinds = memberCallKinds
        self.propertyKinds = propertyKinds

        super.init(viewMode: viewMode)
        walk(node)
    }
    
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // TODO: get import name without .description
        let imp = node.path.description

        if Self.uiKitModules.contains(imp) {
            hasUIKit = true
        }
        else if Self.swiftUIModules.contains(imp) {
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
        collectPendingInit(of: node)

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
            let type = binding.typeAnnotation?.type

            if let kind = typedKind(for: type) {
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
            else if let typeName = resolvedNamedType(for: type) {
                if let value = binding.initializer?.value {
                    collectNamedTypeValue(value, expectedType: typeName)
                }

                if let statements = getterStatements(of: binding.accessorBlock) {
                    collectNamedTypeReturns(in: statements, expectedType: typeName)
                }
            }
        }

        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()

        collectParameterDefaults(node.signature.parameterClause.parameters)

        let returnType = node.signature.returnClause?.type

        if let kind = typedKind(for: returnType), let body = node.body {
            collectReturnedAssets(in: body.statements, with: kind)
        }
        else if let typeName = resolvedNamedType(for: returnType), let body = node.body {
            collectNamedTypeReturns(in: body.statements, expectedType: typeName)
        }

        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        popScope()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        pushScope()

        let returnType = node.signature?.returnClause?.type

        if let kind = typedKind(for: returnType) {
            collectReturnedAssets(in: node.statements, with: kind)
        }
        else if let typeName = resolvedNamedType(for: returnType) {
            collectNamedTypeReturns(in: node.statements, expectedType: typeName)
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

        collectParameterDefaults(node.signature.parameterClause.parameters)

        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        popScope()
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()

        collectParameterDefaults(node.parameterClause.parameters)

        if let statements = getterStatements(of: node.accessorBlock) {
            if let kind = typedKind(for: node.returnClause.type) {
                collectReturnedAssets(in: statements, with: kind)
            }
            else if let typeName = resolvedNamedType(for: node.returnClause.type) {
                collectNamedTypeReturns(in: statements, expectedType: typeName)
            }
        }

        return .visitChildren
    }

    override func visitPost(_ node: SubscriptDeclSyntax) {
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
        enclosingTypeNames.append(node.name.text)
        registerType(named: node.name.text, members: node.memberBlock.members, memberwiseFallback: false)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popScope()
        enclosingTypeNames.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        enclosingTypeNames.append(node.name.text)
        registerType(named: node.name.text, members: node.memberBlock.members, memberwiseFallback: true)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        popScope()
        enclosingTypeNames.removeLast()
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
        enclosingTypeNames.append(node.name.text)
        registerType(named: node.name.text, members: node.memberBlock.members, memberwiseFallback: false)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        popScope()
        enclosingTypeNames.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()

        // Register factories under the extended type (so a call on `any P` resolves), but resolve
        // `Self` in their bodies to the constrained type from `where Self == X` when present.
        let extendedType = namedType(for: node.extendedType)
        enclosingTypeNames.append(extensionSelfType(of: node, default: extendedType))

        if let extendedType {
            registerType(named: extendedType, members: node.memberBlock.members, memberwiseFallback: false)
        }

        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        popScope()
        enclosingTypeNames.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        enclosingTypeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        popScope()
        enclosingTypeNames.removeLast()
    }
}

extension SourceVisitor {
    /// Records bare members passed to known color/image-taking member calls. Only unlabeled
    /// arguments and arguments labeled `color` are collected, so control labels
    /// (`for:`, `alignment:`, `in:`, …) are never mistaken for assets.
    private func collectMemberCallArguments(of node: FunctionCallExprSyntax) {
        guard
            let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            let kind = memberCallKinds[member.declName.baseName.text],
            kinds.contains(kind)
        else {
            return
        }

        for argument in node.arguments {
            guard argument.label == nil || argument.label?.text == "color" else {
                continue
            }

            collectShallowBareMembers(in: argument.expression, with: kind)
        }
    }

    /// Records the innermost bare member of each resolved leaf (`.brand`, `.brand.opacity(0.5)`,
    /// `[.a, .b]`, `flag ? .a : .b`) WITHOUT the deep subtree walk used for typed contexts —
    /// view-builder arguments like `.background(VStack { ... })` must contribute nothing.
    private func collectShallowBareMembers(in expression: ExprSyntax, with kind: ExploreKind) {
        for leaf in shallowLeaves(of: expression) {
            if let name = innermostBareMember(of: leaf) {
                usages.append(.generated(name, kind))
            }
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

    /// Records assets used as default values of resource-typed parameters,
    /// e.g. `func makeBadge(icon: UIImage = .star)`.
    private func collectParameterDefaults(_ parameters: FunctionParameterListSyntax) {
        for parameter in parameters {
            guard let value = parameter.defaultValue?.value else {
                continue
            }

            if let kind = typedKind(for: parameter.type) {
                collectValue(value, with: kind)
            }
            else if let typeName = resolvedNamedType(for: parameter.type) {
                collectNamedTypeValue(value, expectedType: typeName)
            }
        }
    }

    /// Resolves a value expression (initializer / assignment RHS) and records its bare members.
    func collectValue(_ expression: ExprSyntax, with kind: ExploreKind) {
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
