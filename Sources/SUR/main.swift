import Foundation
import PathKit
import CommandLineKit
import Rainbow

let cli = CommandLineKit.CommandLine()

cli.formatOutput = { s, type in
    var str: String
    switch(type) {
    case .error: str = s.red.bold
    case .optionFlag: str = s.green.underline
    default: str = s
    }
    
    return cli.defaultFormat(s: str, type: type)
}

let projectPathOption = StringOption(
    shortFlag: "p",
    longFlag: "project",
    helpMessage: "Root path of your Xcode project. Default is current."
)
cli.addOption(projectPathOption)

let targetOption = StringOption(
    shortFlag: "t",
    longFlag: "target",
    helpMessage: "Project's target. Skip to process all targets."
)
cli.addOption(targetOption)

do {
    try cli.parse()
}
catch {
    cli.printUsage()
    exit(EX_USAGE)
}

let showWarnings = ProcessInfo.processInfo.environment["XCODE_PRODUCT_BUILD_VERSION"] != nil

let project: Path

if let optProject = projectPathOption.value {
    project = Path(optProject)
}
else if let envProject = ProcessInfo.processInfo.environment["PROJECT_FILE_PATH"] {
    project = Path(envProject)
}
else {
    let path = Path(".").absolute()
    if path.extension == "xcodeproj" {
        project = path
    }
    else if let xcodeproj = path.glob("*.xcodeproj").first {
        project = xcodeproj
    }
    else {
        cli.printUsage("Project file not specified")
        exit(EX_USAGE)
    }
}

if !project.exists || !project.isDirectory || project.extension != "xcodeproj" {
    cli.printUsage("Wrong project file specified")
    exit(EX_USAGE)
}

var target: String? = nil

if let optTarget = targetOption.value {
    target = optTarget
}
else if let envTarget = ProcessInfo.processInfo.environment["TARGET_NAME"] {
    target = envTarget
}

let sourceRoot: Path
if let envRoot = ProcessInfo.processInfo.environment["SOURCE_ROOT"] {
    sourceRoot = Path(envRoot)
}
else {
    sourceRoot = project.parent()
}

do {
    try Explorer(projectPath: project, sourceRoot: sourceRoot, target: target, showWarnings: showWarnings).explore()
}
catch {
    print("❌ Processing failed: \(error)".red.bold)
    exit(EX_USAGE)
}
