import AVFoundation
import CoreAudioTypes
import CoreMedia
import Foundation
import os

/// HOA ACN SN3D の `AudioChannelLayout` を `AVChannelLayoutKey` 用にシリアライズする。
nonisolated private func audioChannelLayoutDataHOAACNSN3D(channelCount: Int) throws -> Data {
    guard AmbisonicsOrder(channelCount: channelCount) != nil else {
        throw AmbiMuxError.invalidChannelCount(count: channelCount)
    }
    let ambisonicsLayout = AVAudioChannelLayout(
        layoutTag: kAudioChannelLayoutTag_HOA_ACN_SN3D
            | AudioChannelLayoutTag(channelCount)
    )!
    return Data(bytes: ambisonicsLayout.layout, count: MemoryLayout<AudioChannelLayout>.size)
}

/// ASBD・マジッククッキーを維持し、HOA ACN SN3D レイアウトの `CMFormatDescription` を作る。
nonisolated private func copyAudioFormatDescriptionWithHOALayout(
    from formatDescription: CMFormatDescription,
    channelCount: Int
) throws -> CMFormatDescription {
    guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }
    var asbd = asbdPtr.pointee
    let layoutData = try audioChannelLayoutDataHOAACNSN3D(channelCount: channelCount)
    var magicCookieSize: Int = 0
    let magicCookiePtr = CMAudioFormatDescriptionGetMagicCookie(formatDescription, sizeOut: &magicCookieSize)
    var newFormat: CMFormatDescription?
    let err: OSStatus = layoutData.withUnsafeBytes { rawBuf in
        guard let base = rawBuf.baseAddress else { return -1 }
        return CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: layoutData.count,
            layout: base.assumingMemoryBound(to: AudioChannelLayout.self),
            magicCookieSize: magicCookieSize,
            magicCookie: magicCookiePtr.map { UnsafeRawPointer($0) },
            extensions: nil,
            formatDescriptionOut: &newFormat
        )
    }
    guard err == noErr, let newFormat else {
        throw AmbiMuxError.conversionFailed(
            message: "Could not create audio format description with HOA channel layout")
    }
    return newFormat
}

extension AudioStreamBasicDescription {
    /// `mReserved` を除き、ストリーム形式として同一かどうか。
    nonisolated func isEquivalentStreamFormat(to other: AudioStreamBasicDescription) -> Bool {
        mSampleRate == other.mSampleRate
            && mFormatID == other.mFormatID
            && mFormatFlags == other.mFormatFlags
            && mBytesPerPacket == other.mBytesPerPacket
            && mFramesPerPacket == other.mFramesPerPacket
            && mBytesPerFrame == other.mBytesPerFrame
            && mBitsPerChannel == other.mBitsPerChannel
            && mChannelsPerFrame == other.mChannelsPerFrame
    }
}

/// トラック ASBD に合わせた HOA 付き LPCM の `AVAssetWriterInput` 用 `outputSettings`（レートは従来どおり 48k 上限）。
nonisolated private func linearPCMWriterOutputSettingsHOA(
    asbd: AudioStreamBasicDescription,
    channelCount: Int,
    layoutData: Data
) -> [String: Any] {
    let isFloat = (asbd.mFormatFlags & UInt32(kAudioFormatFlagIsFloat)) != 0
    let isBigEndian = (asbd.mFormatFlags & UInt32(kAudioFormatFlagIsBigEndian)) != 0
    let isNonInterleaved = (asbd.mFormatFlags & UInt32(kAudioFormatFlagIsNonInterleaved)) != 0
    let outputRate = min(asbd.mSampleRate, 48000)
    return [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: outputRate,
        AVNumberOfChannelsKey: channelCount,
        AVLinearPCMBitDepthKey: Int(asbd.mBitsPerChannel),
        AVLinearPCMIsFloatKey: isFloat,
        AVLinearPCMIsBigEndianKey: isBigEndian,
        AVLinearPCMIsNonInterleaved: isNonInterleaved,
        AVChannelLayoutKey: layoutData,
    ]
}

/// 音声データはそのまま、`formatDescription` だけ差し替えた `CMSampleBuffer` を返す。
nonisolated private func sampleBufferReplacingFormatDescription(
    _ sampleBuffer: CMSampleBuffer,
    newFormat: CMFormatDescription
) throws -> CMSampleBuffer {
    guard CMSampleBufferGetFormatDescription(sampleBuffer) != nil else {
        return sampleBuffer
    }
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
        return sampleBuffer
    }
    let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

    var timingNeeded: CMItemCount = 0
    var timingStatus = CMSampleBufferGetSampleTimingInfoArray(
        sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingNeeded)
    guard timingStatus == noErr || timingStatus == kCMSampleBufferError_ArrayTooSmall else {
        throw AmbiMuxError.conversionFailed(message: "Could not get sample timing info count")
    }
    var timingInfos = [CMSampleTimingInfo](
        repeating: CMSampleTimingInfo(), count: max(1, Int(timingNeeded)))
    if timingNeeded > 0 {
        timingStatus = timingInfos.withUnsafeMutableBufferPointer { buf in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer, entryCount: timingNeeded, arrayToFill: buf.baseAddress!,
                entriesNeededOut: nil)
        }
        guard timingStatus == noErr else {
            throw AmbiMuxError.conversionFailed(message: "Could not get sample timing info array")
        }
    }

    var sizesNeeded: CMItemCount = 0
    var sizeStatus = CMSampleBufferGetSampleSizeArray(
        sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &sizesNeeded)
    guard sizeStatus == noErr || sizeStatus == kCMSampleBufferError_ArrayTooSmall else {
        throw AmbiMuxError.conversionFailed(message: "Could not get sample size array count")
    }
    var sizes = [Int](repeating: 0, count: max(1, Int(sizesNeeded)))
    if sizesNeeded > 0 {
        sizeStatus = sizes.withUnsafeMutableBufferPointer { buf in
            CMSampleBufferGetSampleSizeArray(
                sampleBuffer, entryCount: sizesNeeded, arrayToFill: buf.baseAddress!,
                entriesNeededOut: nil)
        }
        guard sizeStatus == noErr else {
            throw AmbiMuxError.conversionFailed(message: "Could not get sample size array")
        }
    }

    var newBuffer: CMSampleBuffer?
    let createStatus: OSStatus
    if timingNeeded > 0, sizesNeeded > 0 {
        createStatus = timingInfos.withUnsafeMutableBufferPointer { timingBuf in
            sizes.withUnsafeMutableBufferPointer { sizeBuf in
                CMSampleBufferCreateReady(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: dataBuffer,
                    formatDescription: newFormat,
                    sampleCount: numSamples,
                    sampleTimingEntryCount: timingNeeded,
                    sampleTimingArray: timingBuf.baseAddress!,
                    sampleSizeEntryCount: sizesNeeded,
                    sampleSizeArray: sizeBuf.baseAddress!,
                    sampleBufferOut: &newBuffer
                )
            }
        }
    } else if timingNeeded > 0 {
        createStatus = timingInfos.withUnsafeMutableBufferPointer { timingBuf in
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: dataBuffer,
                formatDescription: newFormat,
                sampleCount: numSamples,
                sampleTimingEntryCount: timingNeeded,
                sampleTimingArray: timingBuf.baseAddress!,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &newBuffer
            )
        }
    } else {
        createStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: dataBuffer,
            formatDescription: newFormat,
            sampleCount: numSamples,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &newBuffer
        )
    }
    guard createStatus == noErr, let newBuffer else {
        throw AmbiMuxError.conversionFailed(message: "Could not recreate sample buffer with new format")
    }
    return newBuffer
}

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

private func makeFallbackAudioPipelineIfPresent(
    videoReader: AVAssetReader,
    fallbackTrack audioTrack: AVAssetTrack
) async throws -> FallbackAudioTrackPipeline? {
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

    let isSourceAPAC =
        formatDescription.audioStreamBasicDescription?.mFormatID == kAudioFormatAPAC

    // デコードはトラックのネイティブ形式のまま（outputSettings: nil）。HOA は append 直前に CMSampleBuffer の実 formatDescription にだけ付与する。
    let audioAssetReader = try AVAssetReader(asset: audioAsset)
    let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    audioAssetReader.add(audioReaderOutput)

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
    videoAssetReader.add(videoReaderOutput)

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
    videoInput.expectsMediaDataInRealTime = false

    return VideoTrackPipeline(
        reader: videoAssetReader,
        readerOutput: videoReaderOutput,
        writerInput: videoInput
    )
}

private func pump(
    writerInput: AVAssetWriterInput,
    readerOutput: AVAssetReaderOutput,
    queueLabel: String,
    qos: DispatchQoS,
    finishedFlag: OSAllocatedUnfairLock<Bool>,
    mapSampleBuffer: ((_ buffer: CMSampleBuffer) throws -> CMSampleBuffer)? = nil
) {
    let queue = DispatchQueue(label: queueLabel, qos: qos)

    let writerInputRef = UncheckedSendableRef(writerInput)
    let readerOutputRef = UncheckedSendableRef(readerOutput)
    let mapRef = UncheckedSendableRef(mapSampleBuffer)
    writerInput.requestMediaDataWhenReady(on: queue) {
        let writerInput = writerInputRef.value
        let readerOutput = readerOutputRef.value
        let mapSampleBuffer = mapRef.value

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
    let ambisonicsMapSampleBuffer: ((CMSampleBuffer) throws -> CMSampleBuffer)?
    switch audioMode {
    case .lpcm, .embeddedLpcm:
        let hoaFDState = OSAllocatedUnfairLock<
            (referenceASBD: AudioStreamBasicDescription, hoaFormatDescription: CMFormatDescription)?
        >(initialState: nil)
        ambisonicsMapSampleBuffer = { buf in
            guard let fd = buf.formatDescription else {
                throw AmbiMuxError.conversionFailed(
                    message: "Ambisonics sample buffer has no format description")
            }
            guard let asbd = fd.audioStreamBasicDescription else {
                throw AmbiMuxError.couldNotGetAudioStreamDescription
            }
            let hoaFD: CMFormatDescription = try hoaFDState.withLock {
                if let existing = $0 {
                    if existing.referenceASBD.isEquivalentStreamFormat(to: asbd) {
                        return existing.hoaFormatDescription
                    }
                    throw AmbiMuxError.conversionFailed(
                        message: "Ambisonics LPCM format changed mid-stream")
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
                videoReader: videoPipeline.reader,
                fallbackTrack: fallbackTrack
            )
        } else {
            fallbackAudioPipeline = nil
        }
    case .apac, .lpcm:
        if let fallbackTrack = try await scanVideoFallbackTrack(videoAsset: videoAsset) {
            fallbackAudioPipeline = try await makeFallbackAudioPipelineIfPresent(
                videoReader: videoPipeline.reader,
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
        throw AmbiMuxError.conversionFailed(message: errorMessage)
    }
}
