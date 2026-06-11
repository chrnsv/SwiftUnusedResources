import SwiftSyntax

/// Scope-stack management and type-annotation resolution for the visitor's
/// tracking of resource-typed variables. Kept separate from the visit overrides.
extension SourceVisitor {
    func pushScope() {
        scopes.append([:])
    }

    func popScope() {
        if scopes.count > 1 {
            scopes.removeLast()
        }
    }

    /// Records a resource-typed variable in the current (innermost) scope.
    func declareTypedVariable(_ name: String, _ kind: ExploreKind) {
        scopes[scopes.count - 1][name] = kind
    }

    /// Looks a variable up from the innermost scope outwards, so a local shadows
    /// an enclosing declaration and names do not leak between sibling scopes.
    func resolveTypedVariable(_ name: String) -> ExploreKind? {
        for scope in scopes.reversed() {
            if let kind = scope[name] {
                return kind
            }
        }

        return nil
    }

    /// The resource kind an assignment target carries: a tracked resource-typed variable,
    /// or a well-known UIKit color/image property accessed on some object — `label.textColor`,
    /// chained `cell.titleLabel.textColor`, explicit `self.tintColor`. Bare identifiers are
    /// deliberately NOT matched against the curated names: `image = .remote` is far more
    /// likely a plain local than an implicit-self UIKit property (write `self.image` for those),
    /// and matching it would mask unused assets behind common variable names.
    func assignedKind(of expression: ExprSyntax) -> ExploreKind? {
        if let name = assignmentTargetName(expression), let kind = resolveTypedVariable(name) {
            return kind
        }

        guard
            let name = expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
            let kind = propertyKinds[name],
            kinds.contains(kind)
        else {
            return nil
        }

        return kind
    }

    /// The tracked variable name an assignment targets: a bare `name` or an implicit-self
    /// `self.name`. Other member-access targets (`other.name`) are ignored, as they refer
    /// to a different object and would otherwise be misattributed to a same-named local.
    func assignmentTargetName(_ expression: ExprSyntax) -> String? {
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
    func typedKind(for type: TypeSyntax?) -> ExploreKind? {
        guard let leaf = unwrappedType(type) else {
            return nil
        }

        guard let identifier = leaf.as(IdentifierTypeSyntax.self) else {
            return memberTypedKind(for: leaf)
        }

        let name = identifier.name.text

        if name == "Array" || name == "Optional" {
            return nil
        }

        return kind(forTypeName: name)
    }

    /// Strips `Optional` / implicitly-unwrapped-optional / `Array` / `any` / `some` sugar (and the
    /// `Array<>` / `Optional<>` generic forms) down to the innermost type. Shared by `typedKind`
    /// and `namedType`. A bare `Array` / `Optional` with no generic argument is returned unchanged
    /// (it denotes neither a resource nor a user type).
    func unwrappedType(_ type: TypeSyntax?) -> TypeSyntax? {
        guard let type else {
            return nil
        }

        if let optional = type.as(OptionalTypeSyntax.self) {
            return unwrappedType(optional.wrappedType)
        }

        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return unwrappedType(optional.wrappedType)
        }

        if let array = type.as(ArrayTypeSyntax.self) {
            return unwrappedType(array.element)
        }

        if let someOrAny = type.as(SomeOrAnyTypeSyntax.self) {
            return unwrappedType(someOrAny.constraint)
        }

        if
            let identifier = type.as(IdentifierTypeSyntax.self),
            identifier.name.text == "Array" || identifier.name.text == "Optional",
            let argument = identifier.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
            return unwrappedType(argument)
        }

        return type
    }

    /// Resolves a module-qualified type annotation like `SwiftUI.Image` or `UIKit.UIColor`.
    func memberTypedKind(for type: TypeSyntax) -> ExploreKind? {
        guard
            let member = type.as(MemberTypeSyntax.self),
            let base = member.baseType.as(IdentifierTypeSyntax.self),
            Self.assetModules.contains(base.name.text)
        else {
            return nil
        }

        return kind(forTypeName: member.name.text)
    }

    /// The explored kind whose generated symbols live on the type with this name, if any.
    func kind(forTypeName name: String) -> ExploreKind? {
        guard let kind = Self.generatedClassKinds[name], kinds.contains(kind) else {
            return nil
        }

        return kind
    }
}
