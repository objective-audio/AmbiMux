import AVFoundation
import Foundation

public nonisolated enum ConversionEligibilityReason: Sendable {
    case noAudioTracksFound
    case videoAlreadyHasAPAC
    case videoMissingAmbisonics
    case videoAmbisonicsWithoutAPAC
    case audioHasAPAC
    case audioHasAmbisonics(order: AmbisonicsOrder)
    case audioMissingAPACAndAmbisonics
}

public extension ConversionEligibilityReason {
    nonisolated var message: String {
        switch self {
        case .noAudioTracksFound:
            return "No audio tracks found"
        case .videoAlreadyHasAPAC:
            return "APAC track is already present in the video"
        case .videoMissingAmbisonics:
            return "No Ambisonics track (4/9/16ch) found in the video"
        case .videoAmbisonicsWithoutAPAC:
            return "Ambisonics is present and APAC is not present"
        case .audioHasAPAC:
            return "APAC audio is present"
        case .audioHasAmbisonics(let order):
            return "Ambisonics audio is present (order \(order.rawValue), \(order.channelCount)ch)"
        case .audioMissingAPACAndAmbisonics:
            return "Neither APAC nor Ambisonics (4/9/16ch) audio is present"
        }
    }
}

public struct ConversionEligibility: Sendable {
    nonisolated public let isEligible: Bool
    nonisolated public let reason: ConversionEligibilityReason

    nonisolated public init(isEligible: Bool, reason: ConversionEligibilityReason) {
        self.isEligible = isEligible
        self.reason = reason
    }
}

nonisolated public func runAmbiMux(
    audioPath: String?,
    videoPath: String,
    outputPath: String? = nil,
    outputAudioFormat: AudioOutputFormat? = nil
)
    async throws
{
    let audioMode: AudioInputMode
    let actualAudioPath: String

    if let path = audioPath {
        audioMode = try await detectAudioInputMode(audioPath: path)
        actualAudioPath = path
    } else {
        try await validateEmbeddedLpcmAudio(videoPath: videoPath)
        audioMode = .embeddedLpcm
        actualAudioPath = videoPath
    }

    // APAC 入力に対して lpcm 出力は指定できない
    if case .apac = audioMode, outputAudioFormat == .lpcm {
        throw AmbiMuxError.invalidOutputFormatForAPACInput
    }

    // Generate output file path
    let finalOutputPath = generateOutputPath(
        outputPath: outputPath, videoPath: videoPath)

    // Execute conversion
    try await convertVideoWithAudioToMOV(
        audioPath: actualAudioPath,
        audioMode: audioMode,
        videoPath: videoPath,
        outputPath: finalOutputPath,
        outputAudioFormat: outputAudioFormat
    )

    // Verify output file
    try await verifyOutputFileDetails(outputPath: finalOutputPath)
}

nonisolated public func validateVideoInputEligibility(videoPath: String) async throws -> ConversionEligibility {
    let result = try await evaluateVideoInputEligibility(videoPath: videoPath)
    return ConversionEligibility(isEligible: result.isEligible, reason: result.reason)
}

nonisolated public func validateAudioInputEligibility(audioPath: String) async throws -> ConversionEligibility {
    let result = try await evaluateAudioInputEligibility(audioPath: audioPath)
    return ConversionEligibility(isEligible: result.isEligible, reason: result.reason)
}
