import AmbiMuxCore
import ArgumentParser
import Foundation

@main
struct AmbiMuxMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ambimux",
        abstract: "Mux or replace spatial audio into MOV videos using APAC encoding",
        discussion:
            "Embeds or replaces spatial audio in MOV videos for Apple Vision Pro. Supports encoding from audio files (4-channel B-format Ambisonics) and copying APAC-encoded spatial audio without re-encoding."
    )

    @Option(
        name: [.customShort("a"), .customLong("audio")],
        help: "Audio file path (4-channel B-format Ambisonics, or APAC-encoded file)"
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
