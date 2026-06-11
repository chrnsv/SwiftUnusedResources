/// Resolves collected initializer call sites against the aggregated user-type registry,
/// turning a resource passed to a struct/class/actor initializer — directly or through a
/// type-inferred nested `.init(...)` — into a `.generated` usage. Pure and cross-file: it
/// only needs the merged registry, so it is shared by `Explorer` and exercised directly in tests.
struct InitArgumentResolver {
    let typeRegistry: InitializerRegistry
    let kinds: Set<ExploreKind>

    func resolve(_ pendingInits: [PendingInitCall]) -> [ExploreUsage] {
        var usages: [ExploreUsage] = []

        for pending in pendingInits {
            resolve(pending, expectedType: nil, into: &usages)
        }

        return usages
    }

    private func resolve(_ call: PendingInitCall, expectedType: String?, into usages: inout [ExploreUsage]) {
        guard
            let typeName = call.typeName ?? expectedType,
            let parameters = typeRegistry[typeName]?[call.selector]
        else {
            return
        }

        for argument in call.arguments {
            guard let parameterType = parameters[argument.label] else {
                continue
            }

            switch parameterType {
            case .resource(let kind):
                guard kinds.contains(kind) else {
                    continue
                }

                usages.append(contentsOf: argument.members.map { .generated($0, kind) })

            case .named(let innerType):
                for nested in argument.nestedInits {
                    resolve(nested, expectedType: innerType, into: &usages)
                }
            }
        }
    }
}
