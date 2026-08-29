import AVFoundation
import CoreAudioTypes
import CoreMedia
import Foundation
import os

private struct AudioTrackPipeline: Sendable {
    let reader: AVAssetReader
    let readerOutput: AVAssetReaderTrackOutput
    let writerInput: AVAssetWriterInput
}

private struct VideoTrackPipeline: Sendable {
    let reader: AVAssetReader
    let readerOutput: AVAssetReaderTrackOutput
    let writerInput: AVAssetWriterInput
}

private struct FallbackAudioTrackPipeline: Sendable {
    let reader: AVAssetReader
    let readerOutput: AVAssetReaderTrackOutput
    let writerInput: AVAssetWriterInput
}

private func makeFallbackAudioPipelineIfPresent(
    videoAsset: AVURLAsset,
    fallbackTrack audioTrack: AVAssetTrack
) async throws -> FallbackAudioTrackPipeline? {
    let formatDescriptions = try await audioTrack.load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first else {
        return nil
    }

    let fallbackReader = try AVAssetReader(asset: videoAsset)
    let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    fallbackReader.add(audioReaderOutput)

    let audioWriterInput = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: nil,  // パススルー
        sourceFormatHint: formatDescription
    )
    audioWriterInput.expectsMediaDataInRealTime = false

    return FallbackAudioTrackPipeline(
        reader: fallbackReader,
        readerOutput: audioReaderOutput,
        writerInput: audioWriterInput
    )
}

private func makeAmbisonicsAudioPipeline(
    audioAsset: AVURLAsset,
    audioTrack: AVAssetTrack,
    outputAudioFormat: AudioOutputFormat
) async throws -> AudioTrackPipeline {
    let formatDescriptions = try await audioTrack.load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first else {
        throw AmbiMuxError.couldNotRetrieveFormatInformation
    }
    guard let asbdForReader = formatDescription.audioStreamBasicDescription else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }

    let isSourceAPAC = asbdForReader.mFormatID == kAudioFormatAPAC
    // 再エンコード時は Reader で正規 LPCM にデコードし、Writer へ非圧縮サンプルを渡す。APAC ソースはパススルー。
    let needsEncode = !isSourceAPAC

    let channelCount: Int
    let decodeSampleRate: Double
    let decodeASBD: AudioStreamBasicDescription?
    let readerOutputSettings: [String: Any]?
    if needsEncode {
        channelCount = Int(asbdForReader.mChannelsPerFrame)
        guard AmbisonicsOrder(channelCount: channelCount) != nil else {
            throw AmbiMuxError.invalidChannelCount(count: channelCount)
        }
        decodeSampleRate = min(asbdForReader.mSampleRate, 48000)
        decodeASBD = decodeTargetLinearPCMASBD(
            channelCount: channelCount, sampleRate: decodeSampleRate)
        readerOutputSettings = linearPCMReaderOutputSettings(
            channelCount: channelCount, sampleRate: decodeSampleRate)
    } else {
        channelCount = Int(asbdForReader.mChannelsPerFrame)
        decodeSampleRate = asbdForReader.mSampleRate
        decodeASBD = nil
        readerOutputSettings = nil
    }

    let audioAssetReader = try AVAssetReader(asset: audioAsset)
    let audioReaderOutput = AVAssetReaderTrackOutput(
        track: audioTrack, outputSettings: readerOutputSettings)
    audioAssetReader.add(audioReaderOutput)

    // APAC 出力は HOA 付きでエンコード、LPCM 出力はデコードターゲットに合わせた HOA 付き LPCM、APAC ソースはパススルー。
    // HOA レイアウトは append 直前に mapSampleBuffer で付与する。
    let audioInput: AVAssetWriterInput
    if outputAudioFormat == .apac && !isSourceAPAC {
        let writerAudioSettings = try apacWriterOutputSettings(
            channelCount: channelCount, sampleRate: decodeSampleRate)
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerAudioSettings)
    } else if outputAudioFormat == .lpcm && !isSourceAPAC {
        guard let decodeASBD else {
            throw AmbiMuxError.couldNotGetAudioStreamDescription
        }
        guard let ambisonicsOrder = AmbisonicsOrder(channelCount: channelCount) else {
            throw AmbiMuxError.invalidChannelCount(count: channelCount)
        }
        let layoutData = try audioChannelLayoutDataHOAACNSN3D(channelCount: channelCount)
        let writerAudioSettings = linearPCMWriterOutputSettingsHOA(
            asbd: decodeASBD,
            channelCount: ambisonicsOrder.channelCount,
            layoutData: layoutData
        )
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerAudioSettings)
    } else {
        audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
    }
    audioInput.expectsMediaDataInRealTime = false

    return AudioTrackPipeline(
        reader: audioAssetReader,
        readerOutput: audioReaderOutput,
        writerInput: audioInput
    )
}

private func makeVideoPipeline(videoAsset: AVURLAsset) async throws -> VideoTrackPipeline {
    let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
        throw AmbiMuxError.videoTrackNotFound
    }

    let videoAssetReader = try AVAssetReader(asset: videoAsset)
    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    videoAssetReader.add(videoReaderOutput)

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
    videoInput.expectsMediaDataInRealTime = false

    return VideoTrackPipeline(
        reader: videoAssetReader,
        readerOutput: videoReaderOutput,
        writerInput: videoInput
    )
}

func pump(
    writerInput: AVAssetWriterInput,
    readerOutput: AVAssetReaderOutput,
    queueLabel: String,
    qos: DispatchQoS,
    finishedFlag: OSAllocatedUnfairLock<Bool>,
    mapSampleBuffer: (@Sendable (_ buffer: CMSampleBuffer) throws -> CMSampleBuffer)? = nil
) {
    let queue = DispatchQueue(label: queueLabel, qos: qos)

    let writerInputRef = UncheckedSendableRef(writerInput)
    let readerOutputRef = UncheckedSendableRef(readerOutput)
    writerInput.requestMediaDataWhenReady(on: queue) {
        let writerInput = writerInputRef.value
        let readerOutput = readerOutputRef.value

        while writerInput.isReadyForMoreMediaData && !(finishedFlag.withLock { $0 }) {
            if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                do {
                    let toAppend: CMSampleBuffer
                    if let map = mapSampleBuffer {
                        toAppend = try map(sampleBuffer)
                    } else {
                        toAppend = sampleBuffer
                    }
                    guard writerInput.append(toAppend) else {
                        writerInput.markAsFinished()
                        finishedFlag.withLock { $0 = true }
                        return
                    }
                } catch {
                    writerInput.markAsFinished()
                    finishedFlag.withLock { $0 = true }
                    return
                }
            } else {
                writerInput.markAsFinished()
                finishedFlag.withLock { $0 = true }
            }
        }
    }
}

// Process video and audio and output to MOV file
func convertVideoWithAudioToMOV(
    audioPath: String,
    audioMode: AudioInputMode,
    videoPath: String,
    outputPath: String,
    outputAudioFormat: AudioOutputFormat? = nil
) async throws {
    let audioURL = URL(fileURLWithPath: audioPath)
    let videoURL = URL(fileURLWithPath: videoPath)
    let outputURL = URL(fileURLWithPath: outputPath)

    // Create AVURLAsset for video file
    let videoAsset = AVURLAsset(url: videoURL)

    // APAC 入力は常に APAC 出力に固定する。lpcm/embeddedLpcm は指定に従う（デフォルト: .lpcm）
    let effectiveOutputFormat: AudioOutputFormat
    switch audioMode {
    case .lpcm, .embeddedLpcm:
        effectiveOutputFormat = outputAudioFormat ?? .lpcm
    case .apac:
        effectiveOutputFormat = .apac
    }

    // lpcm・embeddedLpcm: 再エンコード時は Reader で正規 LPCM にデコード。append 時に各 CMSampleBuffer の実 ASBD に HOA レイアウトのみ付与
    // apac: パススルー
    let audioAsset: AVURLAsset
    let ambisonicsTrack: AVAssetTrack
    let embeddedScanResult: (ambisonics: AVAssetTrack, fallback: AVAssetTrack?)?

    switch audioMode {
    case .lpcm:
        embeddedScanResult = nil
        let sourceAsset = AVURLAsset(url: audioURL)
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw AmbiMuxError.audioTrackNotFound
        }
        audioAsset = sourceAsset
        ambisonicsTrack = track
    case .embeddedLpcm:
        let scanResult = try await scanVideoAudioTracks(videoAsset: videoAsset)
        embeddedScanResult = (scanResult.ambisonics, scanResult.fallback)
        audioAsset = videoAsset
        ambisonicsTrack = scanResult.ambisonics
    case .apac:
        embeddedScanResult = nil
        let externalAsset = AVURLAsset(url: audioURL)
        let audioTracks = try await externalAsset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw AmbiMuxError.audioTrackNotFound
        }
        audioAsset = externalAsset
        ambisonicsTrack = track
    }

    // Pipelines (refactored for future multiple audio tracks)
    let videoPipeline = try await makeVideoPipeline(videoAsset: videoAsset)
    let ambisonicsAudioPipeline = try await makeAmbisonicsAudioPipeline(
        audioAsset: audioAsset,
        audioTrack: ambisonicsTrack,
        outputAudioFormat: effectiveOutputFormat
    )
    let ambisonicsMapSampleBuffer: (@Sendable (CMSampleBuffer) throws -> CMSampleBuffer)?
    switch audioMode {
    case .lpcm, .embeddedLpcm:
        let hoaFDState = OSAllocatedUnfairLock<
            (referenceASBD: AudioStreamBasicDescription, hoaFormatDescription: CMFormatDescription)?
        >(initialState: nil)
        ambisonicsMapSampleBuffer = { buf in
            guard let fd = buf.formatDescription else {
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
                let newFD = try copyAudioFormatDescriptionWithHOALayout(from: fd, channelCount: channelCount)
                $0 = (referenceASBD: asbd, hoaFormatDescription: newFD)
                return newFD
            }
            return try sampleBufferReplacingFormatDescription(buf, newFormat: hoaFD)
        }
    case .apac:
        ambisonicsMapSampleBuffer = nil
    }
    // 映像ファイルの音声トラックをフォールバック用に抽出（存在する場合）
    // .embeddedLpcm: scanVideoAudioTracks で検出したモノ/ステレオをフォールバックに使用
    // .apac/.lpcm: scanVideoFallbackTrack で検出したモノ/ステレオをフォールバックに使用
    let fallbackAudioPipeline: FallbackAudioTrackPipeline?
    switch audioMode {
    case .embeddedLpcm:
        if let fallbackTrack = embeddedScanResult?.fallback {
            fallbackAudioPipeline = try await makeFallbackAudioPipelineIfPresent(
                videoAsset: videoAsset,
                fallbackTrack: fallbackTrack
            )
        } else {
            fallbackAudioPipeline = nil
        }
    case .apac, .lpcm:
        if let fallbackTrack = try await scanVideoFallbackTrack(videoAsset: videoAsset) {
            fallbackAudioPipeline = try await makeFallbackAudioPipelineIfPresent(
                videoAsset: videoAsset,
                fallbackTrack: fallbackTrack
            )
        } else {
            fallbackAudioPipeline = nil
        }
    }

    // Create AVAssetWriter
    let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    let videoInput = videoPipeline.writerInput
    let ambisonicsAudioInput = ambisonicsAudioPipeline.writerInput
    let fallbackAudioInput = fallbackAudioPipeline?.writerInput

    if assetWriter.canAdd(videoInput) {
        assetWriter.add(videoInput)
    }
    if assetWriter.canAdd(ambisonicsAudioInput) {
        assetWriter.add(ambisonicsAudioInput)
    }
    if let fallbackAudioInput, assetWriter.canAdd(fallbackAudioInput) {
        assetWriter.add(fallbackAudioInput)
    }

    // Configure track metadata for proper fallback behavior
    // The ambisonics track is the primary track, fallback is the alternate
    ambisonicsAudioInput.languageCode = "und"
    ambisonicsAudioInput.extendedLanguageTag = "und"
    ambisonicsAudioInput.marksOutputTrackAsEnabled = true  // Primary track is enabled

    if let fallbackAudioInput {
        fallbackAudioInput.languageCode = "und"
        fallbackAudioInput.extendedLanguageTag = "und"
        // Mark output tracks as enabled true and then false for fallback audio input
        fallbackAudioInput.marksOutputTrackAsEnabled = true
        fallbackAudioInput.marksOutputTrackAsEnabled = false  // Fallback is disabled by default

        // Add track association: ambisonics track has fallback as its alternate
        let associationType = AVAssetTrack.AssociationType.audioFallback.rawValue
        if fallbackAudioInput.canAddTrackAssociation(
            withTrackOf: ambisonicsAudioInput, type: associationType)
        {
            fallbackAudioInput.addTrackAssociation(
                withTrackOf: ambisonicsAudioInput, type: associationType)
        }
    }

    // Start reading and writing
    try assetWriter.start()
    assetWriter.startSession(atSourceTime: .zero)
    try videoPipeline.reader.start()
    try ambisonicsAudioPipeline.reader.start()
    try fallbackAudioPipeline?.reader.start()

    let audioFinished = OSAllocatedUnfairLock(initialState: false)
    let videoFinished = OSAllocatedUnfairLock(initialState: false)
    let fallbackFinished = OSAllocatedUnfairLock(initialState: fallbackAudioPipeline == nil)

    pump(
        writerInput: videoInput,
        readerOutput: videoPipeline.readerOutput,
        queueLabel: "jp.objective-audio.ambimux.video",
        qos: .userInitiated,
        finishedFlag: videoFinished
    )
    pump(
        writerInput: ambisonicsAudioInput,
        readerOutput: ambisonicsAudioPipeline.readerOutput,
        queueLabel: "jp.objective-audio.ambimux.audio.ambisonics",
        qos: .userInitiated,
        finishedFlag: audioFinished,
        mapSampleBuffer: ambisonicsMapSampleBuffer
    )
    if let fallbackAudioPipeline, let fallbackAudioInput {
        pump(
            writerInput: fallbackAudioInput,
            readerOutput: fallbackAudioPipeline.readerOutput,
            queueLabel: "jp.objective-audio.ambimux.audio.fallback",
            qos: .userInitiated,
            finishedFlag: fallbackFinished
        )
    }

    // Wait for async processing using Task
    try await Task {
        // Wait until all processing is complete
        while !(audioFinished.withLock { $0 })
            || !(videoFinished.withLock { $0 })
            || !(fallbackFinished.withLock { $0 })
        {
            try await Task.sleep(for: .milliseconds(10))
        }
    }.value

    // Use async version of finishWriting
    await assetWriter.finishWriting()

    // Check status after writing completes
    if assetWriter.status == .completed {
        print("Conversion completed: \(outputPath)")
    } else {
        let errorMessage = assetWriter.error?.localizedDescription ?? "Unknown error"
        throw AmbiMuxError.outputWritingFailed(message: errorMessage)
    }
}

func exportCompositionPassthrough(
    composition: AVMutableComposition,
    outputURL: URL,
    hasFallbackAudio: Bool
) async throws {
    let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

    let videoTracks = composition.tracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
        throw AmbiMuxError.videoTrackNotFound
    }
    let videoFormatDescriptions = try await videoTrack.load(.formatDescriptions)
    guard let videoFormatDescription = videoFormatDescriptions.first else {
        throw AmbiMuxError.couldNotRetrieveFormatInformation
    }

    let videoReader = try AVAssetReader(asset: composition)
    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    videoReader.add(videoReaderOutput)
    let videoWriterInput = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: nil,
        sourceFormatHint: videoFormatDescription
    )
    videoWriterInput.expectsMediaDataInRealTime = false
    videoWriterInput.transform = try await videoTrack.load(.preferredTransform)
    assetWriter.add(videoWriterInput)

    let audioTracks = composition.tracks(withMediaType: .audio)
    var audioReaders: [AVAssetReader] = []
    var audioPipelines: [(readerOutput: AVAssetReaderTrackOutput, writerInput: AVAssetWriterInput)] = []

    for (index, track) in audioTracks.enumerated() {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            throw AmbiMuxError.couldNotRetrieveFormatInformation
        }

        let audioReader = try AVAssetReader(asset: composition)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        audioReader.add(readerOutput)
        audioReaders.append(audioReader)

        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
        writerInput.expectsMediaDataInRealTime = false
        writerInput.languageCode = "und"
        writerInput.extendedLanguageTag = "und"

        if index == 0 {
            writerInput.marksOutputTrackAsEnabled = true
        } else if hasFallbackAudio && index == 1 {
            writerInput.marksOutputTrackAsEnabled = true
            writerInput.marksOutputTrackAsEnabled = false
        }

        assetWriter.add(writerInput)
        audioPipelines.append((readerOutput, writerInput))
    }

    if hasFallbackAudio, audioPipelines.count >= 2 {
        let ambisonicsInput = audioPipelines[0].writerInput
        let fallbackInput = audioPipelines[1].writerInput
        let associationType = AVAssetTrack.AssociationType.audioFallback.rawValue
        if fallbackInput.canAddTrackAssociation(withTrackOf: ambisonicsInput, type: associationType) {
            fallbackInput.addTrackAssociation(withTrackOf: ambisonicsInput, type: associationType)
        }
    }

    try assetWriter.start()
    assetWriter.startSession(atSourceTime: .zero)
    try videoReader.start()
    for reader in audioReaders {
        try reader.start()
    }

    let videoFinished = OSAllocatedUnfairLock(initialState: false)
    let audioFinishedFlags = audioPipelines.map { _ in OSAllocatedUnfairLock(initialState: false) }

    pump(
        writerInput: videoWriterInput,
        readerOutput: videoReaderOutput,
        queueLabel: "jp.objective-audio.ambimux.join.video",
        qos: .userInitiated,
        finishedFlag: videoFinished
    )

    for (index, pipeline) in audioPipelines.enumerated() {
        pump(
            writerInput: pipeline.writerInput,
            readerOutput: pipeline.readerOutput,
            queueLabel: "jp.objective-audio.ambimux.join.audio.\(index)",
            qos: .userInitiated,
            finishedFlag: audioFinishedFlags[index]
        )
    }

    try await Task {
        while !(videoFinished.withLock { $0 })
            || !audioFinishedFlags.allSatisfy({ $0.withLock { $0 } })
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
