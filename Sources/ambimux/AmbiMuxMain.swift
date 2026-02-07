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
        name: [.customLong("apac")],
        help: "APAC-encoded audio file path (copied without re-encoding)"
    )
    var apacAudioFilePath: String?

    @Option(
        name: [.customLong("lpcm")],
        help: "4-channel B-format Ambisonics audio file path (encoded to APAC)"
    )
    var lpcmAudioFilePath: String?

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
        guard let videoPath = videoFilePath else {
            throw ValidationError("--video is required")
        }

        let apacPath = apacAudioFilePath
        let lpcmPath = lpcmAudioFilePath

        switch (apacPath, lpcmPath) {
        case (let apac?, nil):
            try await runAmbiMux(
                audioPath: apac,
                audioMode: .apac,
                videoPath: videoPath,
                outputPath: outputFilePath
            )
        case (nil, let lpcm?):
            try await runAmbiMux(
                audioPath: lpcm,
                audioMode: .lpcm,
                videoPath: videoPath,
                outputPath: outputFilePath
            )
        default:
            throw ValidationError("Exactly one of --apac or --lpcm is required")
        }
    }
}
