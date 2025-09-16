import ArgumentParser
import Foundation
import PathKit
import Rainbow
import SURCore

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [RewriteRImage.self],
        defaultSubcommand: CLI.self
    )
    @Option(name: .shortAndLong, help: "Root path of your Xcode project. Default is current.", transform: { Path($0) })
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

extension CLI {
    struct RewriteRImage: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rewrite-r-image", abstract: "Rewrite R.image.<id>()! to UIImage(resource: .<id>)")

        @Option(name: .shortAndLong, help: "Path to folder or file to rewrite. Default is current.", transform: { Path($0) })
        var path: Path = Path(".")

        func validate() throws {
            guard path.exists else { throw RuntimeError("Path does not exist") }
        }

        func run() throws {
            var changed = 0
            let rewriter = RToGeneratedAssetsRewriter()
            let stringsRewriter = RToGeneratedStringsRewriter(projectAt: path.url)

            let files: [Path]
            if path.isDirectory {
                files = try collectSwiftFiles(in: path)
            } else {
                files = path.extension == "swift" ? [path] : []
            }

            for file in files {
//                if try rewriter.rewrite(fileAt: file.url) { changed += 1 }
                if try stringsRewriter.rewrite(fileAt: file.url) { changed += 1 }
            }

            print("Rewrote \(changed) files")
        }

        private func collectSwiftFiles(in root: Path) throws -> [Path] {
            let skipDirs: Set<String> = [".build", ".git", ".swiftpm", "DerivedData", "Carthage", "Pods"]
            var result: [Path] = []

            for child in try root.children() {
                if child.isDirectory {
                    if skipDirs.contains(child.lastComponent) { continue }
                    result.append(contentsOf: try collectSwiftFiles(in: child))
                } else if child.extension == "swift" {
                    result.append(child)
                }
            }
            return result
        }
    }
}
