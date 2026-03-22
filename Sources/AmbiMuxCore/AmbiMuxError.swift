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
    case embeddedAmbisonicsAlreadyAPAC

    // Option combination errors
    case invalidOutputFormatForAPACInput

    // Conversion / mux pipeline errors
    case audioTrackNotFound
    case videoTrackNotFound
    case couldNotCreateAudioFormatDescriptionWithHOALayout
    case couldNotGetSampleTimingInfoCount
    case couldNotGetSampleTimingInfoArray
    case couldNotGetSampleSizeArrayCount
    case couldNotGetSampleSizeArray
    case couldNotRecreateSampleBufferWithNewFormat
    case ambisonicsSampleBufferMissingFormatDescription
    case ambisonicsLpcmFormatChangedMidStream
    case outputWritingFailed(message: String)

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
        case .embeddedAmbisonicsAlreadyAPAC:
            return
                "Embedded Ambisonics is already APAC; no conversion is required"
        case .invalidOutputFormatForAPACInput:
            return "--audio-output lpcm cannot be used with APAC input"
        case .audioTrackNotFound:
            return "Audio track not found"
        case .videoTrackNotFound:
            return "Video track not found"
        case .couldNotCreateAudioFormatDescriptionWithHOALayout:
            return "Could not create audio format description with HOA channel layout"
        case .couldNotGetSampleTimingInfoCount:
            return "Could not get sample timing info count"
        case .couldNotGetSampleTimingInfoArray:
            return "Could not get sample timing info array"
        case .couldNotGetSampleSizeArrayCount:
            return "Could not get sample size array count"
        case .couldNotGetSampleSizeArray:
            return "Could not get sample size array"
        case .couldNotRecreateSampleBufferWithNewFormat:
            return "Could not recreate sample buffer with new format"
        case .ambisonicsSampleBufferMissingFormatDescription:
            return "Ambisonics sample buffer has no format description"
        case .ambisonicsLpcmFormatChangedMidStream:
            return "Ambisonics LPCM format changed mid-stream"
        case .outputWritingFailed(let message):
            return "Output writing failed: \(message)"
        }
    }
}
