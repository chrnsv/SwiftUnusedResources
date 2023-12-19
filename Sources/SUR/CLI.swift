import ArgumentParser
import Foundation
import PathKit
import Rainbow

@main
struct CLI: AsyncParsableCommand {
    @Option(name: .shortAndLong, help: "Root path of your Xcode project. Default is current.")
    var project: Path?
    
    @Option(name: .shortAndLong, help: "Project's target. Skip to process all targets.")
    var target: String?
    
    func run() async throws {
        let showWarnings = ProcessInfo.processInfo.environment["XCODE_PRODUCT_BUILD_VERSION"] != nil

        let projectPath: Path

        if let project {
            projectPath = project
        }
        else if let envProject = ProcessInfo.processInfo.environment["PROJECT_FILE_PATH"] {
            projectPath = Path(envProject)
        }
        else {
            let path = Path(".").absolute()
            
            if path.extension == "xcodeproj" {
                projectPath = path
            }
            else if let xcodeproj = path.glob("*.xcodeproj").first {
                projectPath = xcodeproj
            }
            else {
                throw RuntimeError("Project file not specified")
            }
        }

        if !projectPath.exists || !projectPath.isDirectory || projectPath.extension != "xcodeproj" {
            throw RuntimeError("Wrong project file specified")
        }

        var targetName: String?

        if let target {
            targetName = target
        }
        else if let envTarget = ProcessInfo.processInfo.environment["TARGET_NAME"] {
            targetName = envTarget
        }

        let sourceRoot: Path
        
        if let envRoot = ProcessInfo.processInfo.environment["SOURCE_ROOT"] {
            sourceRoot = Path(envRoot)
        }
        else {
            sourceRoot = projectPath.parent()
        }

        do {
            let explorer = try Explorer(
                projectPath: projectPath,
                sourceRoot: sourceRoot,
                target: targetName,
                showWarnings: showWarnings
            )
            
            try await explorer.explore()
        }
        catch {
            throw RuntimeError("❌ Processing failed: \(error)")
        }
    }
}

struct RuntimeError: Error, CustomStringConvertible {
    var description: String
    
    init(_ description: String) {
        self.description = description.red.bold
    }
}

extension Path: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(argument)
    }
}
