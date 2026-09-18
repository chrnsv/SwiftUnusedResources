import Foundation

/// Returns the resources no usage refers to, in the order of `resources`.
/// Pure: no I/O, no state. Throws when a `.regexp` usage holds an invalid pattern.
///
/// Usages are indexed once per kind: exact names, R.swift identifiers and generated identifiers
/// go into sets, and a `.regexp` pattern that is a plain ASCII literal is an exact name too
/// (`^p$` matches exactly `p`). Only genuinely dynamic patterns are compiled — once each, and
/// only when the first resource of their kind is checked, so an invalid pattern throws exactly
/// when it did before: whenever any non-excluded resource of that kind exists.
package func unusedResources(
    in resources: [ExploreResource],
    usages: [ExploreUsage],
    excluding excludedResources: [String]
) throws -> [ExploreResource] {
    var indexes = UsageIndex.build(from: usages)
    let excluded = Set(excludedResources)
    var unused: [ExploreResource] = []

    for resource in resources {
        if excluded.contains(resource.name) {
            continue
        }

        if try indexes[resource.kind, default: UsageIndex()].matches(resource) {
            continue
        }

        unused.append(resource)
    }

    return unused
}

/// Every usage of one kind, indexed for O(1) membership tests.
private struct UsageIndex {
    static func build(from usages: [ExploreUsage]) -> [ExploreKind: Self] {
        var indexes: [ExploreKind: Self] = [:]
        var seenPatterns: Set<String> = []

        for usage in usages {
            switch usage {
            case let .string(value, kind):
                indexes[kind, default: Self()].names.insert(value)

            case let .regexp(pattern, kind):
                if pattern.isLiteral {
                    indexes[kind, default: Self()].literals.insert(pattern)
                }
                else if seenPatterns.insert("\(kind.rawValue):\(pattern)").inserted {
                    indexes[kind, default: Self()].patterns.append(pattern)
                }

            case let .rswift(identifier, kind):
                indexes[kind, default: Self()].rswift.insert(identifier)

            case let .generated(identifier, kind):
                indexes[kind, default: Self()].generated.insert(identifier)
            }
        }

        return indexes
    }

    var names: Set<String> = []
    /// Literal `.regexp` patterns; unlike `names`, `^p$` also matches `p` + one line terminator.
    var literals: Set<String> = []
    var rswift: Set<String> = []
    var generated: Set<String> = []
    /// Distinct dynamic patterns in usage order; compiled on first use.
    var patterns: [String] = []
    var regexes: [NSRegularExpression]?

    /// Whether any usage refers to `resource`. Compiles this kind's patterns on the first call.
    mutating func matches(_ resource: ExploreResource) throws -> Bool {
        let regexes: [NSRegularExpression]

        if let compiled = self.regexes {
            regexes = compiled
        }
        else {
            regexes = try patterns.map { try NSRegularExpression(pattern: "^\($0)$") }
            self.regexes = regexes
        }

        if names.contains(resource.name) || literals.contains(resource.name) {
            return true
        }

        if !literals.isEmpty, let trimmed = resource.name.droppingTrailingLineTerminator, literals.contains(trimmed) {
            return true
        }

        if !rswift.isEmpty || !generated.isEmpty {
            let identifier = SwiftIdentifier(name: resource.name).description

            if rswift.contains(identifier) || generated.contains(identifier.withoutImageAndColor()) {
                return true
            }
        }

        let range = NSRange(location: 0, length: resource.name.utf16.count)

        return regexes.contains { $0.firstMatch(in: resource.name, options: [], range: range) != nil }
    }
}

private extension String {
    private static let metacharacters: Set<UInt8> = Set("\\^$.|?*+()[]{}\n\r".utf8)
    private static let lineTerminators: Set<Unicode.Scalar> = ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"]

    /// True when `^self$` can only ever match `self` itself: ASCII with no regex metacharacter.
    /// Non-ASCII stays a regex because `String ==` uses canonical equivalence and ICU does not.
    var isLiteral: Bool {
        utf8.allSatisfy { $0 < 0x80 && !Self.metacharacters.contains($0) }
    }

    /// The string without one trailing line terminator, or nil when it has none — what a
    /// trailing `$` tolerates. File names never carry one in practice, but the file system allows it.
    var droppingTrailingLineTerminator: String? {
        guard let last = unicodeScalars.last, Self.lineTerminators.contains(last) else {
            return nil
        }

        var scalars = unicodeScalars
        scalars.removeLast()

        if last == "\n", scalars.last == "\r" {
            scalars.removeLast()
        }

        return String(scalars)
    }
}
