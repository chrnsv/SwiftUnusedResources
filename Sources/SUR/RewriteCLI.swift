//
//  RewriteCLI.swift
//  SUR
//
//  Created by Aleksandr Chernousov on 25/09/2025.
//

import Foundation
import ArgumentParser
import PathKit
import Rainbow
import SURCore

struct RewriteCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sur-rewrite",
        abstract: "Rewrite R.swift usage to generated localization symbols",
        version: "1.0.0"
    )
    
    @Argument(help: "Path to the Xcode project (.xcodeproj)")
    var projectPath: String
    
    @Option(name: .shortAndLong, help: "Source root path (default: project directory)")
    var sourceRoot: String?
    
    @Option(name: .shortAndLong, help: "Target name to process (default: all targets)")
    var target: String?
    
    @Flag(name: .shortAndLong, help: "Show detailed warnings and progress")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Dry run - show what would be changed without writing")
    var dryRun: Bool = false
    
    @Flag(name: .long, help: "Rewrite strings localization")
    var strings: Bool = false
    
    @Flag(name: .long, help: "Rewrite assets")
    var assets: Bool = false
    
    @Option(help: "Paths to exclude from rewriting")
    var exclude: [String] = []
    
    mutating func run() async throws {
        let projectPath = Path(self.projectPath)
        let sourceRoot = Path(self.sourceRoot ?? projectPath.parent().string)
        
        // Validate project path
        guard projectPath.exists else {
            throw ValidationError("Project path does not exist: \(projectPath)")
        }
        
        guard projectPath.extension == "xcodeproj" else {
            throw ValidationError("Path must be an Xcode project (.xcodeproj): \(projectPath)")
        }
        
        // Determine which rewriters to use
        var rewriterTypes: Set<RewriteExplorer.RewriterType> = []
        
        if strings {
            rewriterTypes.insert(.strings)
        }
        
        if assets {
            rewriterTypes.insert(.assets)
        }
        
        // If no specific rewriters are specified, use all
        if rewriterTypes.isEmpty {
            rewriterTypes = [.strings, .assets]
        }
        
        // Convert excluded paths
        let excludedSources = exclude.map { Path($0) }
        
        // Create explorer and run
        let explorer = RewriteExplorer(
            projectPath: projectPath,
            sourceRoot: sourceRoot,
            target: target,
            showWarnings: verbose,
            excludedSources: excludedSources,
            dryRun: dryRun
        )
        
        if dryRun {
            print("🔍 Dry run mode - no files will be modified".yellow.bold)
        }
        
        print("🚀 Starting rewrite process...".bold)
        print("   📂 Project: \(projectPath.lastComponent)")
        print("   📍 Source root: \(sourceRoot)")
        print("   🔧 Rewriters: \(rewriterTypes.map(\.description).joined(separator: ", "))")
        
        try await explorer.explore(rewriterTypes: rewriterTypes)
    }
}

extension ValidationError: @retroactive LocalizedError {
    public var errorDescription: String? {
        return message
    }
}
