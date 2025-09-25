//
//  RewriteExplorer.swift
//  SUR
//
//  Created by Aleksandr Chernousov on 25/09/2025.
//

import Foundation
import Glob
import PathKit
import Rainbow
import XcodeProj

/// Discovers and processes files for rewriting R.swift usage to generated localization symbols
public final class RewriteExplorer {
    private let projectPath: Path
    private let sourceRoot: Path
    private let target: String?
    private let showWarnings: Bool
    private let excludedSources: [Path]
    private let dryRun: Bool
    
    /// Supported rewriter types
    public enum RewriterType {
        case strings
        case assets
    }
    
    public init(
        projectPath: Path,
        sourceRoot: Path,
        target: String? = nil,
        showWarnings: Bool = false,
        excludedSources: [Path] = [],
        dryRun: Bool = false
    ) {
        self.projectPath = projectPath
        self.sourceRoot = sourceRoot
        self.target = target
        self.showWarnings = showWarnings
        self.excludedSources = excludedSources
        self.dryRun = dryRun
    }
    
    /// Explore and rewrite files in the project
    public func explore(rewriterTypes: Set<RewriterType> = [.strings, .assets]) async throws {
        print("🔨 Loading project \(projectPath.lastComponent) for rewriting".bold)
        let xcodeproj = try XcodeProj(path: projectPath)
        
        for target in xcodeproj.pbxproj.nativeTargets {
            if self.target == nil || (self.target != nil && target.name == self.target) {
                print("📦 Processing target \(target.name) for rewriting".bold)
                try await explore(target: target, rewriterTypes: rewriterTypes)
            }
        }
        
        print("✨ Rewriting complete".bold.green)
    }
    
    private func explore(target: PBXNativeTarget, rewriterTypes: Set<RewriterType>) async throws {
        // Process sources
        if let sources = try target.sourcesBuildPhase() {
            try await explore(sources: sources, rewriterTypes: rewriterTypes)
        }
        
        // Process synchronized groups (modern Xcode projects)
        if let synchronizedGroups = target.fileSystemSynchronizedGroups {
            try await explore(groups: synchronizedGroups, rewriterTypes: rewriterTypes)
        }
    }
    
    private func explore(groups: [PBXFileSystemSynchronizedRootGroup], rewriterTypes: Set<RewriterType>) async throws {
        for group in groups {
            guard let path = try group.fullPath(sourceRoot: sourceRoot) else {
                continue
            }
            
            // Find all Swift files in the group
            let sources = Glob(pattern: path.string + "**/*.swift")
                .map { Path($0) }
                .filter { !excludedSources.contains($0) }
            
            try await explore(files: sources, rewriterTypes: rewriterTypes)
        }
    }
    
    private func explore(sources: PBXSourcesBuildPhase, rewriterTypes: Set<RewriterType>) async throws {
        guard let files = sources.files else {
            throw RewriteError.notFound(message: "Source files not found")
        }
        
        let paths = try files
            .compactMap { try $0.file?.fullPath(sourceRoot: sourceRoot) }
            .filter { $0.extension == "swift" }
            .filter { !excludedSources.contains($0) }
        
        try await explore(files: paths, rewriterTypes: rewriterTypes)
    }
    
    private func explore(files: some Sequence<Path>, rewriterTypes: Set<RewriterType>) async throws {
        let rewriteResults = try await withThrowingTaskGroup(of: RewriteResult.self) { group in
            files.forEach { path in
                group.addTask { @Sendable [projectPath, dryRun, showWarnings] in
                    try await self.rewriteFile(
                        at: path,
                        projectPath: projectPath,
                        rewriterTypes: rewriterTypes,
                        dryRun: dryRun,
                        showWarnings: showWarnings
                    )
                }
            }
            
            return try await group.reduce(into: [], { $0.append($1) })
        }
        
        // Report results
        await reportResults(rewriteResults)
    }
    
    private func rewriteFile(
        at path: Path,
        projectPath: Path,
        rewriterTypes: Set<RewriterType>,
        dryRun: Bool,
        showWarnings: Bool
    ) async throws -> RewriteResult {
        var changes: [RewriterType: Bool] = [:]
        var errors: [RewriterType: Error] = [:]
        
        for rewriterType in rewriterTypes {
            do {
                let rewriter = try createRewriter(type: rewriterType, projectPath: projectPath)
                let hasChanges = try rewriter.rewrite(fileAt: path.url, dryRun: dryRun)
                changes[rewriterType] = hasChanges
                
                if hasChanges && showWarnings {
                    print("✏️  Rewritten \(rewriterType): \(path.relativePath)")
                }
            } catch {
                errors[rewriterType] = error
                if showWarnings {
                    print("❌ Error rewriting \(path.relativePath) with \(rewriterType): \(error)")
                }
            }
        }
        
        return RewriteResult(path: path, changes: changes, errors: errors)
    }
    
    private func createRewriter(type: RewriterType, projectPath: Path) throws -> any FileRewriter {
        switch type {
        case .strings:
            return RToGeneratedStringsRewriter(projectAt: projectPath.url)
        case .assets:
            return RToGeneratedAssetsRewriter(projectAt: projectPath.url)
        }
    }
    
    private func reportResults(_ results: [RewriteResult]) async {
        let totalFiles = results.count
        let modifiedFiles = results.filter { !$0.changes.isEmpty && $0.changes.values.contains(true) }
        let errorFiles = results.filter { !$0.errors.isEmpty }
        
        print("\n📊 Rewrite Summary:".bold)
        print("   📁 Total files processed: \(totalFiles)")
        print("   ✅ Modified files: \(modifiedFiles.count)")
        print("   ❌ Files with errors: \(errorFiles.count)")
        
        if !modifiedFiles.isEmpty {
            print("\n📝 Modified files:".yellow.bold)
            for result in modifiedFiles {
                let changedTypes = result.changes.compactMap { type, changed in
                    changed ? type.description : nil
                }.joined(separator: ", ")
                print("   • \(result.path.relativePath) (\(changedTypes))")
            }
        }
        
        if !errorFiles.isEmpty {
            print("\n🚨 Files with errors:".red.bold)
            for result in errorFiles {
                print("   • \(result.path.relativePath)")
                for (type, error) in result.errors {
                    print("     └─ \(type): \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Protocol for file rewriters
public protocol FileRewriter {
    init(projectAt projectURL: URL) throws
    func rewrite(fileAt fileURL: URL, dryRun: Bool) throws -> Bool
}

/// Result of rewriting a single file
struct RewriteResult {
    let path: Path
    let changes: [RewriteExplorer.RewriterType: Bool]
    let errors: [RewriteExplorer.RewriterType: Error]
}

/// Errors that can occur during rewriting
enum RewriteError: Error {
    case notFound(message: String)
    case rewriteFailed(message: String)
}

// MARK: - Extensions

extension RewriteExplorer.RewriterType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .strings: return "strings"
        case .assets: return "assets"
        }
    }
}

extension RToGeneratedStringsRewriter: FileRewriter {
    // FileRewriter conformance is provided by the dryRun method we added
}

extension RToGeneratedAssetsRewriter: FileRewriter {
    // FileRewriter conformance would need to be added to RToGeneratedAssetsRewriter
}