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
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")

        // Execute with explicit output path
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "runAmbi_output.mov"
        ).path
        try await runAmbiMux(
            audioPath: audioPath,
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
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")

        // Execute with explicit output path
        let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent(
            "runAmbi_apac_output.mov"
        ).path
        try await runAmbiMux(
            audioPath: audioPath,
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

        // embeddedLpcm: audioPath は nil（映像ファイルの埋め込みオーディオを使用）
        let videoPath = try TestResourceHelper.resourcePath(for: "test_4ch", withExtension: "mov")

        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("runAmbi_embedded_output.mov").path

        try await runAmbiMux(
            audioPath: nil,
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

    @Test func testRunAmbiMuxSuccessWithEmbeddedAmbisonicsOnSecondTrack() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        // test_2ch_4ch.mov: 先頭がステレオ、2本目が 4ch（ソースは Discrete 2–5 ラベルだが変換可能）
        let videoPath = try TestResourceHelper.resourcePath(
            for: "test_2ch_4ch", withExtension: "mov")
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("runAmbi_embedded_2ch_then_4ch_output.mov").path

        try await runAmbiMux(
            audioPath: nil,
            videoPath: videoPath,
            outputPath: outputPath
        )

        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created at \(outputPath)")

        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        #expect(
            audioTracks.count == 1, "Ambisonics only (2ch preceding track in source is ignored)")

        let primaryFormat = try await audioTracks[0].load(.formatDescriptions)
        guard let fd = primaryFormat.first,
            let asbdPtr = fd.audioStreamBasicDescription
        else {
            Issue.record("Could not get primary audio format")
            return
        }
        #expect(Int(asbdPtr.mChannelsPerFrame) == 4, "Primary track should be 4ch")
    }

    @Test func testRunAmbiMuxFailsWhenNoAmbisonicsTrackInVideo() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        // test_2ch.mov はステレオのみで Ambisonics トラックがない
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("should_not_be_created.mov").path

        await #expect(throws: AmbiMuxError.noAmbisonicsTrackFound) {
            try await runAmbiMux(
                audioPath: nil,
                videoPath: videoPath,
                outputPath: outputPath
            )
        }
    }

    @Test func testRunAmbiMuxFailsWhenAPACInputWithLPCMOutput() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(for: "test_apac", withExtension: "mp4")
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("should_not_be_created.mov").path

        await #expect(throws: AmbiMuxError.invalidOutputFormatForAPACInput) {
            try await runAmbiMux(
                audioPath: audioPath,
                videoPath: videoPath,
                outputPath: outputPath,
                outputAudioFormat: .lpcm
            )
        }
    }

    @Test func testRunAmbiMuxFailsWhenEmbeddedAmbisonicsIsAPAC() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")
        let intermediatePath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("embedded_apac_intermediate.mov").path

        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: intermediatePath,
            outputAudioFormat: .apac
        )

        let secondOutputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("should_not_be_created_embedded.mov").path

        await #expect(throws: AmbiMuxError.embeddedAmbisonicsAlreadyAPAC) {
            try await runAmbiMux(
                audioPath: nil,
                videoPath: intermediatePath,
                outputPath: secondOutputPath
            )
        }
    }
}
