import Foundation

/// Returns the resources no usage refers to, in the order of `resources`.
/// Pure: no I/O, no state. Throws when a `.regexp` usage holds an invalid pattern.
package func unusedResources(
    in resources: [ExploreResource],
    usages: [ExploreUsage],
    excluding excludedResources: [String]
) throws -> [ExploreResource] {
    var unused: [ExploreResource] = []

    for resource in resources {
        var usageCount = 0

        if excludedResources.contains(resource.name) {
            continue
        }

        for usage in usages where usage.kind == resource.kind {
            switch usage {
            case .string(let value, _):
                if resource.name == value {
                    usageCount += 1
                }

            case .regexp(let pattern, _):
                let regex = try NSRegularExpression(pattern: "^\(pattern)$")

                let range = NSRange(location: 0, length: resource.name.utf16.count)
                if regex.firstMatch(in: resource.name, options: [], range: range) != nil {
                    usageCount += 1
                }

            case .rswift(let identifier, _):
                let rswift = SwiftIdentifier(name: resource.name)
                if rswift.description == identifier {
                    usageCount += 1
                }

            case .generated(let identifier, _):
                let name = SwiftIdentifier(name: resource.name).description.withoutImageAndColor()

                if name == identifier {
                    usageCount += 1
                }
            }
        }

        if usageCount == 0 {
            unused.append(resource)
        }
    }

    return unused
}

private extension ExploreUsage {
    var kind: ExploreKind {
        switch self {
        case .string(_, let kind): kind
        case .regexp(_, let kind): kind
        case .rswift(_, let kind): kind
        case .generated(_, let kind): kind
        }
    }
}
