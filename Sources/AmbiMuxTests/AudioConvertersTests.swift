import AVFoundation
import Foundation
import Testing

@testable import AmbiMuxCore

struct AudioConvertersTests {

    @Test func testAmbiMuxConversion() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()

        // Get resource file paths
        let audioPath = try TestResourceHelper.wavPath(for: "test_48k_4ch")
        let videoPath = try TestResourceHelper.movPath(for: "test")

        // Generate output file path (full path specified)
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent("test_output.mov")
            .path

        // Execute conversion
        try await convertVideoWithAudioToMOV(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: outputPath
        )

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created at \(outputPath)")

        // Remove test directory
        try TestResourceHelper.removeTestDirectory(at: cachePath)
    }

    @Test func testConvertFailsWhenAudioMissing() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        // Specify non-existent audio path
        let missingAudioPath = "/this/path/does/not/exist.wav"
        let videoPath = try TestResourceHelper.movPath(for: "test")
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "out_missing_audio.mov"
        ).path

        do {
            try await convertVideoWithAudioToMOV(
                audioPath: missingAudioPath,
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

        let audioPath = try TestResourceHelper.wavPath(for: "test_48k_4ch")
        // Specify non-existent video path
        let missingVideoPath = "/this/path/does/not/exist.mov"
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "out_missing_video.mov"
        ).path

        do {
            try await convertVideoWithAudioToMOV(
                audioPath: audioPath,
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
        let audioPath = try TestResourceHelper.wavPath(for: fileName)
        let videoPath = try TestResourceHelper.movPath(for: "test")

        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "\(fileName)_output.mov"
        ).path

        // Execute conversion
        try await convertVideoWithAudioToMOV(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: outputPath
        )

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "\(fileName): Output file was not created")

        // Verify output file sample rate
        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        let audioTrack = try #require(audioTracks.first, "\(fileName): Output file has no audio track")

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
