import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import AmbiMuxCore

struct RunAmbiMuxTests {

    @Test func testRunAmbiMuxSuccessWithWAV() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        // Get resource file paths
        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test", withExtension: "mov")

        // Execute with explicit output path
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "runAmbi_output.mov"
        ).path
        try await runAmbiMux(
            audioPath: audioPath,
            audioMode: .lpcm,
            videoPath: videoPath,
            outputPath: outputPath
        )

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created at \(outputPath)")
    }

    @Test func testRunAmbiMuxSuccessWithAPAC() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        // Get resource file paths (APAC-encoded audio)
        let audioPath = try TestResourceHelper.resourcePath(for: "test_apac", withExtension: "mp4")
        let videoPath = try TestResourceHelper.resourcePath(for: "test", withExtension: "mov")

        // Execute with explicit output path
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "runAmbi_apac_output.mov"
        ).path
        try await runAmbiMux(
            audioPath: audioPath,
            audioMode: .apac,
            videoPath: videoPath,
            outputPath: outputPath
        )

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created at \(outputPath)")
    }

    @Test func testRunAmbiMuxSuccessWithEmbeddedLpcm() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        // embeddedLpcm: audioPath と videoPath は同じファイル
        let videoPath = try TestResourceHelper.resourcePath(for: "test_4ch", withExtension: "mov")

        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("runAmbi_embedded_output.mov").path

        try await runAmbiMux(
            audioPath: videoPath,
            audioMode: .embeddedLpcm,
            videoPath: videoPath,
            outputPath: outputPath
        )

        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created at \(outputPath)")

        // 出力ファイルの音声トラックを検証
        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)

        // embeddedLpcm はフォールバックなし → 1トラックのみ
        #expect(audioTracks.count == 1, "Output should have 1 audio track (ambisonics only)")

        let formatDesc = try await audioTracks[0].load(.formatDescriptions)
        guard let fd = formatDesc.first,
            let asbdPtr = fd.audioStreamBasicDescription
        else {
            Issue.record("Could not get format description")
            return
        }
        #expect(Int(asbdPtr.mChannelsPerFrame) == 4, "Audio track should be 4ch APAC")
    }

    @Test func testRunAmbiMuxSuccessWithVideoAudioFallback() async throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let ambisonicsAudioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test", withExtension: "mov")

        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "runAmbi_fallback_output.mov"
        ).path

        try await runAmbiMux(
            audioPath: ambisonicsAudioPath,
            audioMode: .lpcm,
            videoPath: videoPath,
            outputPath: outputPath
        )

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created")

        // Check if output has audio tracks
        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)

        // Should have 2 tracks: ambisonics (4ch) and fallback stereo (2ch) from video
        #expect(
            audioTracks.count == 2,
            "Output should have 2 audio tracks (ambisonics + fallback stereo)")

        // Verify track order and contents
        // Track 1 (index 0) should be ambisonics (4ch)
        let track1 = audioTracks[0]
        let formatDesc1 = try await track1.load(.formatDescriptions)
        guard let formatDescription1 = formatDesc1.first,
            let asbdPtr1 = formatDescription1.audioStreamBasicDescription
        else {
            Issue.record("Could not get format description for track 1")
            return
        }
        let channelCount1 = Int(asbdPtr1.mChannelsPerFrame)
        #expect(
            channelCount1 == 4, "Track 1 should be ambisonics with 4 channels, got \(channelCount1)"
        )

        // Track 2 (index 1) should be stereo fallback (2ch)
        let track2 = audioTracks[1]
        let formatDesc2 = try await track2.load(.formatDescriptions)
        guard let formatDescription2 = formatDesc2.first,
            let asbdPtr2 = formatDescription2.audioStreamBasicDescription
        else {
            Issue.record("Could not get format description for track 2")
            return
        }
        let channelCount2 = Int(asbdPtr2.mChannelsPerFrame)
        #expect(
            channelCount2 == 2,
            "Track 2 should be stereo fallback with 2 channels, got \(channelCount2)")
    }
}
