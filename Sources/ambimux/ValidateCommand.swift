import AmbiMuxCore
import ArgumentParser
import Foundation

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate whether a single video/audio file is convertible"
    )

    @Option(
        name: [.customLong("video")],
        help: "Video file path to validate"
    )
    var videoFilePath: String?

    @Option(
        name: [.customLong("audio")],
        help: "Audio file path to validate"
    )
    var audioFilePath: String?

    mutating func run() async throws {
        if videoFilePath == nil && audioFilePath == nil {
            throw ValidationError("Either --video or --audio is required")
        }
        if videoFilePath != nil && audioFilePath != nil {
            throw ValidationError("Specify only one of --video or --audio")
        }

        if let videoPath = videoFilePath {
            switch try await validateVideoInputEligibility(videoPath: videoPath) {
            case .eligible:
                return
            case .ineligible(let reason):
                throw ValidationError("Convertible: NO (\(reason.message))")
            }
        }

        let audioPath = audioFilePath!
        switch try await validateAudioInputEligibility(audioPath: audioPath) {
        case .eligible:
            return
        case .ineligible(let reason):
            throw ValidationError("Convertible: NO (\(reason.message))")
        }
    }
}
