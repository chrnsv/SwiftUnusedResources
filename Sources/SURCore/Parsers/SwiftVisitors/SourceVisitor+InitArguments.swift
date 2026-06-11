import SwiftSyntax

/// How an initializer-style callee resolves: an explicit type (`Foo(...)`, `Foo.init(...)`,
/// `Outer.Inner(...)`, `Test.image(...)`) or an inferred leading-dot call (`.init(...)`,
/// `.image(...)`) whose type comes from context. `selector` is `"init"` or a factory method name.
private enum InitCalleeKind {
    case explicit(typeName: String, selector: String)
    case inferred(selector: String)
}

/// The synthetic registry/call label for the positional (`_`) parameter/argument at `index`.
/// Keyed by position so distinct positional parameters never collide under a shared empty label.
private func positionalLabel(_ index: Int) -> String {
    "#\(index)"
}

/// Collection of user-type constructor signatures and constructor call sites, used to resolve a
/// resource passed to a user-defined type's initializer or static factory — `CardStyle(icon: .star)`,
/// a type-inferred `Foo(test: .init(image: .cat))`, or a static factory `Foo(test: .image(.frog))`.
/// The registry and pending calls are aggregated and resolved cross-file by `Explorer`, since a
/// declaration and its call site (and its extensions) can live in different files.
extension SourceVisitor {
    /// Type names that can never carry a resource, so they are not recorded as `.named` parameters
    /// (which would only bloat the registry). Kept deliberately conservative — only stdlib scalars.
    private static let nonResourceTypeNames: Set<String> = [
        "String", "Substring", "Character", "Bool",
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Float16", "CGFloat",
        "Date", "URL", "Data", "UUID", "TimeInterval", "Decimal",
    ]

    /// Records a type's constructors into `typeRegistry`: its initializers (selector `"init"`),
    /// a struct's synthesized memberwise init when it declares none, and any static factory methods
    /// returning `Self` or the type itself (selector = method name). Called for the type's own
    /// declaration and for each `extension`, so factories added in extensions are captured too.
    /// `memberwiseFallback` is `true` only for a struct's primary declaration.
    func registerType(
        named name: String,
        members: MemberBlockItemListSyntax,
        memberwiseFallback: Bool
    ) {
        var selectors: TypeConstructors = [:]

        let initializers = members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }

        if !initializers.isEmpty {
            for initializer in initializers {
                let parameters = parameterTypes(of: initializer.signature.parameterClause.parameters)
                selectors["init", default: [:]].merge(parameters) { _, new in new }
            }
        }
        else if memberwiseFallback {
            let parameters = memberwiseParameters(of: members)
            if !parameters.isEmpty {
                selectors["init", default: [:]].merge(parameters) { _, new in new }
            }
        }

        for factory in staticFactories(of: members, returning: name) {
            selectors[factory.selector, default: [:]].merge(factory.parameters) { _, new in new }
        }

        guard !selectors.isEmpty else {
            return
        }

        mergeInitializerRegistry([name: selectors], into: &typeRegistry)
    }

    /// Records an explicit-type constructor call (`Foo(...)`, `Foo.init(...)`, `Outer.Inner(...)`,
    /// `Test.image(...)`) as a pending call to resolve later. Inferred leading-dot calls are not
    /// recorded here — they carry no type on their own and are captured as nested children.
    func collectPendingInit(of node: FunctionCallExprSyntax) {
        guard case .explicit(let typeName, let selector)? = initCalleeKind(of: node.calledExpression) else {
            return
        }

        let pending = buildPendingInit(node, typeName: typeName, selector: selector)

        if !pending.arguments.isEmpty {
            pendingInits.append(pending)
        }
    }

    /// Records inferred leading-dot calls (`.init(...)`, `.image(...)`) found in a value assigned to
    /// a named-user-typed context (`let x: Foo = .init(...)`, a `Foo`/`Self`-returning body, a `Foo`
    /// parameter default), pinning them to the resolved type. Explicit calls are left to
    /// `collectPendingInit`, which captures them via the visitor's own traversal.
    func collectNamedTypeValue(_ expression: ExprSyntax, expectedType: String) {
        for leaf in shallowLeaves(of: expression) {
            guard
                let call = leaf.as(FunctionCallExprSyntax.self),
                case .inferred(let selector)? = initCalleeKind(of: call.calledExpression)
            else {
                continue
            }

            let pending = buildPendingInit(call, typeName: expectedType, selector: selector)

            if !pending.arguments.isEmpty {
                pendingInits.append(pending)
            }
        }
    }

    /// Collects named-type leading-dot values returned (explicitly or implicitly) by a body,
    /// mirroring `collectReturnedAssets` but for nested constructor resolution.
    func collectNamedTypeReturns(in statements: CodeBlockItemListSyntax, expectedType: String) {
        let visitor = ReturnVisitor(viewMode: viewMode)
        statements.forEach { visitor.walk($0) }

        let leaves = visitor.expressions.flatMap { resolveTail($0) } + implicitTail(of: statements)

        leaves.forEach { collectNamedTypeValue($0, expectedType: expectedType) }
    }

    /// The named type an annotation/return clause refers to, resolving `Self` to the enclosing type.
    func resolvedNamedType(for type: TypeSyntax?) -> String? {
        guard let name = namedType(for: type) else {
            return nil
        }

        if name == "Self" {
            return enclosingTypeNames.last.flatMap { $0 }
        }

        return name
    }

    /// The concrete type a constrained protocol extension pins `Self` to via `where Self == X`
    /// (so `.init(...)` in its method bodies resolves to `X`), or `defaultName` when unconstrained.
    func extensionSelfType(of node: ExtensionDeclSyntax, default defaultName: String?) -> String? {
        guard let whereClause = node.genericWhereClause else {
            return defaultName
        }

        for requirement in whereClause.requirements {
            guard case .sameTypeRequirement(let sameType) = requirement.requirement else {
                continue
            }

            let left = namedType(for: sameType.leftType.as(TypeSyntax.self))
            let right = namedType(for: sameType.rightType.as(TypeSyntax.self))

            if left == "Self", let right {
                return right
            }
            if right == "Self", let left {
                return left
            }
        }

        return defaultName
    }

    /// The simple name of a (non-resource) named type, unwrapping `Optional` / `Array` / IUO /
    /// `any` / `some` sugar and generic forms, and taking the final component of a qualified type.
    func namedType(for type: TypeSyntax?) -> String? {
        guard let leaf = unwrappedType(type) else {
            return nil
        }

        if let identifier = leaf.as(IdentifierTypeSyntax.self) {
            let name = identifier.name.text
            return name == "Array" || name == "Optional" ? nil : name
        }

        if let member = leaf.as(MemberTypeSyntax.self) {
            return member.name.text
        }

        return nil
    }

    // MARK: - Building

    /// Builds a `PendingInitCall` from a constructor call, recursively capturing nested inferred
    /// leading-dot arguments. `typeName` is the resolved type (explicit name, the inferred context
    /// type, or `nil` for a nested inferred call resolved from its parameter at resolution time).
    private func buildPendingInit(
        _ call: FunctionCallExprSyntax,
        typeName: String?,
        selector: String
    ) -> PendingInitCall {
        var arguments: [PendingInitArgument] = []

        for (index, argument) in call.arguments.enumerated() {
            var members: [String] = []
            var nestedInits: [PendingInitCall] = []
            resolveArgumentValue(argument.expression, members: &members, nestedInits: &nestedInits)

            guard !members.isEmpty || !nestedInits.isEmpty else {
                continue
            }

            arguments.append(
                PendingInitArgument(
                    label: argument.label?.text ?? positionalLabel(index),
                    members: members,
                    nestedInits: nestedInits
                )
            )
        }

        return PendingInitCall(typeName: typeName, selector: selector, arguments: arguments)
    }

    /// Resolves an argument expression into the bare members it passes directly and the inferred
    /// leading-dot calls it nests. Explicit `Type(...)` / `Type.factory(...)` calls are intentionally
    /// skipped — the visitor records those independently, so nesting them here would double-count.
    private func resolveArgumentValue(
        _ expression: ExprSyntax,
        members: inout [String],
        nestedInits: inout [PendingInitCall]
    ) {
        for leaf in shallowLeaves(of: expression) {
            if
                let call = leaf.as(FunctionCallExprSyntax.self),
                case .inferred(let selector)? = initCalleeKind(of: call.calledExpression) {
                nestedInits.append(buildPendingInit(call, typeName: nil, selector: selector))
            }
            else if let name = innermostBareMember(of: leaf) {
                members.append(name)
            }
        }
    }

    // MARK: - Signature helpers

    /// The `label → parameter type` map of a parameter list, keeping only resource/named-typed ones.
    private func parameterTypes(of parameters: FunctionParameterListSyntax) -> InitParameterMap {
        var result: InitParameterMap = [:]

        for (index, parameter) in parameters.enumerated() {
            guard let type = parameterType(for: parameter.type) else {
                continue
            }

            let label = parameter.firstName.tokenKind == .wildcard
                ? positionalLabel(index)
                : parameter.firstName.text
            result[label] = type
        }

        return result
    }

    /// The memberwise initializer's `label → parameter type` map, from a struct's stored properties.
    /// Computed properties and `let`s with a default value never appear in the synthesized init.
    private func memberwiseParameters(of members: MemberBlockItemListSyntax) -> InitParameterMap {
        var result: InitParameterMap = [:]

        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)

            for binding in variable.bindings {
                guard
                    let type = binding.typeAnnotation?.type,
                    !isComputedProperty(binding.accessorBlock),
                    !(isLet && binding.initializer != nil),
                    let label = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                    let parameterType = parameterType(for: type)
                else {
                    continue
                }

                result[label] = parameterType
            }
        }

        return result
    }

    /// The static factory methods of a type — `static func ...(...) -> Self`/`-> Type` — as
    /// `(selector, parameters)` pairs, so a leading-dot factory call (`.image(.frog)`) resolves
    /// like an alternative initializer.
    private func staticFactories(
        of members: MemberBlockItemListSyntax,
        returning typeName: String
    ) -> [(selector: String, parameters: InitParameterMap)] {
        var factories: [(String, InitParameterMap)] = []

        for member in members {
            guard
                let function = member.decl.as(FunctionDeclSyntax.self),
                function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) })
            else {
                continue
            }

            let returnName = namedType(for: function.signature.returnClause?.type)
            guard returnName == "Self" || returnName == typeName else {
                continue
            }

            let parameters = parameterTypes(of: function.signature.parameterClause.parameters)
            guard !parameters.isEmpty else {
                continue
            }

            factories.append((function.name.text, parameters))
        }

        return factories
    }

    // MARK: - Type helpers

    /// The `InitParameterType` for a parameter/property type: a resource kind if it resolves to
    /// one, else the simple user-type name for nested constructor resolution (excluding stdlib
    /// scalars that can never carry a resource).
    private func parameterType(for type: TypeSyntax?) -> InitParameterType? {
        if let kind = typedKind(for: type) {
            return .resource(kind)
        }

        if let name = namedType(for: type), !Self.nonResourceTypeNames.contains(name) {
            return .named(name)
        }

        return nil
    }

    /// Whether a property's accessor block makes it computed (a getter), as opposed to a stored
    /// property with only `willSet` / `didSet` observers. Shares the getter probing of
    /// `getterStatements(of:)`.
    private func isComputedProperty(_ accessorBlock: AccessorBlockSyntax?) -> Bool {
        getterStatements(of: accessorBlock) != nil
    }

    // MARK: - Callee classification

    /// Classifies a constructor-call callee, or returns `nil` when the call is not a constructor
    /// call we resolve (plain functions, instance methods, deeper member chains).
    private func initCalleeKind(of callee: ExprSyntax) -> InitCalleeKind? {
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            return isTypeName(name) ? .explicit(typeName: name, selector: "init") : nil
        }

        guard let member = callee.as(MemberAccessExprSyntax.self) else {
            return nil
        }

        let name = member.declName.baseName.text

        guard let base = member.base else {
            // Leading-dot, type inferred from context.
            if name == "init" {
                return .inferred(selector: "init")
            }
            // `.image(...)` — a static factory; uppercase leading-dot calls are out of scope.
            return isTypeName(name) ? nil : .inferred(selector: name)
        }

        // Qualified call: the base must name a type; a value base (`view.tint(...)`) is an instance
        // method handled elsewhere.
        guard let baseName = baseTypeName(of: base), isTypeName(baseName) else {
            return nil
        }

        if name == "init" {
            return .explicit(typeName: baseName, selector: "init")
        }

        // `Outer.Inner(...)` — a type-named final component is a nested type's initializer;
        // `Test.image(...)` — a method-named one is a static factory on the base type.
        if isTypeName(name) {
            return .explicit(typeName: name, selector: "init")
        }

        return .explicit(typeName: baseName, selector: name)
    }

    /// Whether an identifier names a type, tolerating leading underscores (`_InternalStyle`) so
    /// generated/internal types are not mistaken for instances.
    private func isTypeName(_ name: String) -> Bool {
        name.drop { $0 == "_" }.first?.isUppercase == true
    }

    /// The final type-name component of a qualified base (`X` in `X.init`, `Type` in `Module.Type.f`).
    private func baseTypeName(of expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }

        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }

        return nil
    }
}
