import Foundation
import PathKit
import SURCore
import XcodeProj

/// Inputs of the isolated phases, prepared once outside any timed region.
struct Workload {
    let label: String
    let projectPath: Path
    let sourceRoot: Path
    let target: String?
    let groupRoots: [Path]
    let catalogs: [Path]
    let swiftFiles: [URL]
    let xibs: [Path]
    /// Collected by a quiet `Explorer` run; with several targets this is the last one processed.
    let resources: [ExploreResource]
    let usages: [ExploreUsage]
}

func loadWorkload(label: String, projectPath: Path, target: String?) async throws -> Workload {
    let sourceRoot = projectPath.parent()
    let xcodeproj = try XcodeProj(path: projectPath)
    let targets = xcodeproj.pbxproj.nativeTargets.filter { target == nil || $0.name == target }

    var groupRoots: [Path] = []
    var classicResources: [Path] = []
    var classicSources: [Path] = []

    for nativeTarget in targets {
        groupRoots += try (nativeTarget.fileSystemSynchronizedGroups ?? [])
            .compactMap { try $0.fullPath(sourceRoot: sourceRoot) }
        classicResources += try (nativeTarget.resourcesBuildPhase()?.files ?? [])
            .compactMap { try $0.file?.fullPath(sourceRoot: sourceRoot) }
        classicSources += try (nativeTarget.sourcesBuildPhase()?.files ?? [])
            .compactMap { try $0.file?.fullPath(sourceRoot: sourceRoot) }
    }

    let discovered = groupRoots.map { discoverFiles(inSynchronizedGroup: $0) }
    let resources = discovered.flatMap(\.resources) + classicResources
    let sources = discovered.flatMap(\.sources) + classicSources

    let explorer = try Explorer(
        projectPath: projectPath,
        sourceRoot: sourceRoot,
        target: target,
        showWarnings: false,
        quiet: true
    )
    try await explorer.explore()

    let inputs = await explorer.collectedInputs()

    return Workload(
        label: label,
        projectPath: projectPath,
        sourceRoot: sourceRoot,
        target: target,
        groupRoots: groupRoots,
        catalogs: resources.filter { $0.extension == "xcassets" },
        swiftFiles: sources.filter { $0.extension == "swift" }.map(\.url),
        xibs: resources.filter { $0.extension == "xib" || $0.extension == "storyboard" },
        resources: inputs.resources,
        usages: inputs.usages
    )
}

extension Workload {
    var description: String {
        "\(label): \(swiftFiles.count) swift files, \(catalogs.count) catalogs, \(xibs.count) xibs, "
            + "\(resources.count) resources, \(usages.count) usages"
    }
}
