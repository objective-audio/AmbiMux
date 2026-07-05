import AVFoundation
import CoreAudioTypes
import CoreGraphics
import CoreMedia
import Foundation

// MARK: - Format signature

struct MOVJoinFormatSignature: Sendable {
    nonisolated enum AudioTrackRole: Equatable, Sendable {
        case ambisonics
        case fallback
    }

    struct VideoSignature: Equatable, Sendable {
        let codecType: FourCharCode
        let width: Int
        let height: Int
        let nominalFrameRate: Float
        let preferredTransform: CGAffineTransform
    }

    struct AudioTrackSignature: Sendable {
        let role: AudioTrackRole
        let asbd: AudioStreamBasicDescription
        let channelLayoutTag: AudioChannelLayoutTag?
    }

    let video: VideoSignature
    let audioTracks: [AudioTrackSignature]
}

nonisolated private func channelLayoutTag(from formatDescription: CMFormatDescription) -> AudioChannelLayoutTag? {
    var layoutSize: Int = 0
    guard let channelLayout = CMAudioFormatDescriptionGetChannelLayout(
        formatDescription, sizeOut: &layoutSize)
    else {
        return nil
    }
    return channelLayout.pointee.mChannelLayoutTag
}

nonisolated private func audioTrackRole(for channelCount: Int) throws -> MOVJoinFormatSignature.AudioTrackRole {
    if AmbisonicsOrder(channelCount: channelCount) != nil {
        return .ambisonics
    }
    if channelCount == 1 || channelCount == 2 {
        return .fallback
    }
    throw AmbiMuxError.invalidChannelCount(count: channelCount)
}

nonisolated private func collectAudioTrackSignatures(
    from audioTracks: [AVAssetTrack]
) async throws -> [MOVJoinFormatSignature.AudioTrackSignature] {
    var ambisonics: MOVJoinFormatSignature.AudioTrackSignature?
    var fallback: MOVJoinFormatSignature.AudioTrackSignature?

    for track in audioTracks {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let asbd = formatDescription.audioStreamBasicDescription
        else {
            throw AmbiMuxError.couldNotGetAudioStreamDescription
        }

        let channelCount = Int(asbd.mChannelsPerFrame)
        let role = try audioTrackRole(for: channelCount)
        let signature = MOVJoinFormatSignature.AudioTrackSignature(
            role: role,
            asbd: asbd,
            channelLayoutTag: channelLayoutTag(from: formatDescription)
        )

        switch role {
        case .ambisonics:
            if ambisonics == nil {
                ambisonics = signature
            }
        case .fallback:
            if fallback == nil {
                fallback = signature
            }
        }
    }

    guard let ambisonics else {
        throw AmbiMuxError.noAmbisonicsTrackFound
    }

    var result = [ambisonics]
    if let fallback {
        result.append(fallback)
    }
    return result
}

nonisolated func collectFormatSignature(from asset: AVURLAsset) async throws -> MOVJoinFormatSignature {
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
        throw AmbiMuxError.videoTrackNotFound
    }

    let formatDescriptions = try await videoTrack.load(.formatDescriptions)
    guard let videoFormatDescription = formatDescriptions.first else {
        throw AmbiMuxError.couldNotRetrieveFormatInformation
    }

    let naturalSize = try await videoTrack.load(.naturalSize)
    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
    let preferredTransform = try await videoTrack.load(.preferredTransform)

    let videoSignature = MOVJoinFormatSignature.VideoSignature(
        codecType: CMFormatDescriptionGetMediaSubType(videoFormatDescription),
        width: Int(naturalSize.width),
        height: Int(naturalSize.height),
        nominalFrameRate: nominalFrameRate,
        preferredTransform: preferredTransform
    )

    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
        throw AmbiMuxError.noAudioTracksFound
    }

    let audioSignatures = try await collectAudioTrackSignatures(from: audioTracks)

    return MOVJoinFormatSignature(video: videoSignature, audioTracks: audioSignatures)
}

nonisolated private let joinFrameRateTolerance: Float = 0.01

nonisolated private func frameRatesAreEquivalent(_ a: Float, _ b: Float) -> Bool {
    abs(a - b) < joinFrameRateTolerance
}

nonisolated private func validateCompatibility(
    reference: MOVJoinFormatSignature,
    referencePath: String,
    other: MOVJoinFormatSignature,
    otherPath: String
) throws {
    let refVideo = reference.video
    let otherVideo = other.video

    guard refVideo.codecType == otherVideo.codecType else {
        throw AmbiMuxError.concatFormatMismatch(
            referencePath: referencePath,
            otherPath: otherPath,
            detail: "video codec differs"
        )
    }
    guard refVideo.width == otherVideo.width,
        refVideo.height == otherVideo.height
    else {
        throw AmbiMuxError.concatFormatMismatch(
            referencePath: referencePath,
            otherPath: otherPath,
            detail: "video resolution differs (\(refVideo.width)x\(refVideo.height) vs \(otherVideo.width)x\(otherVideo.height))"
        )
    }
    guard frameRatesAreEquivalent(refVideo.nominalFrameRate, otherVideo.nominalFrameRate) else {
        throw AmbiMuxError.concatFormatMismatch(
            referencePath: referencePath,
            otherPath: otherPath,
            detail: "video frame rate differs (\(refVideo.nominalFrameRate) vs \(otherVideo.nominalFrameRate) fps)"
        )
    }
    guard refVideo.preferredTransform == otherVideo.preferredTransform else {
        throw AmbiMuxError.concatFormatMismatch(
            referencePath: referencePath,
            otherPath: otherPath,
            detail: "video transform differs"
        )
    }

    guard reference.audioTracks.count == other.audioTracks.count else {
        throw AmbiMuxError.concatFormatMismatch(
            referencePath: referencePath,
            otherPath: otherPath,
            detail: "audio track count differs (\(reference.audioTracks.count) vs \(other.audioTracks.count))"
        )
    }

    for (index, refAudio) in reference.audioTracks.enumerated() {
        let otherAudio = other.audioTracks[index]
        guard refAudio.role == otherAudio.role else {
            throw AmbiMuxError.concatFormatMismatch(
                referencePath: referencePath,
                otherPath: otherPath,
                detail: "audio track \(index + 1) role differs"
            )
        }
        guard refAudio.asbd.isEquivalentStreamFormat(to: otherAudio.asbd) else {
            throw AmbiMuxError.concatFormatMismatch(
                referencePath: referencePath,
                otherPath: otherPath,
                detail: "audio track \(index + 1) stream format differs"
            )
        }
        guard refAudio.channelLayoutTag == otherAudio.channelLayoutTag else {
            throw AmbiMuxError.concatFormatMismatch(
                referencePath: referencePath,
                otherPath: otherPath,
                detail: "audio track \(index + 1) channel layout differs"
            )
        }
    }
}

// MARK: - Composition

nonisolated private func orderedAudioTracks(from asset: AVURLAsset) async throws -> [AVAssetTrack] {
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
        throw AmbiMuxError.noAudioTracksFound
    }

    var ambisonicsTrack: AVAssetTrack?
    var fallbackTrack: AVAssetTrack?

    for track in audioTracks {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let asbd = formatDescription.audioStreamBasicDescription
        else {
            continue
        }

        let channels = Int(asbd.mChannelsPerFrame)
        if AmbisonicsOrder(channelCount: channels) != nil {
            if ambisonicsTrack == nil {
                ambisonicsTrack = track
            }
        } else if channels == 1 || channels == 2 {
            if fallbackTrack == nil {
                fallbackTrack = track
            }
        } else {
            throw AmbiMuxError.invalidChannelCount(count: channels)
        }
    }

    guard let ambisonics = ambisonicsTrack else {
        throw AmbiMuxError.noAmbisonicsTrackFound
    }

    var result = [ambisonics]
    if let fallback = fallbackTrack {
        result.append(fallback)
    }
    return result
}

private func buildComposition(from assets: [AVURLAsset]) async throws -> AVMutableComposition {
    let composition = AVMutableComposition()

    guard let firstAsset = assets.first else {
        throw AmbiMuxError.concatRequiresAtLeastTwoInputs
    }

    let firstVideoTracks = try await firstAsset.loadTracks(withMediaType: .video)
    guard let firstVideoTrack = firstVideoTracks.first else {
        throw AmbiMuxError.videoTrackNotFound
    }

    let firstOrderedAudio = try await orderedAudioTracks(from: firstAsset)

    guard let compositionVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        throw AmbiMuxError.concatCompositionFailed(message: "Could not create composition video track")
    }

    compositionVideoTrack.preferredTransform = try await firstVideoTrack.load(.preferredTransform)

    var compositionAudioTracks: [AVMutableCompositionTrack] = []
    for _ in firstOrderedAudio {
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AmbiMuxError.concatCompositionFailed(message: "Could not create composition audio track")
        }
        compositionAudioTracks.append(track)
    }

    var cursor = CMTime.zero
    for asset in assets {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw AmbiMuxError.videoTrackNotFound
        }

        let segmentRange = try await videoTrack.load(.timeRange)
        let orderedAudio = try await orderedAudioTracks(from: asset)

        guard orderedAudio.count == compositionAudioTracks.count else {
            throw AmbiMuxError.concatCompositionFailed(
                message: "Audio track count mismatch during composition"
            )
        }

        var audioInsertRanges: [CMTimeRange] = []
        for audioTrack in orderedAudio {
            let audioRange = try await audioTrack.load(.timeRange)
            let clampedDuration = CMTimeMinimum(audioRange.duration, segmentRange.duration)
            audioInsertRanges.append(
                CMTimeRange(start: audioRange.start, duration: clampedDuration))
        }

        do {
            try compositionVideoTrack.insertTimeRange(segmentRange, of: videoTrack, at: cursor)
            for (index, audioTrack) in orderedAudio.enumerated() {
                try compositionAudioTracks[index].insertTimeRange(
                    audioInsertRanges[index], of: audioTrack, at: cursor)
            }
        } catch {
            throw AmbiMuxError.concatCompositionFailed(message: error.localizedDescription)
        }

        cursor = CMTimeAdd(cursor, segmentRange.duration)
    }

    return composition
}

// MARK: - Public API

nonisolated public func runJoinMOV(inputPaths: [String], outputPath: String) async throws {
    guard inputPaths.count >= 2 else {
        throw AmbiMuxError.concatRequiresAtLeastTwoInputs
    }

    for path in inputPaths {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
    }

    var referenceSignature: MOVJoinFormatSignature?
    var referencePath: String?
    var assets: [AVURLAsset] = []

    for path in inputPaths {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let signature = try await collectFormatSignature(from: asset)

        if let referenceSignature, let referencePath {
            try validateCompatibility(
                reference: referenceSignature,
                referencePath: referencePath,
                other: signature,
                otherPath: path
            )
        } else {
            referenceSignature = signature
            referencePath = path
        }

        assets.append(asset)
    }

    let hasFallbackAudio = (referenceSignature?.audioTracks.count ?? 0) > 1

    try await joinValidatedAssets(
        assets: assets,
        outputPath: outputPath,
        hasFallbackAudio: hasFallbackAudio
    )
}

private func joinValidatedAssets(
    assets: [AVURLAsset],
    outputPath: String,
    hasFallbackAudio: Bool
) async throws {
    let composition = try await buildComposition(from: assets)
    try await exportCompositionPassthrough(
        composition: composition,
        outputURL: URL(fileURLWithPath: outputPath),
        hasFallbackAudio: hasFallbackAudio
    )
    print("Join completed: \(outputPath)")
}
