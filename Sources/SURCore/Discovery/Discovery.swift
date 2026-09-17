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

    var resources: [Path] = []

    for ext in extensions {
        for resourcePath in root.descendants(withExtension: ext) {
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
        sources: root.descendants(withExtension: "swift")
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

    return kinds.flatMap { kind in
        catalog.descendants(withExtension: kind.assetExtension)
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
