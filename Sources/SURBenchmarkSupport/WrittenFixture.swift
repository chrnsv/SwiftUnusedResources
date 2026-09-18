import Foundation
import PathKit
import XcodeProj

package struct WrittenFixture {
    package let root: Path
    package let projectPath: Path

    package func remove() {
        try? root.delete()
    }
}

package func makeTemporaryFixtureRoot() throws -> Path {
    let root = Path(FileManager.default.temporaryDirectory.path) + "SURBenchmarks-\(UUID().uuidString)"

    try root.mkpath()

    return root
}

/// Materializes `plan` under `root` and writes `App.xcodeproj` next to the files.
package func writeFixture(_ plan: FixturePlan, into root: Path) throws -> WrittenFixture {
    for file in plan.files {
        let path = root + file.path

        try path.parent().mkpath()
        try path.write(file.contents)
    }

    let projectPath = root + "App.xcodeproj"

    try makeProject(for: plan).write(path: projectPath)

    return WrittenFixture(root: root, projectPath: projectPath)
}

private func makeProject(for plan: FixturePlan) -> XcodeProj {
    let pbxproj = PBXProj()
    let mainGroup = PBXGroup(sourceTree: .group)
    pbxproj.add(object: mainGroup)

    func buildFile(_ relative: String) -> PBXBuildFile {
        let reference = PBXFileReference(sourceTree: .group, path: relative)
        pbxproj.add(object: reference)
        mainGroup.children.append(reference)

        let file = PBXBuildFile(file: reference)
        pbxproj.add(object: file)

        return file
    }

    let sourcesPhase = PBXSourcesBuildPhase(files: plan.classicSources.map(buildFile))
    pbxproj.add(object: sourcesPhase)

    let resourcesPhase = PBXResourcesBuildPhase(files: plan.classicResources.map(buildFile))
    pbxproj.add(object: resourcesPhase)

    func configurationList() -> XCConfigurationList {
        let configuration = XCBuildConfiguration(name: "Debug")
        pbxproj.add(object: configuration)

        let list = XCConfigurationList(buildConfigurations: [configuration], defaultConfigurationName: "Debug")
        pbxproj.add(object: list)

        return list
    }

    let synchronizedGroups = plan.synchronizedGroups.map { relative in
        let group = PBXFileSystemSynchronizedRootGroup(sourceTree: .group, path: relative)
        pbxproj.add(object: group)
        mainGroup.children.append(group)

        return group
    }

    let target = PBXNativeTarget(
        name: FixturePlan.targetName,
        buildConfigurationList: configurationList(),
        buildPhases: [sourcesPhase, resourcesPhase],
        productType: .application
    )
    target.fileSystemSynchronizedGroups = synchronizedGroups
    pbxproj.add(object: target)

    let project = PBXProject(
        name: "App",
        buildConfigurationList: configurationList(),
        compatibilityVersion: "Xcode 14.0",
        preferredProjectObjectVersion: nil,
        minimizedProjectReferenceProxies: nil,
        mainGroup: mainGroup,
        targets: [target]
    )
    pbxproj.add(object: project)
    pbxproj.rootObject = project

    return XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
}
