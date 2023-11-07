import Foundation
import Glob
import PathKit
import XcodeProj

class Explorer {
    private let projectPath: Path
    private let sourceRoot: Path
    private let target: String?
    private let showWarnings: Bool

    private let storage = Storage()
    
    init(projectPath: Path, sourceRoot: Path, target: String?, showWarnings: Bool) throws {
        self.projectPath = projectPath
        self.sourceRoot = sourceRoot
        self.target = target
        self.showWarnings = showWarnings
    }
    
    func explore() async throws {
        print("🔨 Loading project \(projectPath.lastComponent)".bold)
        let xcodeproj = try XcodeProj(path: projectPath)
        
        for target in xcodeproj.pbxproj.nativeTargets {
            if self.target == nil || (self.target != nil && target.name == self.target) {
                print("📦 Processing target \(target.name)".bold)
                try await explore(target: target)
            }
        }
        
        print("🦒 Complete".bold)
    }
    
    private func analyze() async throws {
        let exploredResources = await storage.exploredResources
        let exploredUsages = await storage.exploredUsages
        
        for resource in exploredResources {
            var usageCount = 0
            
            for usage in exploredUsages {
                switch usage {
                case .string(let value):
                    if resource.name == value {
                        usageCount += 1
                    }
                    
                case .regexp(let pattern):
                    let regex = try NSRegularExpression(pattern: "^\(pattern)$")
                    
                    let range = NSRange(location: 0, length: resource.name.utf16.count)
                    if regex.firstMatch(in: resource.name, options: [], range: range) != nil {
                        usageCount += 1
                    }
                    
                case .rswift(let identifier):
                    let rswift = SwiftIdentifier(name: resource.name)
                    if rswift.description == identifier {
                        usageCount += 1
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
                    await storage.addUnused(resource)
                    
                case .image:
                    if showWarnings {
                        print("\(resource.path): warning: '\(resource.name)' never used")
                    }
                    await storage.addUnused(resource)
                }
            }
        }
        
        if !showWarnings {
            let unused = await storage.unused
            if !unused.isEmpty {
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
    
    private func explore(target: PBXNativeTarget) async throws {
        await storage.clean()
        
        guard let resources = try target.resourcesBuildPhase() else {
            // no sources, skip
            print("    No resources, skip")
            return
        }
        try await explore(resources: resources)
        
        if let sources = try target.sourcesBuildPhase() {
            try await explore(sources: sources)
        }
        
        try await analyze()
    }
    
    private func explore(resource: PBXFileElement) async throws {
        guard let fullPath = try resource.fullPath(sourceRoot: sourceRoot) else {
            throw ExploreError.notFound(message: "Could not get full path for resource \(resource) (uuid: \(resource.uuid))")
        }
        
        let ext = fullPath.extension
        
        switch ext {
        case "png", "jpg", "pdf", "gif":
            try await explore(image: resource, path: fullPath)
            
        case "xcassets":
            try await explore(xcassets: resource, path: fullPath)
            
        case "xib", "storyboard":
            try await explore(xib: resource, path: fullPath)
            
        default:
            break
        }
    }
    
    private func explore(resources: PBXResourcesBuildPhase) async throws {
        guard let files = resources.files else {
            throw ExploreError.notFound(message: "Resource files not found")
        }
        
        for file in files {
            guard let resource = file.file else {
                continue
            }
            
            try await explore(resource: resource)
        }
    }
    
    private func explore(xib: PBXFileElement, path: Path) async throws {
        let parser = XibParser()
        
        let usages = try? parser.parse(path)
        
        guard let usages else {
            return
        }
        
        await storage.addUsages(usages)
    }
    
    private func explore(xcassets: PBXFileElement, path: Path) async throws {
        let resources = Glob(pattern: path.string + "**/*.imageset")
            .map { Path($0) }
            .map {
                ExploreResource(
                    name: $0.lastComponentWithoutExtension,
                    type: .asset(assets: path.string),
                    path: $0.absolute()
                )
            }
        
        await storage.addResources(resources)
    }
    
    private func explore(image: PBXFileElement, path: Path) async throws {
        let resource = ExploreResource(
            name: path.lastComponent,
            type: .image,
            path: path
        )
        
        await storage.addResource(resource)
    }
    
    private func explore(sources: PBXSourcesBuildPhase) async throws {
        guard let files = sources.files else {
            throw ExploreError.notFound(message: "Source files not found")
        }
        
        let parser = SwiftParser(showWarnings: showWarnings)
        
        let usages = try await withThrowingTaskGroup(of: [ExploreUsage].self) { group in
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
                
                group.addTask {
                    try parser.parse(fullPath)
                }
            }
            
            return try await group.reduce(into: [], +=)
        }
        
        await storage.addUsages(usages)
    }
}

private extension Explorer {
    enum ExploreError: Error {
        case notFound(message: String)
    }
}
