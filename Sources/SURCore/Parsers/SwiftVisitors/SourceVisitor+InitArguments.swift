import SwiftSyntax

/// Collection of user-type constructor signatures and constructor call sites, used to resolve a
/// resource passed to a user-defined type's initializer or static factory — `CardStyle(icon: .star)`,
/// a type-inferred `Foo(test: .init(image: .cat))`, or a static factory `Foo(test: .image(.frog))`.
/// The registry and pending calls are aggregated and resolved cross-file by `Explorer`, since a
/// declaration and its call site (and its extensions) can live in different files.
extension SourceVisitor {
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
        var selectors: [String: [String: InitParameterType]] = [:]

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

        let pending = buildPendingInit(node, fallbackType: typeName, selector: selector)

        if !pending.arguments.isEmpty {
            pendingInits.append(pending)
        }
    }

    /// Records inferred leading-dot calls (`.init(...)`, `.image(...)`) found in a value assigned to
    /// a named-user-typed context (`let x: Foo = .init(...)`, a `Foo`/`Self`-returning body, a `Foo`
    /// parameter default), pinning them to the resolved type. Explicit calls are left to
    /// `collectPendingInit`, which captures them via the visitor's own traversal.
    func collectNamedTypeValue(_ expression: ExprSyntax, expectedType: String) {
        for leaf in resolveTail(expression) {
            if let array = leaf.as(ArrayExprSyntax.self) {
                array.elements.forEach { collectNamedTypeValue($0.expression, expectedType: expectedType) }
            }
            else if
                let call = leaf.as(FunctionCallExprSyntax.self),
                case .inferred(let selector)? = initCalleeKind(of: call.calledExpression) {
                let pending = buildPendingInit(call, fallbackType: expectedType, selector: selector)
                if !pending.arguments.isEmpty {
                    pendingInits.append(pending)
                }
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

        return name == "Self" ? enclosingTypeNames.last : name
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

    // MARK: - Building

    /// Builds a `PendingInitCall` from a constructor call, recursively capturing nested inferred
    /// leading-dot arguments. `fallbackType` supplies the type for an inferred callee (from the
    /// enclosing parameter or annotation); an explicit callee uses its own type name.
    private func buildPendingInit(
        _ call: FunctionCallExprSyntax,
        fallbackType: String?,
        selector: String
    ) -> PendingInitCall {
        let typeName: String?
        switch initCalleeKind(of: call.calledExpression) {
        case .explicit(let name, _): typeName = name
        case .inferred, nil: typeName = fallbackType
        }

        var arguments: [PendingInitArgument] = []

        for argument in call.arguments {
            var members: [String] = []
            var nestedInits: [PendingInitCall] = []
            resolveArgumentValue(argument.expression, members: &members, nestedInits: &nestedInits)

            guard !members.isEmpty || !nestedInits.isEmpty else {
                continue
            }

            arguments.append(
                PendingInitArgument(
                    label: argument.label?.text ?? "",
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
        for leaf in resolveTail(expression) {
            if let array = leaf.as(ArrayExprSyntax.self) {
                for element in array.elements {
                    resolveArgumentValue(element.expression, members: &members, nestedInits: &nestedInits)
                }
            }
            else if let sequence = leaf.as(SequenceExprSyntax.self) {
                // Unfolded ternary argument: `flag ? .a : .b` arrives as a flat sequence whose
                // `then` branch hides inside an UnresolvedTernaryExprSyntax element.
                for element in sequence.elements {
                    let unwrapped = element.as(UnresolvedTernaryExprSyntax.self)?.thenExpression ?? element
                    resolveArgumentValue(unwrapped, members: &members, nestedInits: &nestedInits)
                }
            }
            else if let call = leaf.as(FunctionCallExprSyntax.self),
                    case .inferred(let selector)? = initCalleeKind(of: call.calledExpression) {
                nestedInits.append(buildPendingInit(call, fallbackType: nil, selector: selector))
            }
            else if let name = innermostBareMember(of: leaf) {
                members.append(name)
            }
        }
    }

    // MARK: - Signature helpers

    /// The `label → parameter type` map of a parameter list, keeping only resource/named-typed ones.
    private func parameterTypes(of parameters: FunctionParameterListSyntax) -> [String: InitParameterType] {
        var result: [String: InitParameterType] = [:]

        for parameter in parameters {
            guard let type = parameterType(for: parameter.type) else {
                continue
            }

            let label = parameter.firstName.tokenKind == .wildcard ? "" : parameter.firstName.text
            result[label] = type
        }

        return result
    }

    /// The memberwise initializer's `label → parameter type` map, from a struct's stored properties.
    /// Computed properties and `let`s with a default value never appear in the synthesized init.
    private func memberwiseParameters(of members: MemberBlockItemListSyntax) -> [String: InitParameterType] {
        var result: [String: InitParameterType] = [:]

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
    ) -> [(selector: String, parameters: [String: InitParameterType])] {
        var factories: [(String, [String: InitParameterType])] = []

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
    /// one, else the simple user-type name for nested constructor resolution.
    private func parameterType(for type: TypeSyntax?) -> InitParameterType? {
        if let kind = typedKind(for: type) {
            return .resource(kind)
        }

        if let name = namedType(for: type) {
            return .named(name)
        }

        return nil
    }

    /// The simple name of a (non-resource) named type, unwrapping `Optional` / `Array` / IUO
    /// sugar and generic forms, and taking the final component of a module-qualified type.
    func namedType(for type: TypeSyntax?) -> String? {
        guard let type else {
            return nil
        }

        if let optional = type.as(OptionalTypeSyntax.self) {
            return namedType(for: optional.wrappedType)
        }

        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return namedType(for: optional.wrappedType)
        }

        if let array = type.as(ArrayTypeSyntax.self) {
            return namedType(for: array.element)
        }

        // `any TestProtocol` / `some TestProtocol` → the constraint's name.
        if let someOrAny = type.as(SomeOrAnyTypeSyntax.self) {
            return namedType(for: someOrAny.constraint)
        }

        if let identifier = type.as(IdentifierTypeSyntax.self) {
            let name = identifier.name.text

            if name == "Array" || name == "Optional" {
                if let argument = identifier.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
                    return namedType(for: argument)
                }
                return nil
            }

            return name
        }

        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }

        return nil
    }

    /// Whether a property's accessor block makes it computed (a shorthand or explicit `get`),
    /// as opposed to a stored property with only `willSet` / `didSet` observers.
    private func isComputedProperty(_ accessorBlock: AccessorBlockSyntax?) -> Bool {
        guard let accessorBlock else {
            return false
        }

        switch accessorBlock.accessors {
        case .getter:
            return true

        case .accessors(let accessors):
            return accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
        }
    }

    // MARK: - Callee classification

    private enum InitCalleeKind {
        /// `Foo(...)`, `Foo.init(...)`, `Outer.Inner(...)`, `Test.image(...)` — type and selector known.
        case explicit(typeName: String, selector: String)
        /// `.init(...)`, `.image(...)` — the type is inferred from context; the selector is known.
        case inferred(selector: String)
    }

    /// Classifies a constructor-call callee, or returns `nil` when the call is not a constructor
    /// call we resolve (plain functions, instance methods, deeper member chains).
    private func initCalleeKind(of callee: ExprSyntax) -> InitCalleeKind? {
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            return name.first?.isUppercase == true ? .explicit(typeName: name, selector: "init") : nil
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
            return name.first?.isLowercase == true ? .inferred(selector: name) : nil
        }

        // Qualified call: the base must name a type (uppercase final component); a lowercase base
        // (`view.tint(...)`) is an instance method handled elsewhere.
        guard let baseName = baseTypeName(of: base), baseName.first?.isUppercase == true else {
            return nil
        }

        if name == "init" {
            return .explicit(typeName: baseName, selector: "init")
        }

        // `Outer.Inner(...)` — an uppercase final component is a nested type's initializer;
        // `Test.image(...)` — a lowercase one is a static factory on the base type.
        if name.first?.isUppercase == true {
            return .explicit(typeName: name, selector: "init")
        }

        return .explicit(typeName: baseName, selector: name)
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
