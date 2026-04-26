@preconcurrency import AVFoundation
import CoreAudioTypes
import CoreMedia
import Foundation

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

/// HOA 付け替えの状態。アンビソニクス転送タスク単体からのみ参照する。
private final class HOAFDMapper: @unchecked Sendable {
    /// アンビソニクス転送タスク1本のみが参照する（`transferTrackSamples` 内）。
    nonisolated(unsafe) private var state:
        (referenceASBD: AudioStreamBasicDescription, hoaFormatDescription: CMFormatDescription)?

    nonisolated func map(_ buf: CMSampleBuffer) throws -> CMSampleBuffer {
        // マーカー等、format なしのサンプルは HOA 付け替えなしでそのまま通す。
        guard let fd = buf.formatDescription else {
            return buf
        }
        guard let asbd = fd.audioStreamBasicDescription else {
            throw AmbiMuxError.couldNotGetAudioStreamDescription
        }
        let hoaFD: CMFormatDescription
        if let existing = state {
            if existing.referenceASBD.isEquivalentStreamFormat(to: asbd) {
                hoaFD = existing.hoaFormatDescription
            } else {
                throw AmbiMuxError.ambisonicsLpcmFormatChangedMidStream
            }
        } else {
            let channelCount = Int(asbd.mChannelsPerFrame)
            guard AmbisonicsOrder(channelCount: channelCount) != nil else {
                throw AmbiMuxError.invalidChannelCount(count: channelCount)
            }
            let newFD = try copyAudioFormatDescriptionWithHOALayout(from: fd, channelCount: channelCount)
            state = (referenceASBD: asbd, hoaFormatDescription: newFD)
            hoaFD = newFD
        }
        return try sampleBufferReplacingFormatDescription(buf, newFormat: hoaFD)
    }
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

    // デコードはトラックのネイティブ形式のまま（outputSettings: nil）。HOA は append 直前に CMSampleBuffer の実 formatDescription にだけ付与する。
    let audioAssetReader = try AVAssetReader(asset: audioAsset)
    let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)

    // lpcm/embeddedLpcm: MOV 書き込み時に CMSampleBuffer を実 ASBD のまま HOA に差し替え。APAC 出力は HOA 付きでエンコード、LPCM 出力はデコード ASBD に合わせた HOA 付き LPCM、それ以外はパススルー。
    let audioInput: AVAssetWriterInput
    if outputAudioFormat == .apac && !isSourceAPAC {
        let channelCount = Int(asbdForReader.mChannelsPerFrame)
        guard let ambisonicsOrder = AmbisonicsOrder(channelCount: channelCount) else {
            throw AmbiMuxError.invalidChannelCount(count: channelCount)
        }
        let layoutData = try audioChannelLayoutDataHOAACNSN3D(channelCount: channelCount)
        let writerAudioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAPAC,
            AVSampleRateKey: min(asbdForReader.mSampleRate, 48000),
            AVNumberOfChannelsKey: ambisonicsOrder.channelCount,
            AVChannelLayoutKey: layoutData,
            AVEncoderBitRateKey: 384000,
            AVEncoderContentSourceKey: AVAudioContentSource.appleAV_Spatial_Offline.rawValue,
            AVEncoderDynamicRangeControlConfigurationKey: AVAudioDynamicRangeControlConfiguration
                .movie.rawValue,
            AVEncoderASPFrequencyKey: 75,
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerAudioSettings)
    } else if outputAudioFormat == .lpcm && !isSourceAPAC {
        let channelCount = Int(asbdForReader.mChannelsPerFrame)
        guard let ambisonicsOrder = AmbisonicsOrder(channelCount: channelCount) else {
            throw AmbiMuxError.invalidChannelCount(count: channelCount)
        }
        let layoutData = try audioChannelLayoutDataHOAACNSN3D(channelCount: channelCount)
        let writerAudioSettings = linearPCMWriterOutputSettingsHOA(
            asbd: asbdForReader,
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

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
    videoInput.expectsMediaDataInRealTime = false

    return VideoTrackPipeline(
        reader: videoAssetReader,
        readerOutput: videoReaderOutput,
        writerInput: videoInput
    )
}

private typealias ReadySampleProvider = AVAssetReaderOutput.Provider<
    CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
>

nonisolated private func mapReadySampleBuffer(
    _ ready: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>,
    mapSampleBuffer: (CMSampleBuffer) throws -> CMSampleBuffer
) throws -> CMReadySampleBuffer<CMSampleBuffer.DynamicContent> {
    try ready.withUnsafeSampleBuffer { sampleBuffer in
        // `mapSampleBuffer` はこのタスク専用。`CMReadySampleBuffer` が所有権を引き取るまでの一時的な橋渡し。
        nonisolated(unsafe) let mapped = try mapSampleBuffer(sampleBuffer)
        return CMReadySampleBuffer(unsafeBuffer: mapped)
    }
}

/// `outputProvider` のサンプルを `inputReceiver` に転送する。各トラックごとに1タスクで呼ぶ。
nonisolated private func transferTrackSamples(
    provider: ReadySampleProvider,
    receiver: AVAssetWriterInput.SampleBufferReceiver,
    mapSampleBuffer: ((CMSampleBuffer) throws -> CMSampleBuffer)?
) async throws {
    do {
        while true {
            guard let ready = try await provider.next() else {
                receiver.finish()
                return
            }
            let toAppend: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
            if let mapSampleBuffer {
                toAppend = try mapReadySampleBuffer(ready, mapSampleBuffer: mapSampleBuffer)
            } else {
                toAppend = ready
            }
            try await receiver.append(toAppend)
        }
    } catch {
        receiver.finish()
        throw error
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

    // lpcm・embeddedLpcm: デコードはネイティブ形式のまま。append 時に各 CMSampleBuffer の実 ASBD に HOA レイアウトのみ付与
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
        let hoaMapper = HOAFDMapper()
        ambisonicsMapSampleBuffer = { buf in
            try hoaMapper.map(buf)
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

    // `outputProvider` は読み取り開始前、`inputReceiver` は書き込み開始前に取得する（内部で入出力の登録・設定を行う）。
    let videoProvider = videoPipeline.reader.outputProvider(for: videoPipeline.readerOutput)
    let ambisonicsProvider = ambisonicsAudioPipeline.reader.outputProvider(
        for: ambisonicsAudioPipeline.readerOutput)
    let fallbackProvider: ReadySampleProvider?
    if let fallbackAudioPipeline {
        fallbackProvider = videoPipeline.reader.outputProvider(for: fallbackAudioPipeline.readerOutput)
    } else {
        fallbackProvider = nil
    }

    let videoReceiver = assetWriter.inputReceiver(for: videoInput)
    let ambisonicsReceiver = assetWriter.inputReceiver(for: ambisonicsAudioInput)
    let fallbackReceiver: AVAssetWriterInput.SampleBufferReceiver?
    if let fallbackAudioInput {
        fallbackReceiver = assetWriter.inputReceiver(for: fallbackAudioInput)
    } else {
        fallbackReceiver = nil
    }

    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: .zero)
    videoPipeline.reader.startReading()
    ambisonicsAudioPipeline.reader.startReading()
    fallbackAudioPipeline?.reader.startReading()

    do {
        try await withThrowingTaskGroup { group in
            group.addTask {
                try await transferTrackSamples(
                    provider: videoProvider,
                    receiver: videoReceiver,
                    mapSampleBuffer: nil
                )
            }
            group.addTask {
                try await transferTrackSamples(
                    provider: ambisonicsProvider,
                    receiver: ambisonicsReceiver,
                    mapSampleBuffer: ambisonicsMapSampleBuffer
                )
            }
            if let fallbackProvider, let fallbackReceiver {
                group.addTask {
                    try await transferTrackSamples(
                        provider: fallbackProvider,
                        receiver: fallbackReceiver,
                        mapSampleBuffer: nil
                    )
                }
            }
            for try await _ in group {}
        }
    } catch {
        videoPipeline.reader.cancelReading()
        ambisonicsAudioPipeline.reader.cancelReading()
        fallbackAudioPipeline?.reader.cancelReading()
        assetWriter.cancelWriting()
        throw error
    }

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
