import AmbiMuxCore
import ArgumentParser
import Foundation

extension AudioOutputFormat: ExpressibleByArgument {}

@main
struct AmbiMuxMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ambimux",
        abstract: "Mux or replace spatial audio into MOV videos",
        discussion:
            "Embeds or replaces spatial audio in MOV videos for Apple Vision Pro. Supports LPCM and APAC audio (auto-detected). Use --audio-output to select the output audio format for LPCM input (default: lpcm).",
        subcommands: [MuxCommand.self, ValidateCommand.self],
        defaultSubcommand: MuxCommand.self
    )
}
