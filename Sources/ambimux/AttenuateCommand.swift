import AmbiMuxCore
import ArgumentParser
import Foundation

struct AttenuateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attenuate",
        abstract:
            "Lower APAC Ambisonics level in a MOV (video passthrough, APAC re-encode). Never boosts."
    )

    @Argument(help: "Input MOV with video and APAC Ambisonics")
    var input: String

    @Option(
        name: [.customShort("o"), .customLong("output")],
        help: "Output MOV file path"
    )
    var outputFilePath: String?

    @Option(
        name: .customLong("db"),
        help: "Amount to lower the level in dB (0 or positive)."
    )
    var db: Double?

    mutating func run() async throws {
        guard let outputPath = outputFilePath else {
            throw ValidationError("--output is required")
        }
        guard let db else {
            throw ValidationError("--db is required")
        }
        guard db >= 0 else {
            throw ValidationError("--db must be 0 or positive (boosting is not allowed)")
        }
        try await runAttenuateMOV(
            inputPath: input, outputPath: outputPath, gainDb: -db)
    }
}
