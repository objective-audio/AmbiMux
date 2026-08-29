import AVFoundation
import Accelerate
import CoreAudio
import CoreAudioTypes
import CoreMedia
import Foundation

// MARK: - HOA / Ambisonics sample-buffer helpers (used by AudioConverters)

/// HOA ACN SN3D の `AudioChannelLayout` を `AVChannelLayoutKey` 用にシリアライズする。
nonisolated func audioChannelLayoutDataHOAACNSN3D(channelCount: Int) throws -> Data {
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
nonisolated func copyAudioFormatDescriptionWithHOALayout(
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
        throw AmbiMuxError.couldNotCreateAudioFormatDescriptionWithHOALayout
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

/// 再エンコード時の正規デコードターゲット: float32 / interleaved LPCM（レートは 48k 上限）。
nonisolated func decodeTargetLinearPCMASBD(
    channelCount: Int,
    sampleRate: Double
) -> AudioStreamBasicDescription {
    let rate = min(sampleRate, 48000)
    let bytesPerFrame = UInt32(MemoryLayout<Float32>.size * channelCount)
    return AudioStreamBasicDescription(
        mSampleRate: rate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
            | kAudioFormatFlagsNativeEndian,
        mBytesPerPacket: bytesPerFrame,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: UInt32(channelCount),
        mBitsPerChannel: 32,
        mReserved: 0
    )
}

/// mux / attenuate 共通の APAC `AVAssetWriterInput` 用 `outputSettings`。
nonisolated func apacWriterOutputSettings(
    channelCount: Int,
    sampleRate: Double
) throws -> [String: Any] {
    guard let ambisonicsOrder = AmbisonicsOrder(channelCount: channelCount) else {
        throw AmbiMuxError.invalidChannelCount(count: channelCount)
    }
    let layoutData = try audioChannelLayoutDataHOAACNSN3D(channelCount: channelCount)
    return [
        AVFormatIDKey: kAudioFormatAPAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: ambisonicsOrder.channelCount,
        AVChannelLayoutKey: layoutData,
        AVEncoderBitRateKey: 384000,
        AVEncoderContentSourceKey: AVAudioContentSource.appleAV_Spatial_Offline.rawValue,
        AVEncoderDynamicRangeControlConfigurationKey: AVAudioDynamicRangeControlConfiguration
            .movie.rawValue,
        AVEncoderASPFrequencyKey: 75,
    ]
}

/// フォールバック再エンコード用の float32 interleaved LPCM（HOA レイアウトなし）。
nonisolated func linearPCMWriterOutputSettings(
    channelCount: Int,
    sampleRate: Double
) -> [String: Any] {
    let rate = min(sampleRate, 48000)
    return [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: rate,
        AVNumberOfChannelsKey: channelCount,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
}

/// 再エンコード時の `AVAssetReaderTrackOutput` 用 LPCM `outputSettings`（HOA レイアウトは付けない）。
nonisolated func linearPCMReaderOutputSettings(
    channelCount: Int,
    sampleRate: Double
) -> [String: Any] {
    let asbd = decodeTargetLinearPCMASBD(channelCount: channelCount, sampleRate: sampleRate)
    return [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: asbd.mSampleRate,
        AVNumberOfChannelsKey: channelCount,
        AVLinearPCMBitDepthKey: Int(asbd.mBitsPerChannel),
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
}

/// トラック ASBD に合わせた HOA 付き LPCM の `AVAssetWriterInput` 用 `outputSettings`（レートは従来どおり 48k 上限）。
nonisolated func linearPCMWriterOutputSettingsHOA(
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

nonisolated func requireAPACAmbisonicsTrack(in asset: AVURLAsset) async throws -> AVAssetTrack {
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
        throw AmbiMuxError.noAudioTracksFound
    }

    var ambisonicsTrack: AVAssetTrack?
    var ambisonicsIsAPAC = false
    var apacInvalidChannelCount: Int?

    for track in audioTracks {
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let asbd = formatDescription.audioStreamBasicDescription
        else {
            continue
        }
        let channels = Int(asbd.mChannelsPerFrame)
        let isAPAC = asbd.mFormatID == kAudioFormatAPAC

        if AmbisonicsOrder(channelCount: channels) != nil {
            if ambisonicsTrack == nil {
                ambisonicsTrack = track
                ambisonicsIsAPAC = isAPAC
            }
        } else if isAPAC {
            apacInvalidChannelCount = channels
        }
    }

    if let ambisonicsTrack {
        guard ambisonicsIsAPAC else {
            throw AmbiMuxError.expectedAPACAudio
        }
        return ambisonicsTrack
    }
    if let count = apacInvalidChannelCount {
        throw AmbiMuxError.invalidChannelCount(count: count)
    }
    throw AmbiMuxError.noAmbisonicsTrackFound
}

/// Interleaved float32 の PCM を `CMSampleBuffer` からコピーする。
nonisolated func copyInterleavedFloat32(from sampleBuffer: CMSampleBuffer) throws -> [Float] {
    guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
        let asbd = format.audioStreamBasicDescription
    else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }
    let isFloat = (asbd.mFormatFlags & UInt32(kAudioFormatFlagIsFloat)) != 0
    guard isFloat, asbd.mBitsPerChannel == 32 else {
        throw AmbiMuxError.couldNotAccessAudioSampleData
    }

    let channelCount = Int(asbd.mChannelsPerFrame)
    let isNonInterleaved = (asbd.mFormatFlags & UInt32(kAudioFormatFlagIsNonInterleaved)) != 0
    let bufferCount = isNonInterleaved ? max(channelCount, 1) : 1
    let bufferListSize = AudioBufferList.sizeInBytes(maximumBuffers: bufferCount)

    let ablRaw = UnsafeMutableRawPointer.allocate(
        byteCount: bufferListSize, alignment: MemoryLayout<AudioBuffer>.alignment)
    defer { ablRaw.deallocate() }
    ablRaw.initializeMemory(as: UInt8.self, repeating: 0, count: bufferListSize)
    let ablPtr = ablRaw.assumingMemoryBound(to: AudioBufferList.self)

    var blockBuffer: CMBlockBuffer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer,
        bufferListSizeNeededOut: nil,
        bufferListOut: ablPtr,
        bufferListSize: bufferListSize,
        blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
        blockBufferOut: &blockBuffer
    )
    guard status == noErr else {
        throw AmbiMuxError.couldNotAccessAudioSampleData
    }

    let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
    if isNonInterleaved {
        guard abl.count == channelCount, let first = abl.first else {
            throw AmbiMuxError.couldNotAccessAudioSampleData
        }
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        var interleaved = [Float](repeating: 0, count: frames * channelCount)
        for channel in 0..<channelCount {
            guard let data = abl[channel].mData else {
                throw AmbiMuxError.couldNotAccessAudioSampleData
            }
            let src = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                interleaved[frame * channelCount + channel] = src[frame]
            }
        }
        return interleaved
    }

    guard let data = abl.first?.mData else {
        throw AmbiMuxError.couldNotAccessAudioSampleData
    }
    let count = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
    if count == 0 {
        return []
    }
    let src = data.assumingMemoryBound(to: Float.self)
    return Array(UnsafeBufferPointer(start: src, count: count))
}

/// Interleaved float32 PCM に線形ゲインをかけ、同じタイミングの新しい `CMSampleBuffer` を返す。
nonisolated func sampleBufferByApplyingLinearGain(
    _ sampleBuffer: CMSampleBuffer,
    linearGain: Float
) throws -> CMSampleBuffer {
    if linearGain == 1 {
        return sampleBuffer
    }
    guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        throw AmbiMuxError.ambisonicsSampleBufferMissingFormatDescription
    }
    guard let asbd = format.audioStreamBasicDescription else {
        throw AmbiMuxError.couldNotGetAudioStreamDescription
    }
    let isFloat = (asbd.mFormatFlags & UInt32(kAudioFormatFlagIsFloat)) != 0
    guard isFloat, asbd.mBitsPerChannel == 32 else {
        throw AmbiMuxError.couldNotAccessAudioSampleData
    }

    var samples = try copyInterleavedFloat32(from: sampleBuffer)
    if samples.isEmpty {
        return sampleBuffer
    }
    var gain = linearGain
    samples.withUnsafeMutableBufferPointer { buf in
        guard let base = buf.baseAddress, !buf.isEmpty else { return }
        vDSP_vsmul(base, 1, &gain, base, 1, vDSP_Length(buf.count))
    }

    let length = samples.count * MemoryLayout<Float>.size
    var newBlock: CMBlockBuffer?
    var status = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: length,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: length,
        flags: 0,
        blockBufferOut: &newBlock
    )
    guard status == kCMBlockBufferNoErr, let newBlock else {
        throw AmbiMuxError.couldNotAccessAudioSampleData
    }
    status = samples.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return -1 }
        return CMBlockBufferReplaceDataBytes(
            with: base,
            blockBuffer: newBlock,
            offsetIntoDestination: 0,
            dataLength: length
        )
    }
    guard status == kCMBlockBufferNoErr else {
        throw AmbiMuxError.couldNotAccessAudioSampleData
    }

    return try sampleBufferReplacingFormatDescription(
        sampleBuffer, newFormat: format, newDataBuffer: newBlock)
}

/// 音声データはそのまま、`formatDescription` だけ差し替えた `CMSampleBuffer` を返す。
/// `newDataBuffer` を渡すとデータも差し替える。
nonisolated func sampleBufferReplacingFormatDescription(
    _ sampleBuffer: CMSampleBuffer,
    newFormat: CMFormatDescription,
    newDataBuffer: CMBlockBuffer? = nil
) throws -> CMSampleBuffer {
    guard CMSampleBufferGetFormatDescription(sampleBuffer) != nil else {
        return sampleBuffer
    }
    let dataBuffer: CMBlockBuffer
    if let newDataBuffer {
        dataBuffer = newDataBuffer
    } else if let existing = CMSampleBufferGetDataBuffer(sampleBuffer) {
        dataBuffer = existing
    } else {
        return sampleBuffer
    }
    let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

    var timingNeeded: CMItemCount = 0
    var timingStatus = CMSampleBufferGetSampleTimingInfoArray(
        sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingNeeded)
    guard timingStatus == noErr || timingStatus == kCMSampleBufferError_ArrayTooSmall else {
        throw AmbiMuxError.couldNotGetSampleTimingInfoCount
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
            throw AmbiMuxError.couldNotGetSampleTimingInfoArray
        }
    }

    var sizesNeeded: CMItemCount = 0
    var sizeStatus = CMSampleBufferGetSampleSizeArray(
        sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &sizesNeeded)
    guard sizeStatus == noErr || sizeStatus == kCMSampleBufferError_ArrayTooSmall else {
        throw AmbiMuxError.couldNotGetSampleSizeArrayCount
    }
    var sizes = [Int](repeating: 0, count: max(1, Int(sizesNeeded)))
    if sizesNeeded > 0 {
        sizeStatus = sizes.withUnsafeMutableBufferPointer { buf in
            CMSampleBufferGetSampleSizeArray(
                sampleBuffer, entryCount: sizesNeeded, arrayToFill: buf.baseAddress!,
                entriesNeededOut: nil)
        }
        guard sizeStatus == noErr else {
            throw AmbiMuxError.couldNotGetSampleSizeArray
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
        throw AmbiMuxError.couldNotRecreateSampleBufferWithNewFormat
    }
    return newBuffer
}

// MARK: - Output path helpers

// Generate unique filename in specified directory with given filename
nonisolated func generateUniqueFileName(
    directory: String, fileName: String, extension fileExtension: String
) -> String {
    let directoryURL = URL(fileURLWithPath: directory)

    var counter = 1
    var newFileName = "\(fileName).\(fileExtension)"
    var newPath = directoryURL.appendingPathComponent(newFileName).path

    while FileManager.default.fileExists(atPath: newPath) {
        newFileName = "\(fileName)_\(counter).\(fileExtension)"
        newPath = directoryURL.appendingPathComponent(newFileName).path
        counter += 1
    }

    return newPath
}

// Generate output file path
nonisolated func generateOutputPath(outputPath: String?, videoPath: String) -> String {
    let sourcePath = outputPath ?? videoPath
    let url = URL(fileURLWithPath: sourcePath)

    let directory = url.deletingLastPathComponent().path
    let fileName = url.deletingPathExtension().lastPathComponent
    let fileExtension = "mov"  // Always output in MOV format

    return generateUniqueFileName(
        directory: directory, fileName: fileName, extension: fileExtension)
}
