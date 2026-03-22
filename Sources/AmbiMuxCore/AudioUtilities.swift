import AVFoundation
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

/// 音声データはそのまま、`formatDescription` だけ差し替えた `CMSampleBuffer` を返す。
nonisolated func sampleBufferReplacingFormatDescription(
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
