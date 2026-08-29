import AVFoundation
import CoreAudioTypes
import CoreGraphics
import CoreMedia
import Darwin
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

nonisolated private func channelLayoutTag(from formatDescription: CMFormatDescription)
    -> AudioChannelLayoutTag?
{
    var layoutSize: Int = 0
    guard
        let channelLayout = CMAudioFormatDescriptionGetChannelLayout(
            formatDescription, sizeOut: &layoutSize)
    else {
        return nil
    }
    return channelLayout.pointee.mChannelLayoutTag
}

nonisolated private func audioTrackRole(for channelCount: Int) throws
    -> MOVJoinFormatSignature.AudioTrackRole
{
    if AmbisonicsOrder(channelCount: channelCount) != nil {
        return .ambisonics
    }
    if channelCount == 1 || channelCount == 2 {
        return .fallback
    }
    throw AmbiMuxError.invalidChannelCount(count: channelCount)
}

nonisolated private struct ClassifiedAudioTrack {
    let track: AVAssetTrack
    let role: MOVJoinFormatSignature.AudioTrackRole
    let asbd: AudioStreamBasicDescription
    let formatDescription: CMFormatDescription
}

nonisolated private func selectOrderedAudioTracks(
    from audioTracks: [AVAssetTrack]
) async throws -> [ClassifiedAudioTrack] {
    var ambisonics: ClassifiedAudioTrack?
    var fallback: ClassifiedAudioTrack?

    for track in audioTracks {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let asbd = formatDescription.audioStreamBasicDescription
        else {
            throw AmbiMuxError.couldNotGetAudioStreamDescription
        }

        let role = try audioTrackRole(for: Int(asbd.mChannelsPerFrame))
        let classified = ClassifiedAudioTrack(
            track: track, role: role, asbd: asbd, formatDescription: formatDescription)

        switch role {
        case .ambisonics:
            if ambisonics == nil { ambisonics = classified }
        case .fallback:
            if fallback == nil { fallback = classified }
        }
    }

    guard let ambisonics else {
        throw AmbiMuxError.noAmbisonicsTrackFound
    }

    var result = [ambisonics]
    if let fallback { result.append(fallback) }
    return result
}

nonisolated private func collectAudioTrackSignatures(
    from audioTracks: [AVAssetTrack]
) async throws -> [MOVJoinFormatSignature.AudioTrackSignature] {
    let classified = try await selectOrderedAudioTracks(from: audioTracks)
    return classified.map { entry in
        MOVJoinFormatSignature.AudioTrackSignature(
            role: entry.role,
            asbd: entry.asbd,
            channelLayoutTag: channelLayoutTag(from: entry.formatDescription)
        )
    }
}

nonisolated func collectFormatSignature(from asset: AVURLAsset) async throws
    -> MOVJoinFormatSignature
{
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
            detail:
                "video resolution differs (\(refVideo.width)x\(refVideo.height) vs \(otherVideo.width)x\(otherVideo.height))"
        )
    }
    guard frameRatesAreEquivalent(refVideo.nominalFrameRate, otherVideo.nominalFrameRate) else {
        throw AmbiMuxError.concatFormatMismatch(
            referencePath: referencePath,
            otherPath: otherPath,
            detail:
                "video frame rate differs (\(refVideo.nominalFrameRate) vs \(otherVideo.nominalFrameRate) fps)"
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
            detail:
                "audio track count differs (\(reference.audioTracks.count) vs \(other.audioTracks.count))"
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

// MARK: - Segment model

/// One join input: a MOV path with an optional half-open time range `[start, end)` in seconds.
public struct JoinSegment: Sendable, Equatable {
    public let path: String
    public let startSeconds: Double?
    public let endSeconds: Double?

    nonisolated public init(path: String, startSeconds: Double? = nil, endSeconds: Double? = nil) {
        self.path = path
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

/// Parses `path` or `path@START-END` (seconds). If the suffix after the last `@` is not a valid
/// range, the whole argument is treated as a path.
nonisolated public func parseJoinSegmentArgument(_ argument: String) throws -> JoinSegment {
    guard let atIndex = argument.lastIndex(of: "@"), atIndex > argument.startIndex else {
        return JoinSegment(path: argument)
    }

    let path = String(argument[..<atIndex])
    let rangePart = String(argument[argument.index(after: atIndex)...])
    guard !path.isEmpty else {
        throw AmbiMuxError.concatInvalidSegmentArgument(
            argument: argument,
            detail: "path before '@' is empty"
        )
    }

    guard let dashIndex = rangePart.firstIndex(of: "-"), dashIndex > rangePart.startIndex,
        dashIndex < rangePart.index(before: rangePart.endIndex)
    else {
        // Not a time-range suffix; treat the whole argument as a literal path.
        return JoinSegment(path: argument)
    }

    let startText = String(rangePart[..<dashIndex])
    let endText = String(rangePart[rangePart.index(after: dashIndex)...])
    guard let start = Double(startText), let end = Double(endText) else {
        return JoinSegment(path: argument)
    }

    guard start >= 0, end > start else {
        throw AmbiMuxError.concatInvalidSegmentArgument(
            argument: argument,
            detail: "expected start < end with non-negative seconds (got \(startText)-\(endText))"
        )
    }

    return JoinSegment(path: path, startSeconds: start, endSeconds: end)
}

// MARK: - Composition

nonisolated private func orderedAudioTracks(from asset: AVURLAsset) async throws -> [AVAssetTrack] {
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
        throw AmbiMuxError.noAudioTracksFound
    }
    let classified = try await selectOrderedAudioTracks(from: audioTracks)
    return classified.map(\.track)
}

nonisolated private let joinTimeRangeToleranceSeconds: Double = 0.001

nonisolated private func resolveSourceTimeRange(
    for videoTrack: AVAssetTrack,
    segment: JoinSegment
) async throws -> CMTimeRange {
    let fullRange = try await videoTrack.load(.timeRange)
    let timescale = fullRange.duration.timescale == 0 ? 600 : fullRange.duration.timescale
    let fullStartSeconds = CMTimeGetSeconds(fullRange.start)
    let fullEndSeconds = fullStartSeconds + CMTimeGetSeconds(fullRange.duration)

    let startSeconds = segment.startSeconds ?? fullStartSeconds
    let endSeconds = segment.endSeconds ?? fullEndSeconds

    guard startSeconds >= 0, endSeconds > startSeconds else {
        throw AmbiMuxError.concatInvalidTimeRange(
            path: segment.path,
            detail: "start (\(startSeconds)) must be < end (\(endSeconds)) and non-negative"
        )
    }

    if startSeconds + joinTimeRangeToleranceSeconds < fullStartSeconds
        || endSeconds > fullEndSeconds + joinTimeRangeToleranceSeconds
    {
        throw AmbiMuxError.concatInvalidTimeRange(
            path: segment.path,
            detail:
                "range \(startSeconds)-\(endSeconds)s is outside media \(fullStartSeconds)-\(fullEndSeconds)s"
        )
    }

    let clampedStart = max(startSeconds, fullStartSeconds)
    let clampedEnd = min(endSeconds, fullEndSeconds)
    let startTime = CMTime(seconds: clampedStart, preferredTimescale: timescale)
    let endTime = CMTime(seconds: clampedEnd, preferredTimescale: timescale)
    return CMTimeRange(start: startTime, end: endTime)
}

private struct ValidatedJoinAsset {
    let segment: JoinSegment
    let asset: AVURLAsset
}

private func buildComposition(from items: [ValidatedJoinAsset]) async throws -> AVMutableComposition
{
    let composition = AVMutableComposition()

    guard let firstItem = items.first else {
        throw AmbiMuxError.concatRequiresAtLeastOneInput
    }

    let firstVideoTracks = try await firstItem.asset.loadTracks(withMediaType: .video)
    guard let firstVideoTrack = firstVideoTracks.first else {
        throw AmbiMuxError.videoTrackNotFound
    }

    let firstOrderedAudio = try await orderedAudioTracks(from: firstItem.asset)

    guard
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
    else {
        throw AmbiMuxError.concatCompositionFailed(
            message: "Could not create composition video track")
    }

    compositionVideoTrack.preferredTransform = try await firstVideoTrack.load(.preferredTransform)

    var compositionAudioTracks: [AVMutableCompositionTrack] = []
    for _ in firstOrderedAudio {
        guard
            let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AmbiMuxError.concatCompositionFailed(
                message: "Could not create composition audio track")
        }
        compositionAudioTracks.append(track)
    }

    var cursor = CMTime.zero
    for item in items {
        let videoTracks = try await item.asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw AmbiMuxError.videoTrackNotFound
        }

        let segmentRange = try await resolveSourceTimeRange(for: videoTrack, segment: item.segment)
        let orderedAudio = try await orderedAudioTracks(from: item.asset)

        guard orderedAudio.count == compositionAudioTracks.count else {
            throw AmbiMuxError.concatCompositionFailed(
                message: "Audio track count mismatch during composition"
            )
        }

        var audioInsertRanges: [CMTimeRange] = []
        for audioTrack in orderedAudio {
            let audioRange = try await audioTrack.load(.timeRange)
            let audioEnd = CMTimeAdd(audioRange.start, audioRange.duration)
            let overlapStart = CMTimeMaximum(segmentRange.start, audioRange.start)
            let overlapEnd = CMTimeMinimum(CMTimeRangeGetEnd(segmentRange), audioEnd)
            let overlapDuration = CMTimeSubtract(overlapEnd, overlapStart)
            guard CMTIME_IS_NUMERIC(overlapDuration),
                CMTimeCompare(overlapDuration, .zero) > 0
            else {
                throw AmbiMuxError.concatInvalidTimeRange(
                    path: item.segment.path,
                    detail: "requested range has no overlapping audio"
                )
            }
            audioInsertRanges.append(CMTimeRange(start: overlapStart, duration: overlapDuration))
        }

        // Keep A/V insert durations aligned to the video segment.
        let videoDuration = segmentRange.duration
        let alignedAudioRanges: [CMTimeRange] = audioInsertRanges.map { audioRange in
            let duration = CMTimeMinimum(audioRange.duration, videoDuration)
            return CMTimeRange(start: audioRange.start, duration: duration)
        }

        do {
            try compositionVideoTrack.insertTimeRange(segmentRange, of: videoTrack, at: cursor)
            for (index, audioTrack) in orderedAudio.enumerated() {
                try compositionAudioTracks[index].insertTimeRange(
                    alignedAudioRanges[index], of: audioTrack, at: cursor)
            }
        } catch {
            throw AmbiMuxError.concatCompositionFailed(message: error.localizedDescription)
        }

        cursor = CMTimeAdd(cursor, videoDuration)
    }

    return composition
}

// MARK: - Public API

nonisolated public func runJoinMOV(inputPaths: [String], outputPath: String) async throws {
    try await runJoinMOV(
        segments: inputPaths.map { JoinSegment(path: $0) },
        outputPath: outputPath
    )
}

nonisolated public func runJoinMOV(segments: [JoinSegment], outputPath: String) async throws {
    guard segments.count >= 1 else {
        throw AmbiMuxError.concatRequiresAtLeastOneInput
    }

    for segment in segments {
        guard FileManager.default.fileExists(atPath: segment.path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: segment.path])
        }
    }

    var referenceSignature: MOVJoinFormatSignature?
    var referencePath: String?
    var items: [ValidatedJoinAsset] = []

    for segment in segments {
        let asset = AVURLAsset(url: URL(fileURLWithPath: segment.path))
        let signature = try await collectFormatSignature(from: asset)

        if let referenceSignature, let referencePath {
            try validateCompatibility(
                reference: referenceSignature,
                referencePath: referencePath,
                other: signature,
                otherPath: segment.path
            )
        } else {
            referenceSignature = signature
            referencePath = segment.path
        }

        items.append(ValidatedJoinAsset(segment: segment, asset: asset))
    }

    let hasFallbackAudio = (referenceSignature?.audioTracks.count ?? 0) > 1

    try await joinValidatedAssets(
        items: items,
        outputPath: outputPath,
        hasFallbackAudio: hasFallbackAudio
    )
}

private func joinValidatedAssets(
    items: [ValidatedJoinAsset],
    outputPath: String,
    hasFallbackAudio: Bool
) async throws {
    let composition = try await buildComposition(from: items)
    try await exportCompositionPassthrough(
        composition: composition,
        outputURL: URL(fileURLWithPath: outputPath),
        hasFallbackAudio: hasFallbackAudio
    )
    print("Join completed: \(outputPath)")
    fflush(stdout)
}
