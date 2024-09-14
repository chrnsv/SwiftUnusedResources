import Foundation
import Glob
import PathKit
import Rainbow
import XcodeProj

public final class Explorer {
    private let projectPath: Path
    private let sourceRoot: Path
    private let target: String?
    private let showWarnings: Bool

    private let storage = Storage()
    
    public init(projectPath: Path, sourceRoot: Path, target: String?, showWarnings: Bool) throws {
        self.projectPath = projectPath
        self.sourceRoot = sourceRoot
        self.target = target
        self.showWarnings = showWarnings
    }
    
    public func explore() async throws {
        let start = Date()
        print("🔨 Loading project \(projectPath.lastComponent)".bold)
        let xcodeproj = try XcodeProj(path: projectPath)
        
        for target in xcodeproj.pbxproj.nativeTargets {
            if self.target == nil || (self.target != nil && target.name == self.target) {
                print("📦 Processing target \(target.name)".bold)
                try await explore(target: target)
            }
        }
        
        print("🦒 Complete".bold)
        let duration = Date().timeIntervalSince(start)
        
        print("Duration: \(duration)")
    }
    
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func analyze() async throws {
        let exploredResources = await storage.exploredResources
        let exploredUsages = await storage.exploredUsages
        
        for resource in exploredResources {
            var usageCount = 0
            
            for usage in exploredUsages where usage.kind == resource.kind {
                switch usage {
                case .string(let value, _):
                    if resource.name == value {
                        usageCount += 1
                    }
                    
                case .regexp(let pattern, _):
                    let regex = try NSRegularExpression(pattern: "^\(pattern)$")
                    
                    let range = NSRange(location: 0, length: resource.name.utf16.count)
                    if regex.firstMatch(in: resource.name, options: [], range: range) != nil {
                        usageCount += 1
                    }
                    
                case .rswift(let identifier, _):
                    let rswift = SwiftIdentifier(name: resource.name)
                    if rswift.value.trimmingCharacters(in: CharacterSet(charactersIn: "`")) == identifier {
                        usageCount += 1
                    }
                }
            }
            
            if usageCount == 0 {
                switch resource.type {
                case .asset(let assets):
                    if showWarnings {
                        var name = resource.name
                        
                        for path in resource.pathes {
                            if path.string.starts(with: assets) {
                                name = NSString(string: String(path.string.dropFirst(assets.count + 1))).deletingPathExtension
                            }
                            
                            print("\(assets): warning: '\(name)' never used")
                        }
                    }
                    await storage.addUnused(resource)
                    
                case .file:
                    if showWarnings {
                        for path in resource.pathes {
                            print("\(path): warning: '\(resource.name)' never used")
                        }
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
                    for path in resource.pathes {
                        var name = switch resource.kind {
                        case .asset: path.string
                        case .string: "\(resource.name), \(path.string)"
                        }
                        
                        if name.starts(with: sourceRoot.string) {
                            name = String(path.string.dropFirst(sourceRoot.string.count + 1))
                        }
                        
                        let size = path.size
                        print("     \(size.humanFileSize.padding(toLength: 10, withPad: " ", startingAt: 0)) \(name)")
                        totalSize += size
                    }
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
        case "png", "jpg", "pdf", "gif", "svg":
            try await explore(image: resource, path: fullPath)
            
        case "xcassets":
            try await explore(xcassets: resource, path: fullPath)
            
        case "xib", "storyboard":
            try await explore(xib: resource, path: fullPath)
            
        default:
            break
        }
    }
    
    private func explore(path: Path) async throws {
        print(path)
        let files = Glob(pattern: path.string + "**/*.strings")
            .map { Path($0) }
        
        let resources = files
            .compactMap { path in
                NSDictionary(contentsOfFile: path.string)
                    .flatMap { $0 as? [String: String] }
                    .map { (path, $0.keys) }
            }
            .flatMap { path, keys in
                keys.map { ($0, path) }
            }
            .reduce(into: [:]) { result, element in
                result[element.0, default: []].append(element.1)
            }
            .map { key, pathes in
                ExploreResource(
                    name: key,
                    type: .file,
                    kind: .string,
                    pathes: pathes
                )
            }
        
        await storage.addResources(resources)
    }
    
    private func explore(resources: PBXResourcesBuildPhase) async throws {
        guard let files = resources.files else {
            throw ExploreError.notFound(message: "Resource files not found")
        }
        
        let resources = files
            .compactMap { $0.file.flatMap { Resource(element: $0, root: sourceRoot) } }
            .toSet()
        
        for resource in resources {
            switch resource {
            case .file(let file):
                try await explore(resource: file)
                
            case .group(let group):
                try await explore(path: group)
            }
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
        let resources = ExploreKind.Asset.allCases
            .flatMap { explore(xcassets: xcassets, path: path, kind: $0) }
        
        await storage.addResources(resources)
    }
    
    private func explore(xcassets: PBXFileElement, path: Path, kind: ExploreKind.Asset) -> [ExploreResource] {
        let resources = Glob(pattern: path.string + kind.assets)
            .map { Path($0) }
            .map {
                ExploreResource(
                    name: $0.lastComponentWithoutExtension,
                    type: .asset(assets: path.string),
                    kind: .asset(kind),
                    pathes: [$0.absolute()]
                )
            }
        
        return resources
    }
    
    private func explore(image: PBXFileElement, path: Path) async throws {
        let resource = ExploreResource(
            name: path.lastComponent,
            type: .file,
            kind: .asset(.image),
            pathes: [path]
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
    enum Resource: Hashable {
        case file(PBXFileReference)
        case group(Path)
        
        init?(element: PBXFileElement, root: Path) {
            switch element {
            case let file as PBXFileReference:
                self = .file(file)
                
            case let group as PBXVariantGroup:
                guard let path = try? group.fullPath(sourceRoot: root) else {
                    return nil
                }
                
                self = .group(path)
                
            default:
                return nil
            }
        }
    }
    
    enum ExploreError: Error {
        case notFound(message: String)
    }
}

private extension ExploreKind.Asset {
    var assets: String {
        switch self {
        case .image: "**/*.imageset"
        case .color: "**/*.colorset"
        }
    }
}

private extension ExploreUsage {
    var kind: ExploreKind {
        switch self {
        case .string(_, let kind): kind
        case .regexp(_, let kind): kind
        case .rswift(_, let kind): kind
        }
    }
}

private extension Sequence where Element: Hashable {
    func toSet() -> Set<Element> { Set(self) }
}
