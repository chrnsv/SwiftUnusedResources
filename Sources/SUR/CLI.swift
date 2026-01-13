import ArgumentParser
import Foundation
import PathKit
import Rainbow
import SURCore

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [SUR.self, RToXcode.self],
        defaultSubcommand: SUR.self
    )
}
