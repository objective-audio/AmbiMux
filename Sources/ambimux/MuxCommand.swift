import AmbiMuxCore
import ArgumentParser
import Foundation

struct MuxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mux",
        abstract: "Mux or replace spatial audio into MOV videos"
    )

    @Option(
        name: [.customShort("a"), .customLong("audio")],
        help: "Spatial audio file path (APAC or LPCM, auto-detected). Omit to use embedded audio from the video file."
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

    @Option(
        name: [.customLong("audio-output")],
        help: "Output audio format for LPCM input: lpcm (default) or apac"
    )
    var audioOutputFormat: AudioOutputFormat?

    mutating func run() async throws {
        guard let videoPath = videoFilePath else {
            throw ValidationError("--video is required")
        }

        try await runAmbiMux(
            audioPath: audioFilePath,
            videoPath: videoPath,
            outputPath: outputFilePath,
            outputAudioFormat: audioOutputFormat
        )
    }
}
