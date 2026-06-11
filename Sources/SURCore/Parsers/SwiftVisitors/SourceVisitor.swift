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

    /// User-type initializer signatures declared in this file: `typeName → (label → parameter type)`.
    /// Aggregated across files and used to resolve `pendingInits`. Mutated from the
    /// `SourceVisitor+InitArguments` extension, so it carries an internal (not private) setter.
    var typeRegistry: [String: [String: InitParameterType]] = [:]

    /// Explicit-type initializer call sites whose arguments may carry resources, resolved against
    /// `typeRegistry` once every file has contributed.
    var pendingInits: [PendingInitCall] = []

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
            else if let typeName = namedType(for: type) {
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
        else if let typeName = namedType(for: returnType), let body = node.body {
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
        else if let typeName = namedType(for: returnType) {
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
            else if let typeName = namedType(for: node.returnClause.type) {
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
        registerType(named: node.name.text, members: node.memberBlock.members, memberwiseFallback: false)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        popScope()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope()
        registerType(named: node.name.text, members: node.memberBlock.members, memberwiseFallback: true)
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
        registerType(named: node.name.text, members: node.memberBlock.members, memberwiseFallback: false)
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
        guard Self.generatedClassKinds[node.baseName.text] == kind else {
            return nil
        }

        if let call = initializerCall(of: node) {
            // collectValue resolves ternary / if / switch branches before recording, so
            // `UIImage(resource: flag ? .a : .b)` records both assets. Usages are appended
            // directly; a DeclRef has no children worth skipping, so returning nil is fine.
            if call.arguments.count == 1, let argument = call.arguments.first {
                collectValue(argument.expression, with: kind)
            }

            return nil
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
        for leaf in resolveTail(expression) {
            if let array = leaf.as(ArrayExprSyntax.self) {
                array.elements.forEach { collectShallowBareMembers(in: $0.expression, with: kind) }
            }
            else if let sequence = leaf.as(SequenceExprSyntax.self) {
                // The parser does not fold operators, so a ternary argument arrives as a flat
                // sequence: `flag ? .a : .b` → [flag, UnresolvedTernary(.a), .b]. Collect from
                // each operand; the unresolved-ternary element carries the `then` branch.
                for element in sequence.elements {
                    let unwrapped = element.as(UnresolvedTernaryExprSyntax.self)?.thenExpression ?? element
                    collectShallowBareMembers(in: unwrapped, with: kind)
                }
            }
            else if let name = innermostBareMember(of: leaf) {
                usages.append(.generated(name, kind))
            }
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
            else if let typeName = namedType(for: parameter.type) {
                collectNamedTypeValue(value, expectedType: typeName)
            }
        }
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
