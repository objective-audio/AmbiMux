import AmbiMuxCore
import ArgumentParser
import Foundation

struct JoinCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "join",
        abstract:
            "Join multiple MOV files with matching video and audio formats. Optional per-clip range: path@START-END (seconds)."
    )

    @Argument(
        help:
            "Input MOV paths in order (at least two). Append @START-END in seconds to trim, e.g. clip.mov@1.5-12"
    )
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

        let segments = try inputs.map { try parseJoinSegmentArgument($0) }
        try await runJoinMOV(segments: segments, outputPath: outputPath)
    }
}
