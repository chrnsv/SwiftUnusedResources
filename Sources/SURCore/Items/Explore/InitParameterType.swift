import Foundation

/// The kind of value an initializer parameter (or memberwise stored property) accepts,
/// as far as asset detection cares: either a resource directly, or another user type
/// whose own initializer may carry resources (enabling nested `.init` resolution).
enum InitParameterType: Sendable, Equatable {
    /// A resource-typed parameter, e.g. `ImageResource` → `.resource(.image)`.
    case resource(ExploreKind)

    /// A parameter typed as some user type by simple name, e.g. `Test` → `.named("Test")`.
    /// Used to resolve a nested `.init(...)` whose type is inferred from this parameter.
    case named(String)
}

/// A collected initializer call site, recorded during parsing and resolved against the
/// cross-file type registry afterwards. `typeName` is the explicit callee type
/// (`Foo(...)`, `Foo.init(...)`, `Outer.Inner(...)`), or `nil` for an inferred `.init(...)`
/// whose type comes from the enclosing parameter at resolution time.
struct PendingInitCall: Sendable, Equatable {
    var typeName: String?
    var arguments: [PendingInitArgument]
}

/// One argument of a `PendingInitCall`: the bare members it passes directly (`.cat` → "cat")
/// and any nested `.init(...)` calls whose type is inferred from this argument's parameter.
struct PendingInitArgument: Sendable, Equatable {
    /// The argument label, or `""` for a positional (`_`) parameter.
    var label: String
    var members: [String]
    var nestedInits: [PendingInitCall]
}

/// Everything one parsed Swift file contributes: the asset usages it directly proves, the
/// initializer signatures it declares, and the pending init call sites awaiting resolution.
struct SwiftParseResult: Sendable {
    var usages: [ExploreUsage]
    var typeRegistry: [String: [String: InitParameterType]]
    var pendingInits: [PendingInitCall]
}
