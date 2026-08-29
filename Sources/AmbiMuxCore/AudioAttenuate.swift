import AVFoundation
import CoreAudioTypes
import CoreMedia
import Darwin
import Foundation
import os

nonisolated let attenuatePassthroughEpsilonDb: Double = 0.05

/// 単体の MOV（映像 + APAC Ambisonics）の音声レベルを下げて書き出す。`gainDb` は 0 以下。
nonisolated public func runAttenuateMOV(
    inputPath: String,
    outputPath: String,
    gainDb: Double
) async throws {
    guard FileManager.default.fileExists(atPath: inputPath) else {
        throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: inputPath])
    }
    guard gainDb <= 0 else {
        throw AmbiMuxError.attenuateGainMustNotBoost
    }

    let asset = AVURLAsset(url: URL(fileURLWithPath: inputPath))
    _ = try await requireAPACAmbisonicsTrack(in: asset)
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard videoTracks.first != nil else {
        throw AmbiMuxError.videoTrackNotFound
    }

    if abs(gainDb) < attenuatePassthroughEpsilonDb {
        try replaceItem(at: outputPath, withCopyOf: inputPath)
        printAttenuateCompletion(outputPath: outputPath, gainDb: 0, passthrough: true)
        return
    }

    let linearGain = Float(pow(10.0, gainDb / 20.0))
    try await writeAttenuatedAPACMOV(asset: asset, outputPath: outputPath, linearGain: linearGain)
    printAttenuateCompletion(outputPath: outputPath, gainDb: gainDb, passthrough: false)
}

nonisolated private func printAttenuateCompletion(
    outputPath: String,
    gainDb: Double,
    passthrough: Bool
) {
    let gainText = String(format: "%.1f", gainDb)
    if passthrough {
        print("Attenuate: gain \(gainText) dB (passthrough) → \(outputPath)")
    } else {
        print("Attenuate: gain \(gainText) dB → \(outputPath)")
    }
    fflush(stdout)
}

nonisolated private func replaceItem(at destination: String, withCopyOf source: String) throws {
    if FileManager.default.fileExists(atPath: destination) {
        try FileManager.default.removeItem(atPath: destination)
    }
    try FileManager.default.copyItem(atPath: source, toPath: destination)
}

private func writeAttenuatedAPACMOV(
    asset: AVURLAsset,
    outputPath: String,
    linearGain: Float
) async throws {
    if FileManager.default.fileExists(atPath: outputPath) {
        try FileManager.default.removeItem(atPath: outputPath)
    }

    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
        throw AmbiMuxError.videoTrackNotFound
    }
    let videoFormatDescriptions = try await videoTrack.load(.formatDescriptions)
    guard let videoFormatDescription = videoFormatDescriptions.first else {
        throw AmbiMuxError.couldNotRetrieveFormatInformation
    }

    let ambisonicsTrack = try await requireAPACAmbisonicsTrack(in: asset)
    let ambisonicsFormatDescriptions = try await ambisonicsTrack.load(.formatDescriptions)
    guard let ambisonicsFD = ambisonicsFormatDescriptions.first,
        let ambisonicsASBD = ambisonicsFD.audioStreamBasicDescription
    else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }
    let ambisonicsChannels = Int(ambisonicsASBD.mChannelsPerFrame)
    guard AmbisonicsOrder(channelCount: ambisonicsChannels) != nil else {
        throw AmbiMuxError.invalidChannelCount(count: ambisonicsChannels)
    }
    let sourceRate = ambisonicsASBD.mSampleRate > 0 ? ambisonicsASBD.mSampleRate : 48000
    let decodeRate = min(sourceRate, 48000)

    let videoReader = try AVAssetReader(asset: asset)
    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    videoReader.add(videoReaderOutput)

    let ambisonicsReader = try AVAssetReader(asset: asset)
    let ambisonicsReaderOutput = AVAssetReaderTrackOutput(
        track: ambisonicsTrack,
        outputSettings: linearPCMReaderOutputSettings(
            channelCount: ambisonicsChannels, sampleRate: decodeRate)
    )
    ambisonicsReader.add(ambisonicsReaderOutput)

    let fallbackTrack = try await scanVideoFallbackTrack(videoAsset: asset)
    var fallbackReader: AVAssetReader?
    var fallbackReaderOutput: AVAssetReaderTrackOutput?
    var fallbackChannelCount: Int?
    var fallbackSampleRate: Double?
    if let fallbackTrack {
        let fallbackFDs = try await fallbackTrack.load(.formatDescriptions)
        guard let fallbackFD = fallbackFDs.first,
            let fallbackASBD = fallbackFD.audioStreamBasicDescription
        else {
            throw AmbiMuxError.couldNotGetAudioStreamDescription
        }
        let channels = Int(fallbackASBD.mChannelsPerFrame)
        let rate = min(fallbackASBD.mSampleRate > 0 ? fallbackASBD.mSampleRate : decodeRate, 48000)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: fallbackTrack,
            outputSettings: linearPCMReaderOutputSettings(channelCount: channels, sampleRate: rate)
        )
        reader.add(output)
        fallbackReader = reader
        fallbackReaderOutput = output
        fallbackChannelCount = channels
        fallbackSampleRate = rate
    }

    let assetWriter = try AVAssetWriter(outputURL: URL(fileURLWithPath: outputPath), fileType: .mov)

    let videoWriterInput = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: nil,
        sourceFormatHint: videoFormatDescription
    )
    videoWriterInput.expectsMediaDataInRealTime = false
    videoWriterInput.transform = try await videoTrack.load(.preferredTransform)
    assetWriter.add(videoWriterInput)

    let ambisonicsWriterSettings = try apacWriterOutputSettings(
        channelCount: ambisonicsChannels, sampleRate: decodeRate)
    let ambisonicsWriterInput = AVAssetWriterInput(
        mediaType: .audio, outputSettings: ambisonicsWriterSettings)
    ambisonicsWriterInput.expectsMediaDataInRealTime = false
    ambisonicsWriterInput.languageCode = "und"
    ambisonicsWriterInput.extendedLanguageTag = "und"
    ambisonicsWriterInput.marksOutputTrackAsEnabled = true
    assetWriter.add(ambisonicsWriterInput)

    var fallbackWriterInput: AVAssetWriterInput?
    if let fallbackChannelCount, let fallbackSampleRate {
        let fallbackInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: linearPCMWriterOutputSettings(
                channelCount: fallbackChannelCount, sampleRate: fallbackSampleRate)
        )
        fallbackInput.expectsMediaDataInRealTime = false
        fallbackInput.languageCode = "und"
        fallbackInput.extendedLanguageTag = "und"
        fallbackInput.marksOutputTrackAsEnabled = true
        fallbackInput.marksOutputTrackAsEnabled = false
        assetWriter.add(fallbackInput)
        let associationType = AVAssetTrack.AssociationType.audioFallback.rawValue
        if fallbackInput.canAddTrackAssociation(
            withTrackOf: ambisonicsWriterInput, type: associationType)
        {
            fallbackInput.addTrackAssociation(
                withTrackOf: ambisonicsWriterInput, type: associationType)
        }
        fallbackWriterInput = fallbackInput
    }

    let hoaFDState = OSAllocatedUnfairLock<
        (referenceASBD: AudioStreamBasicDescription, hoaFormatDescription: CMFormatDescription)?
    >(initialState: nil)
    let ambisonicsMap: @Sendable (CMSampleBuffer) throws -> CMSampleBuffer = { buf in
        let gained = try sampleBufferByApplyingLinearGain(buf, linearGain: linearGain)
        guard let fd = gained.formatDescription else {
            throw AmbiMuxError.ambisonicsSampleBufferMissingFormatDescription
        }
        guard let asbd = fd.audioStreamBasicDescription else {
            throw AmbiMuxError.couldNotGetAudioStreamDescription
        }
        let hoaFD: CMFormatDescription = try hoaFDState.withLock {
            if let existing = $0 {
                if existing.referenceASBD.isEquivalentStreamFormat(to: asbd) {
                    return existing.hoaFormatDescription
                }
                throw AmbiMuxError.ambisonicsLpcmFormatChangedMidStream
            }
            let channelCount = Int(asbd.mChannelsPerFrame)
            guard AmbisonicsOrder(channelCount: channelCount) != nil else {
                throw AmbiMuxError.invalidChannelCount(count: channelCount)
            }
            let newFD = try copyAudioFormatDescriptionWithHOALayout(
                from: fd, channelCount: channelCount)
            $0 = (referenceASBD: asbd, hoaFormatDescription: newFD)
            return newFD
        }
        return try sampleBufferReplacingFormatDescription(gained, newFormat: hoaFD)
    }

    let fallbackMap: @Sendable (CMSampleBuffer) throws -> CMSampleBuffer = { buf in
        try sampleBufferByApplyingLinearGain(buf, linearGain: linearGain)
    }

    try assetWriter.start()
    assetWriter.startSession(atSourceTime: .zero)
    try videoReader.start()
    try ambisonicsReader.start()
    try fallbackReader?.start()

    let videoFinished = OSAllocatedUnfairLock(initialState: false)
    let ambisonicsFinished = OSAllocatedUnfairLock(initialState: false)
    let fallbackFinished = OSAllocatedUnfairLock(initialState: fallbackWriterInput == nil)

    pump(
        writerInput: videoWriterInput,
        readerOutput: videoReaderOutput,
        queueLabel: "jp.objective-audio.ambimux.attenuate.video",
        qos: .userInitiated,
        finishedFlag: videoFinished
    )
    pump(
        writerInput: ambisonicsWriterInput,
        readerOutput: ambisonicsReaderOutput,
        queueLabel: "jp.objective-audio.ambimux.attenuate.audio.ambisonics",
        qos: .userInitiated,
        finishedFlag: ambisonicsFinished,
        mapSampleBuffer: ambisonicsMap
    )
    if let fallbackWriterInput, let fallbackReaderOutput {
        pump(
            writerInput: fallbackWriterInput,
            readerOutput: fallbackReaderOutput,
            queueLabel: "jp.objective-audio.ambimux.attenuate.audio.fallback",
            qos: .userInitiated,
            finishedFlag: fallbackFinished,
            mapSampleBuffer: fallbackMap
        )
    }

    try await Task {
        while !(videoFinished.withLock { $0 })
            || !(ambisonicsFinished.withLock { $0 })
            || !(fallbackFinished.withLock { $0 })
        {
            try await Task.sleep(for: .milliseconds(10))
        }
    }.value

    await assetWriter.finishWriting()
    if assetWriter.status == .completed {
        return
    }
    let errorMessage = assetWriter.error?.localizedDescription ?? "Unknown error"
    throw AmbiMuxError.outputWritingFailed(message: errorMessage)
}
