import AVFoundation
import Foundation

public struct ConversionEligibility: Sendable {
    nonisolated public let isEligible: Bool
    nonisolated public let reason: String

    nonisolated public init(isEligible: Bool, reason: String) {
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
