import Foundation

enum AmbiMuxError: Error, LocalizedError, Equatable {
    // Audio validation errors
    case noAudioTracksFound
    case noAmbisonicsTrackFound
    case invalidChannelCount(count: Int)
    case expectedAPACAudio
    case couldNotGetAudioStreamDescription
    case couldNotRetrieveFormatInformation
    case invalidAmbisonicsChannelLayout(detail: String)

    // Option combination errors
    case invalidOutputFormatForAPACInput

    // Conversion errors
    case audioTrackNotFound
    case videoTrackNotFound
    case conversionFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .noAudioTracksFound:
            return "No audio tracks found in the file"
        case .noAmbisonicsTrackFound:
            return "No Ambisonics track (4/9/16 channels) found in the video file"
        case .invalidChannelCount(let count):
            return
                "Audio file must have \(AmbisonicsOrder.allowedChannelCounts.map(String.init).joined(separator: ", ")) channels for B-format Ambisonics. Current channels: \(count)"
        case .expectedAPACAudio:
            return "Audio file must be APAC-encoded"
        case .couldNotGetAudioStreamDescription:
            return "Could not get audio stream basic description"
        case .couldNotRetrieveFormatInformation:
            return "Could not retrieve format information"
        case .invalidAmbisonicsChannelLayout(let detail):
            return
                "Ambisonics source uses channel descriptions but channel labels must be Discrete_0, Discrete_1, … in order. \(detail)"
        case .invalidOutputFormatForAPACInput:
            return "--audio-output lpcm cannot be used with APAC input"
        case .audioTrackNotFound:
            return "Audio track not found"
        case .videoTrackNotFound:
            return "Video track not found"
        case .conversionFailed(let message):
            return "Conversion failed: \(message)"
        }
    }
}
