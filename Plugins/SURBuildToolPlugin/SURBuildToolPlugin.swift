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
        try [
            makeCommand(
                tool: context.tool(named: "sur"),
                arguments: [],
                workDirectory: context.pluginWorkDirectoryURL
            ),
        ]
    }

    // A prebuild command rather than a build command: Xcode turns a build command
    // without output files into a script phase with a new identifier on every build,
    // so the build description has to be recreated each time (about 8 s on a large
    // project). sur produces no files, and a made-up output would be copied into the
    // product bundle as a resource.
    private func makeCommand(tool: PluginContext.Tool, arguments: [String], workDirectory: URL) -> Command {
        .prebuildCommand(
            displayName: "SwiftUnusedResources",
            executable: tool.url,
            // A prebuild command does not get the build environment by which sur
            // recognizes an Xcode build, so Xcode warnings are requested explicitly.
            arguments: arguments + ["--xcode-warnings"],
            outputFilesDirectory: workDirectory.appending(path: "Output")
        )
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SURBuildToolPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        // A script phase used to pass the project and the target to sur through its
        // environment; a prebuild command has to name them explicitly.
        let project = context.xcodeProject.directoryURL
            .appending(path: "\(context.xcodeProject.displayName).xcodeproj")

        return try [
            makeCommand(
                tool: context.tool(named: "sur"),
                arguments: ["--project", project.path(percentEncoded: false), "--target", target.displayName],
                workDirectory: context.pluginWorkDirectoryURL
            ),
        ]
    }
}
#endif
