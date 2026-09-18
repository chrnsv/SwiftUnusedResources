import Foundation
import PathKit

package struct DiscoveredFiles: Equatable {
    package var resources: [Path]
    package var sources: [Path]
}

/// Resource and Swift source paths inside a file-system-synchronized group.
/// Reads the file system, but has no side effects and depends on nothing but `root`.
package func discoverFiles(inSynchronizedGroup root: Path) -> DiscoveredFiles {
    let extensions = ["png", "jpg", "pdf", "gif", "svg", "xcassets", "xib", "storyboard"]
    // A catalog is one resource; nothing inside it is a source or a resource of its own.
    let found = root.descendants(withExtensions: Set(extensions + ["swift"]), pruning: ["xcassets"])

    var resources: [Path] = []

    for ext in extensions {
        for resourcePath in found[ext] ?? [] {
            if ext != "xcassets" && resourcePath.string.contains("xcassets") {
                continue
            }

            if resourcePath.containsDirectory(withExtension: "icon") {
                continue
            }

            resources.append(resourcePath)
        }
    }

    return DiscoveredFiles(
        resources: resources,
        sources: found["swift"] ?? []
    )
}

/// Image/color sets of an asset catalog as resources. Empty when the catalog is excluded.
package func assetResources(
    in catalog: Path,
    kinds: Set<ExploreKind>,
    excludedAssets: [String]
) -> [ExploreResource] {
    guard !excludedAssets.contains(catalog.lastComponentWithoutExtension) else {
        return []
    }

    // allCases, not the set, so the resource (and output) order is the same on every run.
    let orderedKinds = ExploreKind.allCases.filter(kinds.contains)
    let assetExtensions = Set(orderedKinds.map(\.assetExtension))
    // Sets never nest, so their contents are not walked.
    let found = catalog.descendants(withExtensions: assetExtensions, pruning: assetExtensions)

    return orderedKinds.flatMap { kind in
        (found[kind.assetExtension] ?? [])
            .filter { !$0.containsDirectory(withExtension: "icon") }
            .map {
                ExploreResource(
                    name: $0.lastComponentWithoutExtension,
                    type: .asset(assets: catalog.string),
                    kind: kind,
                    path: $0.absolute().string
                )
            }
    }
}

private extension ExploreKind {
    var assetExtension: String {
        switch self {
        case .image: "imageset"
        case .color: "colorset"
        }
    }
}
