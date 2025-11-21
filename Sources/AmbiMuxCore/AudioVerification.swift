import AVFoundation
import CoreAudioTypes
import Foundation

// Validate audio file
nonisolated func validateAudioFile(audioPath: String) async throws {
    let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)

    guard !audioTracks.isEmpty else {
        throw AmbiMuxError.noAudioTracksFound
    }

    let audioTrack = audioTracks[0]
    let formatDescriptions = try await audioTrack.load(.formatDescriptions)
    let audioFormat = formatDescriptions[0]
    guard
        let audioStreamBasicDescriptionPtr = CMAudioFormatDescriptionGetStreamBasicDescription(
            audioFormat)
    else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }
    let audioStreamBasicDescription = audioStreamBasicDescriptionPtr.pointee

    // Check if it has 4 channels (skip check for APAC codec)
    let formatID = audioStreamBasicDescription.mFormatID
    if formatID != kAudioFormatAPAC {
        guard audioStreamBasicDescription.mChannelsPerFrame == 4 else {
            throw AmbiMuxError.invalidChannelCount(
                count: Int(audioStreamBasicDescription.mChannelsPerFrame))
        }
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
