import Foundation
import PathKit
import XcodeProj

/// Builds a minimal real `.xcodeproj` in a temporary directory for Explorer
/// integration tests. The same XcodeProj library that `Explorer` reads with
/// writes the project, so the format is compatible by construction.
final class FixtureProject {
    private static let contentsJSON = """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """

    private let tmp: TemporaryDirectory

    var root: Path { tmp.path }

    var projectPath: Path { tmp.path + "App.xcodeproj" }

    init() throws {
        tmp = try TemporaryDirectory()
    }

    func addSource(_ relative: String, _ contents: String) throws {
        try tmp.write(relative, contents)
    }

    func addAssetCatalog(_ name: String, imageSets: [String] = [], colorSets: [String] = []) throws {
        try (tmp.path + name).mkpath()

        for set in imageSets {
            try tmp.write("\(name)/\(set).imageset/Contents.json", Self.contentsJSON)
        }

        for set in colorSets {
            try tmp.write("\(name)/\(set).colorset/Contents.json", Self.contentsJSON)
        }
    }

    func addXib(_ relative: String, _ xml: String) throws {
        try tmp.write(relative, xml)
    }

    func addLooseImage(_ relative: String) throws {
        try tmp.write(relative, "fake image bytes")
    }

    func setSurYML(_ yaml: String) throws {
        try tmp.write("sur.yml", yaml)
    }

    func write(targets: [TargetSpec]) throws {
        let pbxproj = PBXProj()
        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)

        var nativeTargets: [PBXTarget] = []

        for spec in targets {
            func buildFile(_ relative: String) -> PBXBuildFile {
                let reference = PBXFileReference(sourceTree: .group, path: relative)
                pbxproj.add(object: reference)
                mainGroup.children.append(reference)

                let file = PBXBuildFile(file: reference)
                pbxproj.add(object: file)

                return file
            }

            let sourcesPhase = PBXSourcesBuildPhase(files: spec.sources.map(buildFile))
            pbxproj.add(object: sourcesPhase)

            let resourcesPhase = PBXResourcesBuildPhase(files: spec.resources.map(buildFile))
            pbxproj.add(object: resourcesPhase)

            let configuration = XCBuildConfiguration(name: "Debug")
            pbxproj.add(object: configuration)

            let configurationList = XCConfigurationList(
                buildConfigurations: [configuration],
                defaultConfigurationName: "Debug"
            )
            pbxproj.add(object: configurationList)

            let target = PBXNativeTarget(
                name: spec.name,
                buildConfigurationList: configurationList,
                buildPhases: [sourcesPhase, resourcesPhase],
                productType: .application
            )
            pbxproj.add(object: target)
            nativeTargets.append(target)
        }

        let projectConfiguration = XCBuildConfiguration(name: "Debug")
        pbxproj.add(object: projectConfiguration)

        let projectConfigurationList = XCConfigurationList(
            buildConfigurations: [projectConfiguration],
            defaultConfigurationName: "Debug"
        )
        pbxproj.add(object: projectConfigurationList)

        let project = PBXProject(
            name: "App",
            buildConfigurationList: projectConfigurationList,
            compatibilityVersion: "Xcode 14.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            targets: nativeTargets
        )
        pbxproj.add(object: project)
        pbxproj.rootObject = project

        let xcodeproj = XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
        try xcodeproj.write(path: projectPath)
    }

    func remove() {
        tmp.remove()
    }

    struct TargetSpec {
        let name: String
        let sources: [String]
        let resources: [String]

        init(name: String, sources: [String] = [], resources: [String] = []) {
            self.name = name
            self.sources = sources
            self.resources = resources
        }
    }
}
