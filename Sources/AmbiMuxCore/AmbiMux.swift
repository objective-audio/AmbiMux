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

nonisolated private func runAmbiMuxCore(
    audioPath: String?,
    videoPath: String,
    outputPath: String?,
    outputAudioFormat: AudioOutputFormat?,
    progressInterval: Duration?,
    progress: (@Sendable (Double) -> Void)?
) async throws {
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

    if case .apac = audioMode, outputAudioFormat == .lpcm {
        throw AmbiMuxError.invalidOutputFormatForAPACInput
    }

    let finalOutputPath = generateOutputPath(
        outputPath: outputPath, videoPath: videoPath)

    try await convertVideoWithAudioToMOV(
        audioPath: actualAudioPath,
        audioMode: audioMode,
        videoPath: videoPath,
        outputPath: finalOutputPath,
        outputAudioFormat: outputAudioFormat,
        progress: progress,
        progressInterval: progressInterval
    )

    try await verifyOutputFileDetails(outputPath: finalOutputPath)
}

nonisolated public func runAmbiMux(
    audioPath: String?,
    videoPath: String,
    outputPath: String? = nil,
    outputAudioFormat: AudioOutputFormat? = nil,
    progressInterval: Duration? = nil,
    progress: (@Sendable (Double) -> Void)? = nil
) async throws {
    try await runAmbiMuxCore(
        audioPath: audioPath,
        videoPath: videoPath,
        outputPath: outputPath,
        outputAudioFormat: outputAudioFormat,
        progressInterval: progressInterval,
        progress: progress
    )
}

/// 変換の進捗（0.0〜1.0）を `progressInterval` ごとに `AsyncThrowingStream` で yield する。
nonisolated public func runAmbiMuxProgressStream(
    audioPath: String?,
    videoPath: String,
    outputPath: String? = nil,
    outputAudioFormat: AudioOutputFormat? = nil,
    progressInterval: Duration = .milliseconds(250)
) -> AsyncThrowingStream<Double, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                try await runAmbiMuxCore(
                    audioPath: audioPath,
                    videoPath: videoPath,
                    outputPath: outputPath,
                    outputAudioFormat: outputAudioFormat,
                    progressInterval: progressInterval,
                    progress: { continuation.yield($0) }
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

nonisolated public func validateVideoInputEligibility(videoPath: String) async throws -> ConversionEligibility {
    let result = try await evaluateVideoInputEligibility(videoPath: videoPath)
    return ConversionEligibility(isEligible: result.isEligible, reason: result.reason)
}

nonisolated public func validateAudioInputEligibility(audioPath: String) async throws -> ConversionEligibility {
    let result = try await evaluateAudioInputEligibility(audioPath: audioPath)
    return ConversionEligibility(isEligible: result.isEligible, reason: result.reason)
}
