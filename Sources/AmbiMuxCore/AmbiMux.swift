import AVFoundation
import Foundation

// MARK: - Video validation

public nonisolated enum VideoValidationSuccess: Equatable, Sendable {
    case noEmbeddedAudioUseExternal
    case ambisonicsWithoutAPAC
    case nonSpatialEmbeddedAudio
}

public nonisolated enum VideoValidationFailure: Equatable, Sendable {
    case noVideoTracks
    case nonAPACWithHOALayoutTag
    case alreadyHasAPAC
    case missingAmbisonicsTrack
}

public nonisolated enum VideoValidationResult: Equatable, Sendable {
    case eligible(VideoValidationSuccess)
    case ineligible(VideoValidationFailure)
}

public extension VideoValidationSuccess {
    nonisolated var message: String {
        switch self {
        case .noEmbeddedAudioUseExternal:
            return
                "No embedded audio tracks; use --audio with an external spatial audio file when muxing"
        case .ambisonicsWithoutAPAC:
            return "Ambisonics is present and APAC is not present"
        case .nonSpatialEmbeddedAudio:
            return "Embedded audio is present but neither APAC nor Ambisonics; still eligible"
        }
    }
}

public extension VideoValidationFailure {
    nonisolated var message: String {
        switch self {
        case .noVideoTracks:
            return "No video tracks found"
        case .nonAPACWithHOALayoutTag:
            return
                "Non-APAC audio uses HOA ACN SN3D channel layout; expected only with APAC for this workflow"
        case .alreadyHasAPAC:
            return "APAC track is already present in the video"
        case .missingAmbisonicsTrack:
            return "No Ambisonics track (4/9/16ch) found in the video"
        }
    }
}

// MARK: - Audio validation

public nonisolated enum AudioValidationSuccess: Equatable, Sendable {
    case apac
    case ambisonics(AmbisonicsOrder)
}

public nonisolated enum AudioValidationFailure: Equatable, Sendable {
    case noAudioTracks
    case nonAPACWithHOALayoutTag
    case missingAPACAndAmbisonics
}

public nonisolated enum AudioValidationResult: Equatable, Sendable {
    case eligible(AudioValidationSuccess)
    case ineligible(AudioValidationFailure)
}

public extension AudioValidationSuccess {
    nonisolated var message: String {
        switch self {
        case .apac:
            return "APAC audio is present"
        case .ambisonics(let order):
            return "Ambisonics audio is present (order \(order.rawValue), \(order.channelCount)ch)"
        }
    }
}

public extension AudioValidationFailure {
    nonisolated var message: String {
        switch self {
        case .noAudioTracks:
            return "No audio tracks found"
        case .nonAPACWithHOALayoutTag:
            return
                "Non-APAC audio uses HOA ACN SN3D channel layout; expected only with APAC for this workflow"
        case .missingAPACAndAmbisonics:
            return "Neither APAC nor Ambisonics (4/9/16ch) audio is present"
        }
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

nonisolated public func validateVideoInputEligibility(videoPath: String) async throws -> VideoValidationResult {
    try await evaluateVideoInputEligibility(videoPath: videoPath)
}

nonisolated public func validateAudioInputEligibility(audioPath: String) async throws -> AudioValidationResult {
    try await evaluateAudioInputEligibility(audioPath: audioPath)
}
