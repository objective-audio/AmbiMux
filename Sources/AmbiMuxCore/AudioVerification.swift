import AVFoundation
import CoreAudioTypes
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

// Validate embedded LPCM audio channel count in a video file
nonisolated func validateEmbeddedLpcmAudio(videoPath: String) async throws {
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let audioTracks = try await videoAsset.loadTracks(withMediaType: .audio)

    guard !audioTracks.isEmpty else {
        throw AmbiMuxError.noAudioTracksFound
    }

    let formatDescriptions = try await audioTracks[0].load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first,
        let asbd = formatDescription.audioStreamBasicDescription
    else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }

    let channels = Int(asbd.mChannelsPerFrame)
    guard AmbisonicsOrder(channelCount: channels) != nil else {
        throw AmbiMuxError.invalidChannelCount(count: channels)
    }
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
