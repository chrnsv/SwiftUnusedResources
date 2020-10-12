import Foundation
import PathKit
import XcodeProj
import Glob

enum ExploreError: Error {
    case notFound(message: String)
}

enum ExploreResourceType {
    case asset(assets: String)
    case image
}

struct ExploreResource {
    let name: String
    let type: ExploreResourceType
    let path: Path
    var usedCount: Int = 0
}

enum ExploreUsage {
    case string(_ value: String)
    case regexp(_ pattern: String)
    case rswift(_ identifier: String)
}


class Explorer {
    private let projectPath: Path
    private let sourceRoot: Path
    private let target: String?
    private let showWarnings: Bool

    private var exploredResources: [ExploreResource] = []
    private var exploredUsages: [ExploreUsage] = []
    
    init(projectPath: Path, sourceRoot: Path, target: String?, showWarnings: Bool) throws {
        self.projectPath = projectPath
        self.sourceRoot = sourceRoot
        self.target = target
        self.showWarnings = showWarnings
    }
    
    func explore() throws {
        print("🔨 Loading project \(project.lastComponent)".bold)
        let xcodeproj = try XcodeProj(path: projectPath)
        
        try xcodeproj.pbxproj.nativeTargets.forEach { target in
            if self.target == nil || (self.target != nil && target.name == self.target) {
                print("📦 Processing target \(target.name)".bold)
                try explore(target: target)
            }
        }
        
        print("🦒 Complete".bold)
    }
    
    private func analyze() {
        var unused: [ExploreResource] = []
        
        exploredResources.forEach { resource in
            var usageCount = 0
            
            exploredUsages.forEach { usage in
                switch usage {
                case .string(let value):
                    if resource.name == value {
                        usageCount = usageCount + 1
                    }
                    
                case .regexp(let pattern):
                    let regex = try! NSRegularExpression(pattern: "^\(pattern)$")
                    
                    let range = NSRange(location: 0, length: resource.name.utf16.count)
                    if (regex.firstMatch(in: resource.name, options: [], range: range) != nil) {
                        usageCount = usageCount + 1
                    }
                    
                case .rswift(let identifier):
                    let rswift = SwiftIdentifier(name: resource.name)
                    if rswift.description == identifier {
                        usageCount = usageCount + 1
                    }
                }
            }
            
            if usageCount == 0 {
                switch resource.type {
                case .asset(let assets):
                    if showWarnings {
                        var name = resource.name
                        if resource.path.string.starts(with: assets) {
                            name = NSString(string: String(resource.path.string.dropFirst(assets.count + 1))).deletingPathExtension
                        }
                        
                        print("\(assets): warning: '\(name)' never used")
                    }
                    unused.append(resource)
                    
                case .image:
                    if (showWarnings) {
                        print("\(resource.path): warning: '\(resource.name)' never used")
                    }
                    unused.append(resource)
                }
            }
        }
        
        if !showWarnings {
            if unused.count > 0 {
                print("    \(unused.count) unused images found".yellow.bold)
                var totalSize = 0
                unused.forEach { resource in
                    var name = resource.path.string
                    if name.starts(with: sourceRoot.string) {
                        name = String(resource.path.string.dropFirst(sourceRoot.string.count + 1))
                    }
                    
                    let size = resource.path.size
                    print("     \(size.humanFileSize.padding(toLength: 10, withPad: " ", startingAt: 0)) \(name)")
                    totalSize += size
                }
                print("    \(totalSize.humanFileSize) total".yellow)
            }
            else {
                print("    No unused images found".lightGreen)
            }
        }
    }
    
    private func explore(target: PBXNativeTarget) throws {
        exploredUsages = []
        exploredResources = []
        
        guard let resources = try target.resourcesBuildPhase() else {
            // no sources, skip
            print("    No resources, skip")
            return
        }
        try explore(resources: resources)
        
        if let sources = try target.sourcesBuildPhase() {
            try explore(sources: sources)
        }
        
        analyze()
    }
    
    private func explore(resource: PBXFileElement) throws {
        guard let fullPath = try resource.fullPath(sourceRoot: sourceRoot) else {
            throw ExploreError.notFound(message: "Could not get full path for resource \(resource) (uuid: \(resource.uuid))")
        }
        
        let ext = fullPath.extension
        
        switch ext {
        case "png", "jpg", "pdf", "gif":
            try explore(image: resource, path: fullPath)
            
        case "xcassets":
            try explore(xcassets: resource, path: fullPath)
            
        case "xib", "storyboard":
            try explore(xib: resource, path: fullPath)
            
        default:
            break
        }
    }
    
    private func explore(resources: PBXResourcesBuildPhase) throws {
        guard let files = resources.files else {
            throw ExploreError.notFound(message: "Resource files not found")
        }
        
        try files.forEach { file in
            guard let ffile = file.file else {
                return
            }
            
            try explore(resource: ffile)
        }
    }
    
    private func explore(xib: PBXFileElement, path: Path) throws {
        _ = try? XibParser(path, { usage in
            self.exploredUsages.append(usage)
        })
    }
    
    private func explore(xcassets: PBXFileElement, path: Path) throws {
        let files = Glob(pattern: path.string + "**/*.imageset")
        
        files.forEach { setPath in
            let setPath = Path(setPath)
            
            let exp = ExploreResource(
                name: setPath.lastComponentWithoutExtension,
                type: .asset(assets: path.string),
                path: setPath.absolute()
            )
            
            exploredResources.append(exp)
        }
    }
    
    private func explore(image: PBXFileElement, path: Path) throws {
        let exp = ExploreResource(
            name: path.lastComponent,
            type: .image,
            path: path
        )
        
        exploredResources.append(exp)
    }
    
    private func explore(sources: PBXSourcesBuildPhase) throws {
        guard let files = sources.files else {
            throw ExploreError.notFound(message: "Source files not found")
        }
        
        try files.forEach { file in
            guard let fullPath = try file.file?.fullPath(sourceRoot: sourceRoot) else {
                return
            }
            
            if fullPath.extension != "swift" {
                return
            }

            if fullPath.lastComponent == "R.generated.swift" {
                return
            }
            
            try SwiftParser(fullPath, { usage in
                self.exploredUsages.append(usage)
            })
        }
    }
}
