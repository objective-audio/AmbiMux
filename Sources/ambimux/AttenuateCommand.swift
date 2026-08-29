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
        name: .customLong("gain"),
        help: "Attenuation in dB (0 or negative)."
    )
    var gain: Double?

    mutating func run() async throws {
        guard let outputPath = outputFilePath else {
            throw ValidationError("--output is required")
        }
        guard let gainDb = gain else {
            throw ValidationError("--gain is required")
        }
        guard gainDb <= 0 else {
            throw ValidationError("--gain must be 0 or negative (boosting is not allowed)")
        }
        try await runAttenuateMOV(
            inputPath: input, outputPath: outputPath, gainDb: gainDb)
    }
}
