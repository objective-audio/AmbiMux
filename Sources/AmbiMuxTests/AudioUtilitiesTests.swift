import AVFoundation
import CoreAudioTypes
import CoreMedia
import Foundation
import Testing

@testable import AmbiMuxCore

struct AudioUtilitiesTests {

    // MARK: - Helpers (CMFormatDescription / ASBD)

    /// Interleaved float LPCM 48kHz 4ch — layoutなしの `CMAudioFormatDescription`。
    private func makeInterleavedFloat4chFormatDescription() throws -> CMFormatDescription {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: 16,
            mFramesPerPacket: 1,
            mBytesPerFrame: 16,
            mChannelsPerFrame: 4,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )
        try #require(status == noErr)
        return try #require(format)
    }

    /// 音声 ASBD を返さない `CMFormatDescription`（映像用）。
    private func makeH264VideoFormatDescription() throws -> CMFormatDescription {
        var videoFormat: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: 1920,
            height: 1080,
            extensions: nil,
            formatDescriptionOut: &videoFormat
        )
        try #require(status == noErr)
        return try #require(videoFormat)
    }

    private func createTempDirectory() throws -> URL {
        // Generate unique directory name for each test
        let uniqueId = UUID().uuidString
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AmbiMuxTest_\(uniqueId)")
        // Remove existing directory
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    @Test func testGenerateUniqueFileName() throws {
        let tempDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Generate first filename
        let firstPath = generateUniqueFileName(
            directory: tempDir.path,
            fileName: "test",
            extension: "mov"
        )

        // Verify result (no duplicate, so original filename)
        #expect(firstPath == tempDir.appendingPathComponent("test.mov").path)
    }

    @Test func testGenerateUniqueFileNameWhenDuplicate() throws {
        let tempDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Prepare existing files (test.mov and test_1.mov exist)
        let originalPath = tempDir.appendingPathComponent("test.mov").path
        let duplicatePath1 = tempDir.appendingPathComponent("test_1.mov").path
        FileManager.default.createFile(atPath: originalPath, contents: Data(), attributes: nil)
        FileManager.default.createFile(atPath: duplicatePath1, contents: Data(), attributes: nil)

        // When duplicate exists, path with sequential number is returned
        let uniquePath = generateUniqueFileName(
            directory: tempDir.path,
            fileName: "test",
            extension: "mov"
        )

        let expected = tempDir.appendingPathComponent("test_2.mov").path
        #expect(uniquePath == expected)
    }

    @Test func testGenerateOutputPathWithCustomPath() throws {
        let tempDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let customOutputPath = tempDir.appendingPathComponent("custom_output.mov").path
        let videoPath = tempDir.appendingPathComponent("input.mov").path

        // Specify custom output path
        let resultPath = generateOutputPath(
            outputPath: customOutputPath,
            videoPath: videoPath
        )

        // Verify result
        #expect(resultPath == customOutputPath)
    }

    @Test func testGenerateOutputPathWithDefaultPath() throws {
        let tempDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let videoPath = tempDir.appendingPathComponent("input.mov").path

        // Default output path (outputPath = nil)
        let resultPath = generateOutputPath(
            outputPath: nil,
            videoPath: videoPath
        )

        // Verify result (same name as video file)
        #expect(resultPath == tempDir.appendingPathComponent("input.mov").path)
    }

    @Test func testGenerateOutputPathWithDifferentExtensions() throws {
        let tempDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let videoPath = tempDir.appendingPathComponent("input.mp4").path

        // Default output path (video file extension is .mp4)
        let resultPath = generateOutputPath(
            outputPath: nil,
            videoPath: videoPath
        )

        // Verify result (converted to .mov)
        #expect(resultPath == tempDir.appendingPathComponent("input.mov").path)
    }

    @Test func testGenerateOutputPathWithCustomExtension() throws {
        let tempDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let customOutputPath = tempDir.appendingPathComponent("custom_output.mp4").path
        let videoPath = tempDir.appendingPathComponent("input.mov").path

        // Specify custom output path (extension is .mp4)
        let resultPath = generateOutputPath(
            outputPath: customOutputPath,
            videoPath: videoPath
        )

        // Verify result (extension is forcibly changed to .mov)
        let expectedPath = tempDir.appendingPathComponent("custom_output.mov").path
        #expect(resultPath == expectedPath)
    }

    // MARK: - audioChannelLayoutDataHOAACNSN3D

    @Test(
        "audioChannelLayoutDataHOAACNSN3D succeeds for Ambisonics channel counts",
        arguments: [4, 9, 16]
    )
    func testAudioChannelLayoutDataHOAACNSN3DSuccess(channelCount: Int) throws {
        let data = try audioChannelLayoutDataHOAACNSN3D(channelCount: channelCount)
        #expect(data.count == MemoryLayout<AudioChannelLayout>.size)
    }

    @Test(
        "audioChannelLayoutDataHOAACNSN3D throws for invalid channel count",
        arguments: [2, 5])
    func testAudioChannelLayoutDataHOAACNSN3DInvalidChannelCount(channelCount: Int) throws {
        #expect(throws: AmbiMuxError.invalidChannelCount(count: channelCount)) {
            try audioChannelLayoutDataHOAACNSN3D(channelCount: channelCount)
        }
    }

    // MARK: - copyAudioFormatDescriptionWithHOALayout

    @Test func testCopyAudioFormatDescriptionWithHOALayoutPreservesASBDAndSetsHOA() throws {
        let original = try makeInterleavedFloat4chFormatDescription()
        let originalASBD = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(original))
        let copied = try copyAudioFormatDescriptionWithHOALayout(from: original, channelCount: 4)
        let copiedASBD = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(copied))

        #expect(originalASBD.pointee.isEquivalentStreamFormat(to: copiedASBD.pointee))

        var layoutSize: Int = 0
        let layoutPtr = CMAudioFormatDescriptionGetChannelLayout(copied, sizeOut: &layoutSize)
        let layoutTag = try #require(layoutPtr?.pointee.mChannelLayoutTag)
        #expect(layoutTag & kAudioChannelLayoutTag_HOA_ACN_SN3D == kAudioChannelLayoutTag_HOA_ACN_SN3D)
    }

    @Test func testCopyAudioFormatDescriptionWithHOALayoutInvalidChannelCount() throws {
        let original = try makeInterleavedFloat4chFormatDescription()
        #expect(throws: AmbiMuxError.invalidChannelCount(count: 3)) {
            try copyAudioFormatDescriptionWithHOALayout(from: original, channelCount: 3)
        }
    }

    @Test func testCopyAudioFormatDescriptionWithHOALayoutNoAudioASBD() throws {
        let videoFormat = try makeH264VideoFormatDescription()
        #expect(throws: AmbiMuxError.couldNotGetAudioStreamDescription) {
            try copyAudioFormatDescriptionWithHOALayout(from: videoFormat, channelCount: 4)
        }
    }

    // MARK: - AudioStreamBasicDescription.isEquivalentStreamFormat

    @Test func testIsEquivalentStreamFormatIgnoresReserved() {
        let a = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 16,
            mFramesPerPacket: 1,
            mBytesPerFrame: 16,
            mChannelsPerFrame: 4,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var b = a
        b.mReserved = 0xDEAD_BEEF
        #expect(a.isEquivalentStreamFormat(to: b))
    }

    @Test func testIsEquivalentStreamFormatDetectsSampleRateChange() {
        let a = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 16,
            mFramesPerPacket: 1,
            mBytesPerFrame: 16,
            mChannelsPerFrame: 4,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var b = a
        b.mSampleRate = 44100
        #expect(!a.isEquivalentStreamFormat(to: b))
    }

    @Test func testIsEquivalentStreamFormatDetectsChannelCountChange() {
        let a = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 16,
            mFramesPerPacket: 1,
            mBytesPerFrame: 16,
            mChannelsPerFrame: 4,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var b = a
        b.mChannelsPerFrame = 2
        b.mBytesPerFrame = 8
        b.mBytesPerPacket = 8
        #expect(!a.isEquivalentStreamFormat(to: b))
    }

    // MARK: - linearPCMWriterOutputSettingsHOA

    @Test func testLinearPCMWriterOutputSettingsHOAMapsFlagsAndRate() throws {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 96000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsBigEndian
                | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 4,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let layoutData = try audioChannelLayoutDataHOAACNSN3D(channelCount: 4)
        let settings = linearPCMWriterOutputSettingsHOA(
            asbd: asbd, channelCount: 4, layoutData: layoutData)

        let formatID = try #require(settings[AVFormatIDKey] as? UInt32)
        #expect(formatID == kAudioFormatLinearPCM)

        let sampleRate = try #require(settings[AVSampleRateKey] as? Double)
        #expect(sampleRate == 48000)

        let channels = try #require(settings[AVNumberOfChannelsKey] as? Int)
        #expect(channels == 4)

        #expect(settings[AVLinearPCMIsFloatKey] as? Bool == true)
        #expect(settings[AVLinearPCMIsBigEndianKey] as? Bool == true)
        #expect(settings[AVLinearPCMIsNonInterleaved] as? Bool == true)

        let bitDepth = try #require(settings[AVLinearPCMBitDepthKey] as? Int)
        #expect(bitDepth == 32)

        let layoutOut = try #require(settings[AVChannelLayoutKey] as? Data)
        #expect(layoutOut == layoutData)
    }

    @Test func testLinearPCMWriterOutputSettingsHOAPreservesSub48kSampleRate() throws {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 16,
            mFramesPerPacket: 1,
            mBytesPerFrame: 16,
            mChannelsPerFrame: 4,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let layoutData = try audioChannelLayoutDataHOAACNSN3D(channelCount: 4)
        let settings = linearPCMWriterOutputSettingsHOA(
            asbd: asbd, channelCount: 4, layoutData: layoutData)
        let sampleRate = try #require(settings[AVSampleRateKey] as? Double)
        #expect(sampleRate == 44100)
    }
}
