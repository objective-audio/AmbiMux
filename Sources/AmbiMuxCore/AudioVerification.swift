import AVFoundation
import CoreAudioTypes
import CoreMedia
import Foundation

// Detect audio input mode from file format
nonisolated func detectAudioInputMode(audioPath: String) async throws -> AudioInputMode {
    let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)

    guard !audioTracks.isEmpty else {
        throw AmbiMuxError.noAudioTracksFound
    }

    let formatDescriptions = try await audioTracks[0].load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first,
        let asbd = formatDescription.audioStreamBasicDescription
    else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }

    if asbd.mFormatID == kAudioFormatAPAC {
        return .apac
    }

    let channels = Int(asbd.mChannelsPerFrame)
    guard AmbisonicsOrder(channelCount: channels) != nil else {
        throw AmbiMuxError.invalidChannelCount(count: channels)
    }
    return .lpcm
}

/// 映像の音声トラックを走査し、最初の Ambisonics（4/9/16ch）トラックを返す
/// - Throws: `noAudioTracksFound` / `noAmbisonicsTrackFound`
nonisolated func scanVideoAmbisonicsTrack(videoAsset: AVURLAsset) async throws -> AVAssetTrack {
    let audioTracks = try await videoAsset.loadTracks(withMediaType: .audio)

    guard !audioTracks.isEmpty else {
        throw AmbiMuxError.noAudioTracksFound
    }

    var ambisonicsTrack: AVAssetTrack?

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
        }
    }

    guard let ambisonics = ambisonicsTrack else {
        throw AmbiMuxError.noAmbisonicsTrackFound
    }

    return ambisonics
}

nonisolated private func isTrackAPAC(_ track: AVAssetTrack) async throws -> Bool {
    let formatDescriptions = try await track.load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first,
        let asbd = formatDescription.audioStreamBasicDescription
    else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }
    return asbd.mFormatID == kAudioFormatAPAC
}

/// True when the stream is not APAC but `CMFormatDescription` carries HOA ACN SN3D layout metadata.
nonisolated func hasNonAPACWithHOALayoutTag(
    formatDescription: CMFormatDescription,
    formatID: AudioFormatID
) -> Bool {
    guard formatID != kAudioFormatAPAC else { return false }
    var layoutSize: Int = 0
    guard
        let channelLayout = CMAudioFormatDescriptionGetChannelLayout(
            formatDescription, sizeOut: &layoutSize)
    else {
        return false
    }
    let layoutTag = channelLayout.pointee.mChannelLayoutTag
    return layoutTag & kAudioChannelLayoutTag_HOA_ACN_SN3D == kAudioChannelLayoutTag_HOA_ACN_SN3D
}

/// Validates embedded spatial audio before conversion: an Ambisonics track (4/9/16ch) must exist,
/// and the primary Ambisonics track must not already be APAC (no re-encode needed).
nonisolated func validateEmbeddedLpcmAudio(videoPath: String) async throws {
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let ambisonics = try await scanVideoAmbisonicsTrack(videoAsset: videoAsset)
    if try await isTrackAPAC(ambisonics) {
        throw AmbiMuxError.embeddedAmbisonicsAlreadyAPAC
    }
}

nonisolated func evaluateVideoInputEligibility(videoPath: String) async throws
    -> VideoValidationResult
{
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
    guard !videoTracks.isEmpty else {
        return .ineligible(.noVideoTracks)
    }

    let audioTracks = try await videoAsset.loadTracks(withMediaType: .audio)

    guard !audioTracks.isEmpty else {
        return .eligible(.noEmbeddedAudioUseExternal)
    }

    var hasAPAC = false
    var hasAmbisonics = false

    for track in audioTracks {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let asbd = formatDescription.audioStreamBasicDescription
        else {
            continue
        }

        if hasNonAPACWithHOALayoutTag(
            formatDescription: formatDescription, formatID: asbd.mFormatID)
        {
            return .ineligible(.nonAPACWithHOALayoutTag)
        }

        if asbd.mFormatID == kAudioFormatAPAC {
            hasAPAC = true
        }

        let channels = Int(asbd.mChannelsPerFrame)
        if AmbisonicsOrder(channelCount: channels) != nil {
            hasAmbisonics = true
        }
    }

    if hasAPAC {
        return .ineligible(.alreadyHasAPAC)
    }
    if hasAmbisonics {
        return .eligible(.ambisonicsWithoutAPAC)
    }
    return .eligible(.nonSpatialEmbeddedAudio)
}

nonisolated func evaluateAudioInputEligibility(audioPath: String) async throws
    -> AudioValidationResult
{
    let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)

    guard !audioTracks.isEmpty else {
        return .ineligible(.noAudioTracks)
    }

    var hasAPAC = false
    var hasAmbisonics = false
    var detectedOrder: AmbisonicsOrder?

    for track in audioTracks {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let asbd = formatDescription.audioStreamBasicDescription
        else {
            continue
        }

        if hasNonAPACWithHOALayoutTag(
            formatDescription: formatDescription, formatID: asbd.mFormatID)
        {
            return .ineligible(.nonAPACWithHOALayoutTag)
        }

        if asbd.mFormatID == kAudioFormatAPAC {
            hasAPAC = true
        }

        let channels = Int(asbd.mChannelsPerFrame)
        if let order = AmbisonicsOrder(channelCount: channels) {
            hasAmbisonics = true
            if detectedOrder == nil {
                detectedOrder = order
            }
        }
    }

    if hasAPAC {
        return .eligible(.apac)
    }
    if hasAmbisonics, let order = detectedOrder {
        return .eligible(.ambisonics(order))
    }
    return .ineligible(.missingAPACAndAmbisonics)
}

// Display detailed information of output file
nonisolated func verifyOutputFileDetails(outputPath: String) async throws {
    print("\nChecking output file details...")

    let outputURL = URL(fileURLWithPath: outputPath)
    let asset = AVURLAsset(url: outputURL)

    // Get file size
    do {
        let attributes = try FileManager.default.attributesOfItem(atPath: outputPath)
        if let fileSize = attributes[.size] as? NSNumber {
            let fileSizeMB = fileSize.doubleValue / (1024 * 1024)
            print("File size: \(String(format: "%.2f", fileSizeMB))MB")
        }
    } catch {
        print("Failed to get file size")
    }

    // Video track information
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    print("Video tracks: \(videoTracks.count)")

    for (index, track) in videoTracks.enumerated() {
        print("   Video track \(index + 1):")
        let timeRange = try await track.load(.timeRange)
        print("     - Duration: \(String(format: "%.2f", CMTimeGetSeconds(timeRange.duration)))s")
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        print("     - Frame rate: \(nominalFrameRate)fps")
        let naturalSize = try await track.load(.naturalSize)
        print("     - Resolution: \(Int(naturalSize.width))x\(Int(naturalSize.height))")
    }

    // Audio track information
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    print("Audio tracks: \(audioTracks.count)")

    for (index, track) in audioTracks.enumerated() {
        print("   Audio track \(index + 1):")
        let timeRange = try await track.load(.timeRange)
        print("     - Duration: \(String(format: "%.2f", CMTimeGetSeconds(timeRange.duration)))s")

        // Get format information
        let formatDescriptions = try await track.load(.formatDescriptions)
        if let formatDescription = formatDescriptions.first {
            if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription)
            {
                let sampleRate = audioStreamBasicDescription.pointee.mSampleRate
                let channelCount = Int(audioStreamBasicDescription.pointee.mChannelsPerFrame)
                let formatID = audioStreamBasicDescription.pointee.mFormatID
                print("     - Sample rate: \(sampleRate)Hz")
                print("     - Channel count: \(channelCount)")
                print("     - Format ID: \(formatID)")

                // Display format name
                let formatName = getAudioFormatName(formatID: formatID)
                print("     - Format: \(formatName)")

                // Channel layout information
                var layoutSize: Int = 0
                if let channelLayout = CMAudioFormatDescriptionGetChannelLayout(
                    formatDescription, sizeOut: &layoutSize)
                {
                    let layoutTag = channelLayout.pointee.mChannelLayoutTag
                    let layoutName = getChannelLayoutName(layoutTag: layoutTag)
                    print("     - Channel layout: \(layoutName)")
                }
            }
        }
    }

    print("Output file verification completed")
}

// Get audio format name
nonisolated private func getAudioFormatName(formatID: AudioFormatID) -> String {
    if formatID == kAudioFormatAPAC {
        return "APAC (Ambisonics)"
    }
    return "Unknown (\(formatID))"
}

// Get channel layout name
nonisolated private func getChannelLayoutName(layoutTag: AudioChannelLayoutTag) -> String {
    // Only SN3D is assumed after conversion. Channel count is included in lower 16 bits of tag
    if layoutTag & kAudioChannelLayoutTag_HOA_ACN_SN3D == kAudioChannelLayoutTag_HOA_ACN_SN3D {
        let channelCount = layoutTag & 0xFFFF
        return "HOA ACN SN3D (\(channelCount) channels)"
    }
    return "Unknown (\(layoutTag))"
}
