@preconcurrency import AVFoundation
import CoreAudioTypes
import CoreMedia
import Foundation
import os

// Process audio samples using provider pattern
nonisolated func processAudioSamples(
    provider: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>,
    writerInput: AVAssetWriterInput
) async throws {
    while let readySampleBuffer = try await provider.next() {
        // Extract CMSampleBuffer from CMReadySampleBuffer and append to writer input
        try readySampleBuffer.withUnsafeSampleBuffer { cmSampleBuffer in
            writerInput.append(cmSampleBuffer)
        }
    }
    writerInput.markAsFinished()
}

// Process video samples using provider pattern
nonisolated func processVideoSamples(
    provider: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>,
    writerInput: AVAssetWriterInput
) async throws {
    while let readySampleBuffer = try await provider.next() {
        // Extract CMSampleBuffer from CMReadySampleBuffer and append to writer input
        try readySampleBuffer.withUnsafeSampleBuffer { cmSampleBuffer in
            writerInput.append(cmSampleBuffer)
        }
    }
    writerInput.markAsFinished()
}

// Process video and audio and output to MOV file
nonisolated func convertVideoWithAudioToMOV(
    audioPath: String, videoPath: String, outputPath: String
) async throws {
    let audioURL = URL(fileURLWithPath: audioPath)
    let videoURL = URL(fileURLWithPath: videoPath)
    let outputURL = URL(fileURLWithPath: outputPath)
    // Create AVURLAsset for audio file
    let audioAsset = AVURLAsset(url: audioURL)

    // Create AVURLAsset for video file
    let videoAsset = AVURLAsset(url: videoURL)

    // Get audio track
    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
    guard let audioTrack = audioTracks.first else {
        throw AmbiMuxError.audioTrackNotFound
    }

    // Get video track
    let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
        throw AmbiMuxError.videoTrackNotFound
    }
    
    // Get video frame size for pixel buffer attributes
    let videoFrameSize = try await videoTrack.load(.naturalSize)

    // Do not use audio tracks from video file

    // Get input format information
    let formatDescriptions = try await audioTrack.load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first else {
        throw AmbiMuxError.couldNotRetrieveFormatInformation
    }

    guard
        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
            formatDescription)
    else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }
    let sampleRate = audioStreamBasicDescription.pointee.mSampleRate
    let formatID = audioStreamBasicDescription.pointee.mFormatID
    let isAPAC = (formatID == kAudioFormatAPAC)

    // Create AVAssetReader
    let audioAssetReader = try AVAssetReader(asset: audioAsset)
    let videoAssetReader = try AVAssetReader(asset: videoAsset)

    // Create AVAssetReaderTrackOutput
    // For APAC, read in original format (avoid re-encoding)
    let audioReaderOutput: AVAssetReaderTrackOutput
    if isAPAC {
        // Setting outputSettings to nil reads in original format (APAC)
        audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    } else {
        // For non-APAC, convert to LinearPCM
        let ambisonicsLayout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_HOA_ACN_SN3D | 4)!
        let layoutData = Data(
            bytes: ambisonicsLayout.layout, count: MemoryLayout<AudioChannelLayout>.size)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVChannelLayoutKey: layoutData,
        ]
        audioReaderOutput = AVAssetReaderTrackOutput(
            track: audioTrack, outputSettings: outputSettings)
    }
    // Note: outputProvider(for:) internally calls addOutput, so we don't need to call add() separately
    // Get audio provider (this will add the output internally)
    let audioProvider = audioAssetReader.outputProvider(for: audioReaderOutput)

    // Create AVAssetReaderTrackOutput for video
    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    
    // Get video provider (this will add the output internally)
    let videoProvider = videoAssetReader.outputProvider(for: videoReaderOutput)

    // Create AVAssetWriter
    let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    
    // Create AVAssetWriterInput
    // For APAC, write in original format (avoid re-encoding)
    let audioInput: AVAssetWriterInput
    if isAPAC {
        // Set outputSettings to nil and inherit original format info via sourceFormatHint
        audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: formatDescription)
    } else {
        // For non-APAC, encode normally
        let ambisonicsLayout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_HOA_ACN_SN3D | 4)!
        let layoutData = Data(
            bytes: ambisonicsLayout.layout, count: MemoryLayout<AudioChannelLayout>.size)
        let writerAudioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAPAC,
            AVSampleRateKey: min(sampleRate, 48000),
            AVNumberOfChannelsKey: 4,
            AVChannelLayoutKey: layoutData,
            AVEncoderBitRateKey: 384000,
            AVEncoderContentSourceKey: AVAudioContentSource.appleAV_Spatial_Offline.rawValue,
            AVEncoderDynamicRangeControlConfigurationKey: AVAudioDynamicRangeControlConfiguration
                .movie.rawValue,
            AVEncoderASPFrequencyKey: 75,
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerAudioSettings)
    }
    audioInput.expectsMediaDataInRealTime = false

    // Create AVAssetWriterInput for video
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
    videoInput.expectsMediaDataInRealTime = false

    if assetWriter.canAdd(videoInput) {
        assetWriter.add(videoInput)
    }

    if assetWriter.canAdd(audioInput) {
        assetWriter.add(audioInput)
    }

    // Start reading and writing using new API
    try assetWriter.start()
    assetWriter.startSession(atSourceTime: .zero)
    try videoAssetReader.start()
    try audioAssetReader.start()

    // Process video and audio samples concurrently using provider pattern
    try await withThrowingTaskGroup(of: Void.self) { group in
        // Process video samples
        group.addTask {
            try await processVideoSamples(
                provider: videoProvider,
                writerInput: videoInput
            )
        }
        
        // Process audio samples
        group.addTask {
            try await processAudioSamples(
                provider: audioProvider,
                writerInput: audioInput
            )
        }
        
        // Wait for both tasks to complete
        try await group.waitForAll()
    }

    // Use async version of finishWriting
    await assetWriter.finishWriting()

    // Check status after writing completes
    if assetWriter.status == .completed {
        print("Conversion completed: \(outputPath)")
    } else {
        let errorMessage = assetWriter.error?.localizedDescription ?? "Unknown error"
        throw AmbiMuxError.conversionFailed(message: errorMessage)
    }
}
