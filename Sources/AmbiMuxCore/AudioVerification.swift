import AVFoundation
import CoreAudioTypes
import Foundation

struct ConversionEligibilityStatus {
    let isEligible: Bool
    let reason: String
}

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

/// 映像の音声トラックを走査し、Ambisonics（4/9/16ch）とモノ/ステレオ（全トラック）を検出する
/// - Returns: (ambisonicsTrack, fallbackTrack) フォールバックは存在しない場合 nil
/// - Throws: noAmbisonicsTrackFound  Ambisonics トラックが1つもない場合
nonisolated func scanVideoAudioTracks(videoAsset: AVURLAsset) async throws -> (
    ambisonics: AVAssetTrack, fallback: AVAssetTrack?
) {
    let audioTracks = try await videoAsset.loadTracks(withMediaType: .audio)

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
        }
    }

    guard let ambisonics = ambisonicsTrack else {
        throw AmbiMuxError.noAmbisonicsTrackFound
    }

    return (ambisonics, fallbackTrack)
}

/// 映像の音声トラックを走査し、モノ/ステレオのトラックを検出する（apac/lpcm 用フォールバック）
/// - Returns: 最初に見つかった 1ch/2ch トラック、なければ nil
nonisolated func scanVideoFallbackTrack(videoAsset: AVURLAsset) async throws -> AVAssetTrack? {
    let audioTracks = try await videoAsset.loadTracks(withMediaType: .audio)

    for track in audioTracks {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let asbd = formatDescription.audioStreamBasicDescription
        else {
            continue
        }

        let channels = Int(asbd.mChannelsPerFrame)
        if channels == 1 || channels == 2 {
            return track
        }
    }

    return nil
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

/// Validates embedded spatial audio before conversion: an Ambisonics track (4/9/16ch) must exist,
/// and the primary Ambisonics track must not already be APAC (no re-encode needed).
nonisolated func validateEmbeddedLpcmAudio(videoPath: String) async throws {
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let scanResult = try await scanVideoAudioTracks(videoAsset: videoAsset)
    if try await isTrackAPAC(scanResult.ambisonics) {
        throw AmbiMuxError.embeddedAmbisonicsAlreadyAPAC
    }
}

nonisolated func evaluateVideoInputEligibility(videoPath: String) async throws -> ConversionEligibilityStatus {
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let audioTracks = try await videoAsset.loadTracks(withMediaType: .audio)

    guard !audioTracks.isEmpty else {
        return ConversionEligibilityStatus(
            isEligible: false,
            reason: "No audio tracks found"
        )
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

        if asbd.mFormatID == kAudioFormatAPAC {
            hasAPAC = true
        }

        let channels = Int(asbd.mChannelsPerFrame)
        if AmbisonicsOrder(channelCount: channels) != nil {
            hasAmbisonics = true
        }
    }

    if hasAPAC {
        return ConversionEligibilityStatus(
            isEligible: false,
            reason: "APAC track is already present in the video"
        )
    }
    if !hasAmbisonics {
        return ConversionEligibilityStatus(
            isEligible: false,
            reason: "No Ambisonics track (4/9/16ch) found in the video"
        )
    }
    return ConversionEligibilityStatus(
        isEligible: true,
        reason: "Ambisonics is present and APAC is not present"
    )
}

nonisolated func evaluateAudioInputEligibility(audioPath: String) async throws -> ConversionEligibilityStatus {
    let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)

    guard !audioTracks.isEmpty else {
        return ConversionEligibilityStatus(
            isEligible: false,
            reason: "No audio tracks found"
        )
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

        if asbd.mFormatID == kAudioFormatAPAC {
            hasAPAC = true
        }

        let channels = Int(asbd.mChannelsPerFrame)
        if AmbisonicsOrder(channelCount: channels) != nil {
            hasAmbisonics = true
        }
    }

    if hasAPAC {
        return ConversionEligibilityStatus(
            isEligible: true,
            reason: "APAC audio is present"
        )
    }
    if hasAmbisonics {
        return ConversionEligibilityStatus(
            isEligible: true,
            reason: "Ambisonics audio (4/9/16ch) is present"
        )
    }
    return ConversionEligibilityStatus(
        isEligible: false,
        reason: "Neither APAC nor Ambisonics (4/9/16ch) audio is present"
    )
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
