import Foundation

enum AmbiMuxError: Error, LocalizedError {
    // File related errors
    case audioFileNotFound(path: String)
    case videoFileNotFound(path: String)

    // Audio validation errors
    case noAudioTracksFound
    case invalidChannelCount(count: Int)
    case expectedAPACAudio
    case couldNotGetAudioStreamDescription
    case couldNotRetrieveFormatInformation

    // Conversion errors
    case audioTrackNotFound
    case videoTrackNotFound
    case conversionFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .audioFileNotFound(let path):
            return "Audio file not found: \(path)"
        case .videoFileNotFound(let path):
            return "Video file not found: \(path)"
        case .noAudioTracksFound:
            return "No audio tracks found in the audio file"
        case .invalidChannelCount(let count):
            return
                "Audio file must have exactly 4 channels for B-format Ambisonics. Current channels: \(count)"
        case .expectedAPACAudio:
            return "Audio file must be APAC-encoded"
        case .couldNotGetAudioStreamDescription:
            return "Could not get audio stream basic description"
        case .couldNotRetrieveFormatInformation:
            return "Could not retrieve format information"
        case .audioTrackNotFound:
            return "Audio track not found"
        case .videoTrackNotFound:
            return "Video track not found"
        case .conversionFailed(let message):
            return "Conversion failed: \(message)"
        }
    }
}
