import AVFoundation
import Foundation
import Testing

@testable import AmbiMuxCore

struct AudioConvertersTests {

    @Test func testAmbiMuxConversionWithWAV() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()

        // Get resource file paths
        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test", withExtension: "mov")

        // Generate output file path (full path specified)
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent("test_output.mov")
            .path

        // Execute conversion
        try await convertVideoWithAudioToMOV(
            audioPath: audioPath,
            audioMode: .lpcm,
            videoPath: videoPath,
            outputPath: outputPath
        )

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created at \(outputPath)")

        // Verify output file has audio track with correct channel count
        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        let audioTrack = try #require(audioTracks.first, "Output file has no audio track")

        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        let audioFormat = try #require(
            formatDescriptions.first, "Could not retrieve audio format information")

        let audioStreamBasicDescriptionPtr = try #require(
            CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat),
            "Could not retrieve audio stream information")
        let channelCount = Int(audioStreamBasicDescriptionPtr.pointee.mChannelsPerFrame)

        // Verify output has 4 channels (WAV input is 4-channel B-format)
        #expect(
            channelCount == 4,
            "Output audio should have 4 channels (actual=\(channelCount))"
        )

        // Remove test directory
        try TestResourceHelper.removeTestDirectory(at: cachePath)
    }

    @Test func testAmbiMuxConversionWithAPAC() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        // Get resource file paths (APAC-encoded audio)
        let audioPath = try TestResourceHelper.resourcePath(for: "test_apac", withExtension: "mp4")
        let videoPath = try TestResourceHelper.resourcePath(for: "test", withExtension: "mov")

        // Generate output file path
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "test_apac_output.mov"
        )
        .path

        // Execute conversion
        try await convertVideoWithAudioToMOV(
            audioPath: audioPath,
            audioMode: .apac,
            videoPath: videoPath,
            outputPath: outputPath
        )

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created at \(outputPath)")

        // Verify output file has audio track with APAC format
        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        let audioTrack = try #require(audioTracks.first, "Output file has no audio track")

        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        let audioFormat = try #require(
            formatDescriptions.first, "Could not retrieve audio format information")

        let audioStreamBasicDescriptionPtr = try #require(
            CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat),
            "Could not retrieve audio stream information")
        let formatID = audioStreamBasicDescriptionPtr.pointee.mFormatID
        let channelCount = Int(audioStreamBasicDescriptionPtr.pointee.mChannelsPerFrame)

        // Verify output is APAC format
        #expect(
            formatID == kAudioFormatAPAC,
            "Output audio should be APAC format (formatID=\(formatID))"
        )

        // Verify output has 7 channels (APAC input preserves original channel count)
        #expect(
            channelCount == 7,
            "Output audio should have 7 channels (actual=\(channelCount))"
        )
    }

    @Test func testConvertFailsWhenAudioMissing() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        // Specify non-existent audio path
        let missingAudioPath = "/this/path/does/not/exist.wav"
        let videoPath = try TestResourceHelper.resourcePath(for: "test", withExtension: "mov")
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "out_missing_audio.mov"
        ).path

        do {
            try await convertVideoWithAudioToMOV(
                audioPath: missingAudioPath,
                audioMode: .lpcm,
                videoPath: videoPath,
                outputPath: outputPath
            )
            #expect(Bool(false), "Missing audio should cause an error")
        } catch {
            // Expected exception occurred
            #expect(true)
        }
    }

    @Test func testConvertFailsWhenVideoMissing() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        // Specify non-existent video path
        let missingVideoPath = "/this/path/does/not/exist.mov"
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "out_missing_video.mov"
        ).path

        do {
            try await convertVideoWithAudioToMOV(
                audioPath: audioPath,
                audioMode: .lpcm,
                videoPath: missingVideoPath,
                outputPath: outputPath
            )
            #expect(Bool(false), "Missing video should cause an error")
        } catch {
            // Expected exception occurred
            #expect(true)
        }
    }

    @Test(
        "Audio sampling rate conversion",
        arguments: [
            ("test_44k_4ch", 44100.0, 44100.0),
            ("test_48k_4ch", 48000.0, 48000.0),
            ("test_96k_4ch", 96000.0, 48000.0),
        ])
    func testAudioSamplingRateConversion(
        fileName: String,
        inputSampleRate: Double,
        expectedOutputRate: Double
    ) async throws {
        let audioPath = try TestResourceHelper.resourcePath(for: fileName, withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test", withExtension: "mov")

        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "\(fileName)_output.mov"
        ).path

        // Execute conversion
        try await convertVideoWithAudioToMOV(
            audioPath: audioPath,
            audioMode: .lpcm,
            videoPath: videoPath,
            outputPath: outputPath
        )

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "\(fileName): Output file was not created")

        // Verify output file sample rate
        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        let audioTrack = try #require(
            audioTracks.first, "\(fileName): Output file has no audio track")

        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        let audioFormat = try #require(
            formatDescriptions.first, "\(fileName): Could not retrieve audio format information")

        let audioStreamBasicDescriptionPtr = try #require(
            CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat),
            "\(fileName): Could not retrieve audio stream information")
        let actualOutputRate = audioStreamBasicDescriptionPtr.pointee.mSampleRate

        // Verify sample rate conversion
        #expect(
            actualOutputRate == expectedOutputRate,
            "\(fileName): Sample rate does not match expected value (expected=\(expectedOutputRate)Hz, actual=\(actualOutputRate)Hz)"
        )

        // Remove test directory
        try TestResourceHelper.removeTestDirectory(at: cachePath)
    }

}
