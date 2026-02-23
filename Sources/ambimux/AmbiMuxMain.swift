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
            "Embeds or replaces spatial audio in MOV videos for Apple Vision Pro. Supports LPCM and APAC audio. Use --audio-output to select the output audio format (default: matches input)."
    )

    @Option(
        name: [.customLong("apac")],
        help: "APAC-encoded audio file path (copied without re-encoding by default)"
    )
    var apacAudioFilePath: String?

    @Option(
        name: [.customLong("lpcm")],
        help: "4-channel B-format Ambisonics audio file path (written as LPCM by default)"
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

    @Option(
        name: [.customLong("audio-output")],
        help: "Output audio format for LPCM input: lpcm (default) or apac"
    )
    var audioOutputFormat: AudioOutputFormat?

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
                outputPath: outputFilePath,
                outputAudioFormat: audioOutputFormat
            )
        case (nil, let lpcm?):
            try await runAmbiMux(
                audioPath: lpcm,
                audioMode: .lpcm,
                videoPath: videoPath,
                outputPath: outputFilePath,
                outputAudioFormat: audioOutputFormat
            )
        case (nil, nil):
            try await runAmbiMux(
                audioPath: videoPath,
                audioMode: .embeddedLpcm,
                videoPath: videoPath,
                outputPath: outputFilePath,
                outputAudioFormat: audioOutputFormat
            )
        case (_, _):
            throw ValidationError("--apac and --lpcm cannot be specified at the same time")
        }
    }
}
