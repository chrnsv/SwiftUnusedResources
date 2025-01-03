//
//  SURBuildToolPlugin.swift
//
//
//  Created by Alexander Chernousov on 19.07.2024.
//

import Foundation
import PackagePlugin

@main
struct SURBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: any Target) async throws -> [Command] {
        try makeCommand(executable: context.tool(named: "sur"))
    }
    
    private func makeCommand(executable: PluginContext.Tool) -> [Command] {
        let command: Command = .buildCommand(displayName: "SwiftUnusedResources", executable: executable.url, arguments: [])
        
        return [command]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SURBuildToolPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        try makeCommand(executable: context.tool(named: "sur"))
    }
}
#endif
