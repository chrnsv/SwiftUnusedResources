import SwiftSyntax

/// Collection of user-type initializer signatures and initializer call sites, used to
/// resolve a resource passed as an argument to a user-defined type's initializer —
/// `CardStyle(icon: .star)` or, with the type inferred from the parameter,
/// `Foo(test: .init(image: .cat))`. The registry and pending calls are aggregated and
/// resolved cross-file by `Explorer`, since the declaration and the call site can live
/// in different files.
extension SourceVisitor {
    /// Records the resource/named-type parameters of a type declaration into `typeRegistry`.
    /// When the type declares initializers, their parameters define the labels; otherwise a
    /// struct's stored properties define its memberwise-init labels. `memberwiseFallback` is
    /// `true` only for structs — classes and actors have no synthesized memberwise init.
    func registerType(
        named name: String,
        members: MemberBlockItemListSyntax,
        memberwiseFallback: Bool
    ) {
        var parameters: [String: InitParameterType] = [:]

        let initializers = members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }

        if !initializers.isEmpty {
            for initializer in initializers {
                for parameter in initializer.signature.parameterClause.parameters {
                    guard let type = parameterType(for: parameter.type) else {
                        continue
                    }

                    let label = parameter.firstName.tokenKind == .wildcard ? "" : parameter.firstName.text
                    parameters[label] = type
                }
            }
        }
        else if memberwiseFallback {
            for member in members {
                guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                    continue
                }

                let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)

                for binding in variable.bindings {
                    // Computed properties and `let`s with a default value never appear in the
                    // synthesized memberwise initializer, so they contribute no call label.
                    guard
                        let type = binding.typeAnnotation?.type,
                        !isComputedProperty(binding.accessorBlock),
                        !(isLet && binding.initializer != nil),
                        let label = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                        let parameterType = parameterType(for: type)
                    else {
                        continue
                    }

                    parameters[label] = parameterType
                }
            }
        }

        guard !parameters.isEmpty else {
            return
        }

        typeRegistry[name, default: [:]].merge(parameters) { _, new in new }
    }

    /// Records an explicit-type initializer call (`Foo(...)`, `Foo.init(...)`, `Outer.Inner(...)`)
    /// as a pending call to resolve later. Inferred `.init(...)` calls are not recorded here —
    /// they carry no type on their own and are captured as nested children of their enclosing call.
    func collectPendingInit(of node: FunctionCallExprSyntax) {
        guard case .explicit(let typeName)? = initCalleeKind(of: node.calledExpression) else {
            return
        }

        let pending = buildPendingInit(node, fallbackType: typeName)

        if !pending.arguments.isEmpty {
            pendingInits.append(pending)
        }
    }

    /// Records `.init(...)` / explicit calls found in a value assigned to a named-user-typed
    /// context (`let x: Foo = .init(...)`, a `Foo`-returning body, a `Foo` parameter default),
    /// pinning the inferred `.init` to the annotated type. Explicit calls are left to
    /// `collectPendingInit`, which captures them via the visitor's own traversal.
    func collectNamedTypeValue(_ expression: ExprSyntax, expectedType: String) {
        for leaf in resolveTail(expression) {
            if let array = leaf.as(ArrayExprSyntax.self) {
                array.elements.forEach { collectNamedTypeValue($0.expression, expectedType: expectedType) }
            }
            else if
                let call = leaf.as(FunctionCallExprSyntax.self),
                case .inferred? = initCalleeKind(of: call.calledExpression) {
                let pending = buildPendingInit(call, fallbackType: expectedType)
                if !pending.arguments.isEmpty {
                    pendingInits.append(pending)
                }
            }
        }
    }

    /// Collects named-type `.init` values returned (explicitly or implicitly) by a body,
    /// mirroring `collectReturnedAssets` but for nested-init resolution.
    func collectNamedTypeReturns(in statements: CodeBlockItemListSyntax, expectedType: String) {
        let visitor = ReturnVisitor(viewMode: viewMode)
        statements.forEach { visitor.walk($0) }

        let leaves = visitor.expressions.flatMap { resolveTail($0) } + implicitTail(of: statements)

        leaves.forEach { collectNamedTypeValue($0, expectedType: expectedType) }
    }

    // MARK: - Building

    /// Builds a `PendingInitCall` from an initializer call, recursively capturing nested inferred
    /// `.init(...)` arguments. `fallbackType` supplies the type for an inferred callee (from the
    /// enclosing parameter or annotation); an explicit callee uses its own type name.
    private func buildPendingInit(_ call: FunctionCallExprSyntax, fallbackType: String?) -> PendingInitCall {
        let typeName: String?
        switch initCalleeKind(of: call.calledExpression) {
        case .explicit(let name): typeName = name
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

        return PendingInitCall(typeName: typeName, arguments: arguments)
    }

    /// Resolves an argument expression into the bare members it passes directly and the inferred
    /// `.init(...)` calls it nests. Explicit `Type(...)` calls are intentionally skipped — the
    /// visitor records those independently, so nesting them here would double-count.
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
                    case .inferred? = initCalleeKind(of: call.calledExpression) {
                nestedInits.append(buildPendingInit(call, fallbackType: nil))
            }
            else if let name = innermostBareMember(of: leaf) {
                members.append(name)
            }
        }
    }

    // MARK: - Type helpers

    /// The `InitParameterType` for a parameter/property type: a resource kind if it resolves to
    /// one, else the simple user-type name for nested-init resolution.
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
        /// `Foo(...)`, `Foo.init(...)`, `Outer.Inner(...)` — the type name is known.
        case explicit(String)
        /// `.init(...)` — the type is inferred from the enclosing context.
        case inferred
    }

    /// Classifies an initializer-call callee, or returns `nil` when the call is not an
    /// initializer-style call we resolve (lowercase function/method calls, member chains).
    private func initCalleeKind(of callee: ExprSyntax) -> InitCalleeKind? {
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            return name.first?.isUppercase == true ? .explicit(name) : nil
        }

        guard let member = callee.as(MemberAccessExprSyntax.self) else {
            return nil
        }

        let name = member.declName.baseName.text

        if name == "init" {
            // `Type.init(...)` carries its type in the base; bare `.init(...)` is inferred.
            if let base = member.base, let typeName = baseTypeName(of: base) {
                return .explicit(typeName)
            }
            return .inferred
        }

        // `Outer.Inner(...)` — an uppercase final component is a nested type initializer;
        // a lowercase one (`view.tint(...)`) is a method call handled elsewhere.
        return name.first?.isUppercase == true ? .explicit(name) : nil
    }

    /// The final type-name component of a `.init` base (`X` in `X.init`, `Inner` in `A.Inner.init`).
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
