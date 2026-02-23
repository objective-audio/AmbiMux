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
    let readerOutput: AVAssetReaderTrackOutput
    let writerInput: AVAssetWriterInput
}

@MainActor
private func makeFallbackAudioPipelineIfPresent(
    videoAsset: AVURLAsset,
    videoReader: AVAssetReader
) async throws -> FallbackAudioTrackPipeline? {
    let audioTracks = try await videoAsset.loadTracks(withMediaType: .audio)
    guard let audioTrack = audioTracks.first else {
        return nil  // 音声トラックがなければnilを返す
    }

    let formatDescriptions = try await audioTrack.load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first else {
        return nil
    }

    let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    videoReader.add(audioReaderOutput)

    let audioWriterInput = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: nil,  // パススルー
        sourceFormatHint: formatDescription
    )
    audioWriterInput.expectsMediaDataInRealTime = false

    return FallbackAudioTrackPipeline(
        readerOutput: audioReaderOutput,
        writerInput: audioWriterInput
    )
}

@MainActor
private func makeAmbisonicsAudioPipeline(
    audioAsset: AVURLAsset,
    outputAudioFormat: AudioOutputFormat
) async throws -> AudioTrackPipeline {
    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
    guard let audioTrack = audioTracks.first else {
        throw AmbiMuxError.audioTrackNotFound
    }

    let formatDescriptions = try await audioTrack.load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first else {
        throw AmbiMuxError.couldNotRetrieveFormatInformation
    }

    let audioAssetReader = try AVAssetReader(asset: audioAsset)
    let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    audioAssetReader.add(audioReaderOutput)

    // ソースが LPCM（temp CAF 経由）かつ APAC 出力を要求された場合のみエンコード設定を適用する。
    // それ以外はパススルー（LPCM→LPCM / APAC→APAC）。
    let audioInput: AVAssetWriterInput
    let isSourceAPAC =
        formatDescription.audioStreamBasicDescription?.mFormatID == kAudioFormatAPAC
    if outputAudioFormat == .apac && !isSourceAPAC {
        guard let asbd = formatDescription.audioStreamBasicDescription else {
            throw AmbiMuxError.couldNotGetAudioStreamDescription
        }
        let channelCount = Int(asbd.mChannelsPerFrame)
        guard let ambisonicsOrder = AmbisonicsOrder(channelCount: channelCount) else {
            throw AmbiMuxError.invalidChannelCount(count: channelCount)
        }
        let ambisonicsLayout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_HOA_ACN_SN3D
                | AudioChannelLayoutTag(ambisonicsOrder.channelCount)
        )!
        let layoutData = Data(
            bytes: ambisonicsLayout.layout, count: MemoryLayout<AudioChannelLayout>.size)
        let writerAudioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAPAC,
            AVSampleRateKey: min(asbd.mSampleRate, 48000),
            AVNumberOfChannelsKey: ambisonicsOrder.channelCount,
            AVChannelLayoutKey: layoutData,
            AVEncoderBitRateKey: 384000,
            AVEncoderContentSourceKey: AVAudioContentSource.appleAV_Spatial_Offline.rawValue,
            AVEncoderDynamicRangeControlConfigurationKey: AVAudioDynamicRangeControlConfiguration
                .movie.rawValue,
            AVEncoderASPFrequencyKey: 75,
        ]
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

@MainActor
private func extractAudioToTempCAF(audioAsset: AVURLAsset, outputDirectory: URL) async throws -> URL {
    let tempURL = outputDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("caf")

    let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
    guard let audioTrack = audioTracks.first else {
        throw AmbiMuxError.audioTrackNotFound
    }

    let formatDescriptions = try await audioTrack.load(.formatDescriptions)
    guard let formatDescription = formatDescriptions.first else {
        throw AmbiMuxError.couldNotRetrieveFormatInformation
    }
    guard let asbd = formatDescription.audioStreamBasicDescription else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }

    let channelCount = Int(asbd.mChannelsPerFrame)
    guard let ambisonicsOrder = AmbisonicsOrder(channelCount: channelCount) else {
        throw AmbiMuxError.invalidChannelCount(count: channelCount)
    }
    let ambisonicsLayout = AVAudioChannelLayout(
        layoutTag: kAudioChannelLayoutTag_HOA_ACN_SN3D
            | AudioChannelLayoutTag(ambisonicsOrder.channelCount)
    )!
    let layoutData = Data(
        bytes: ambisonicsLayout.layout, count: MemoryLayout<AudioChannelLayout>.size)

    let sampleRate = min(asbd.mSampleRate, 48000.0)

    // LPCM ソース: AVChannelLayoutKey を指定せずチャンネルマトリクス変換を回避する。
    // APAC ソース: AVChannelLayoutKey を指定してデコード出力レイアウトを明示する。
    let isSourceAPAC = asbd.mFormatID == kAudioFormatAPAC
    var readerOutputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channelCount,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    // TODO: 削除しても問題ないか検証する
    if isSourceAPAC {
        readerOutputSettings[AVChannelLayoutKey] = layoutData
    }

    // Writer は HOA_ACN_SN3D でタグ付けする（LPCM writer は PCM データを変換しない）。
    // これにより後段の APAC エンコーダーがレイアウト変換なしで HOA として処理できる。
    let writerOutputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channelCount,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
        AVChannelLayoutKey: layoutData,
    ]

    let cafReader = try AVAssetReader(asset: audioAsset)
    let cafReaderOutput = AVAssetReaderTrackOutput(
        track: audioTrack, outputSettings: readerOutputSettings)
    cafReader.add(cafReaderOutput)

    let cafWriter = try AVAssetWriter(outputURL: tempURL, fileType: .caf)
    let cafWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerOutputSettings)
    cafWriterInput.expectsMediaDataInRealTime = false
    cafWriter.add(cafWriterInput)

    cafWriter.startWriting()
    cafWriter.startSession(atSourceTime: .zero)
    cafReader.startReading()

    let cafFinished = OSAllocatedUnfairLock(initialState: false)
    pump(
        writerInput: cafWriterInput,
        readerOutput: cafReaderOutput,
        queueLabel: "jp.objective-audio.ambimux.audio.tempcaf",
        qos: .userInitiated,
        finishedFlag: cafFinished
    )

    try await Task {
        while !(cafFinished.withLock { $0 }) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }.value

    await cafWriter.finishWriting()

    guard cafWriter.status == .completed else {
        let message = cafWriter.error?.localizedDescription ?? "Unknown error"
        throw AmbiMuxError.conversionFailed(message: message)
    }

    return tempURL
}

@MainActor
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

@MainActor
private func pump(
    writerInput: AVAssetWriterInput,
    readerOutput: AVAssetReaderOutput,
    queueLabel: String,
    qos: DispatchQoS,
    finishedFlag: OSAllocatedUnfairLock<Bool>
) {
    let queue = DispatchQueue(label: queueLabel, qos: qos)

    let writerInputRef = UncheckedSendableRef(writerInput)
    let readerOutputRef = UncheckedSendableRef(readerOutput)
    writerInput.requestMediaDataWhenReady(on: queue) {
        let writerInput = writerInputRef.value
        let readerOutput = readerOutputRef.value

        while writerInput.isReadyForMoreMediaData && !(finishedFlag.withLock { $0 }) {
            if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                writerInput.append(sampleBuffer)
            } else {
                writerInput.markAsFinished()
                finishedFlag.withLock { $0 = true }
            }
        }
    }
}

// Process video and audio and output to MOV file
@MainActor
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
    let outputDirectory = outputURL.deletingLastPathComponent()

    // Create AVURLAsset for video file
    let videoAsset = AVURLAsset(url: videoURL)

    // 実効出力フォーマット: 未指定の場合は入力に合わせる
    let effectiveOutputFormat: AudioOutputFormat
    if let outputAudioFormat {
        effectiveOutputFormat = outputAudioFormat
    } else {
        switch audioMode {
        case .lpcm, .embeddedLpcm:
            effectiveOutputFormat = .lpcm
        case .apac:
            effectiveOutputFormat = .apac
        }
    }

    // lpcm・embeddedLpcm: 常に temp CAF 経由でチャンネルマトリクス変換を回避する
    // apac → lpcm: temp CAF 経由で APAC をデコードする
    // apac → apac: パススルー
    var tempCAFURL: URL?
    let audioAsset: AVURLAsset
    switch (audioMode, effectiveOutputFormat) {
    case (.lpcm, _), (.embeddedLpcm, _):
        let sourceAsset = audioMode == .embeddedLpcm
            ? videoAsset
            : AVURLAsset(url: audioURL)
        let tempURL = try await extractAudioToTempCAF(
            audioAsset: sourceAsset, outputDirectory: outputDirectory)
        tempCAFURL = tempURL
        audioAsset = AVURLAsset(url: tempURL)
    case (.apac, .lpcm):
        let tempURL = try await extractAudioToTempCAF(
            audioAsset: AVURLAsset(url: audioURL), outputDirectory: outputDirectory)
        tempCAFURL = tempURL
        audioAsset = AVURLAsset(url: tempURL)
    case (.apac, .apac):
        audioAsset = AVURLAsset(url: audioURL)
    }
    defer { tempCAFURL.map { try? FileManager.default.removeItem(at: $0) } }

    // Pipelines (refactored for future multiple audio tracks)
    let videoPipeline = try await makeVideoPipeline(videoAsset: videoAsset)
    let ambisonicsAudioPipeline = try await makeAmbisonicsAudioPipeline(
        audioAsset: audioAsset,
        outputAudioFormat: effectiveOutputFormat
    )
    // 映像ファイルの音声トラックをフォールバック用に抽出（存在する場合）
    // .embeddedLpcm の場合は映像内オーディオをAmbisonicsトラックとして使用しているため、フォールバックは追加しない
    // ビデオと同じreaderを使用する
    let fallbackAudioPipeline: FallbackAudioTrackPipeline?
    switch audioMode {
    case .embeddedLpcm:
        fallbackAudioPipeline = nil
    case .apac, .lpcm:
        fallbackAudioPipeline = try await makeFallbackAudioPipelineIfPresent(
            videoAsset: videoAsset,
            videoReader: videoPipeline.reader
        )
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
    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: .zero)
    videoPipeline.reader.startReading()
    ambisonicsAudioPipeline.reader.startReading()

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
        finishedFlag: audioFinished
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
        throw AmbiMuxError.conversionFailed(message: errorMessage)
    }
}
