import AmbiMuxCore
import ArgumentParser
import Foundation

struct JoinCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "join",
        abstract: "Join multiple MOV files with matching video and audio formats"
    )

    @Argument(help: "Input MOV file paths to join in order (at least two)")
    var inputs: [String]

    @Option(
        name: [.customShort("o"), .customLong("output")],
        help: "Output MOV file path"
    )
    var outputFilePath: String?

    mutating func run() async throws {
        guard let outputPath = outputFilePath else {
            throw ValidationError("--output is required")
        }

        try await runJoinMOV(inputPaths: inputs, outputPath: outputPath)
    }
}
