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

/// One constructor's parameters, keyed by argument label (or `#0`, `#1`, … for positional params).
typealias InitParameterMap = [String: InitParameterType]

/// The constructors a type exposes, keyed by *selector* — `"init"` for an initializer/memberwise
/// init, or a static factory method's name.
typealias TypeConstructors = [String: InitParameterMap]

/// The set of constructors every known type exposes to asset detection, keyed by type name.
/// Built per file and merged across files.
typealias InitializerRegistry = [String: TypeConstructors]

/// Deep-merges one initializer registry into another (`type → selector → label`), the later
/// value winning on a conflict — used to combine per-file registries and a type's own
/// declaration with its extensions.
func mergeInitializerRegistry(_ source: InitializerRegistry, into target: inout InitializerRegistry) {
    for (type, selectors) in source {
        for (selector, parameters) in selectors {
            target[type, default: [:]][selector, default: [:]].merge(parameters) { _, new in new }
        }
    }
}

/// A collected constructor call site, recorded during parsing and resolved against the cross-file
/// type registry afterwards. `typeName` is the explicit callee type (`Foo(...)`, `Foo.init(...)`,
/// `Outer.Inner(...)`, `Test.image(...)`), or `nil` for an inferred leading-dot call (`.init(...)`,
/// `.image(...)`) whose type comes from the enclosing parameter at resolution time. `selector`
/// is `"init"` for an initializer or the static factory method's name.
struct PendingInitCall: Sendable, Equatable {
    var typeName: String?
    var selector: String
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
    /// Source file path, used to merge per-file registries in a deterministic order.
    var path: String
    var usages: [ExploreUsage]
    var typeRegistry: InitializerRegistry
    var pendingInits: [PendingInitCall]
}
