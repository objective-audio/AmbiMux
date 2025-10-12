import AmbiMuxCore
import ArgumentParser
import Foundation

@main
struct AmbiMuxMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ambimux",
        abstract: "Mux or replace 1st-order Ambisonics (B-format) into MOV video",
        discussion:
            "Combines or replaces the video's audio with a specified 4-channel B-format Ambisonics WAV and outputs a MOV. Internally uses APAC where appropriate, but the primary purpose is FOA muxing/replacement."
    )

    @Option(
        name: [.customShort("a"), .customLong("audio")],
        help: "Audio file path (4-channel B-format Ambisonics WAV)"
    )
    var audioFilePath: String?

    @Option(
        name: [.customShort("v"), .customLong("video")],
        help: "Video file path"
    )
    var videoFilePath: String?

    @Option(
        name: [.customShort("o"), .customLong("output")],
        help: "Output file path (optional, defaults to video filename with .mov extension)"
    )
    var outputFilePath: String?

    mutating func run() async throws {
        guard let audioPath = audioFilePath, let videoPath = videoFilePath else {
            throw ValidationError("--audio and --video are required")
        }

        try await runAmbiMux(audioPath: audioPath, videoPath: videoPath, outputPath: outputFilePath)
    }
}
