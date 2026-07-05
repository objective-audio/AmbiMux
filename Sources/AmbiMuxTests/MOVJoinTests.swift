import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import AmbiMuxCore

struct MOVJoinTests {

    @Test func testRunJoinMOVSucceedsWithMatchingClips() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")

        let clip1Path = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_clip1.mov").path
        let clip2Path = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_clip2.mov").path
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_output.mov").path

        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: clip1Path,
            outputAudioFormat: .apac
        )
        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: clip2Path,
            outputAudioFormat: .apac
        )

        let clip1Asset = AVURLAsset(url: URL(fileURLWithPath: clip1Path))
        let clip2Asset = AVURLAsset(url: URL(fileURLWithPath: clip2Path))
        let clip1Video = try await clip1Asset.loadTracks(withMediaType: .video)[0]
        let clip2Video = try await clip2Asset.loadTracks(withMediaType: .video)[0]
        let clip1Duration = CMTimeGetSeconds(try await clip1Video.load(.timeRange).duration)
        let clip2Duration = CMTimeGetSeconds(try await clip2Video.load(.timeRange).duration)

        try await runJoinMOV(inputPaths: [clip1Path, clip2Path], outputPath: outputPath)

        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Joined output file should be created")

        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        #expect(outputVideoTracks.count == 1, "Output should have one video track")

        let outputDuration = CMTimeGetSeconds(
            try await outputVideoTracks[0].load(.timeRange).duration)
        #expect(
            abs(outputDuration - (clip1Duration + clip2Duration)) < 0.1,
            "Output duration should equal sum of input durations"
        )

        let outputAudioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        #expect(outputAudioTracks.count == 2, "Output should have ambisonics + fallback audio tracks")

        let primaryFormat = try await outputAudioTracks[0].load(.formatDescriptions)
        guard let primaryFD = primaryFormat.first,
            let primaryASBD = primaryFD.audioStreamBasicDescription
        else {
            Issue.record("Could not get primary audio format")
            return
        }
        #expect(Int(primaryASBD.mChannelsPerFrame) == 4, "Primary track should be 4ch")

        let fallbackFormat = try await outputAudioTracks[1].load(.formatDescriptions)
        guard let fallbackFD = fallbackFormat.first,
            let fallbackASBD = fallbackFD.audioStreamBasicDescription
        else {
            Issue.record("Could not get fallback audio format")
            return
        }
        #expect(Int(fallbackASBD.mChannelsPerFrame) == 2, "Fallback track should be 2ch")
    }

    @Test func testRunJoinMOVPreservesPreferredTransform() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")

        let clip1Path = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_transform_clip1.mov").path
        let clip2Path = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_transform_clip2.mov").path
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_transform_output.mov").path

        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: clip1Path,
            outputAudioFormat: .apac
        )
        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: clip2Path,
            outputAudioFormat: .apac
        )

        let clip1Asset = AVURLAsset(url: URL(fileURLWithPath: clip1Path))
        let clip1Video = try await clip1Asset.loadTracks(withMediaType: .video)[0]
        let sourceTransform = try await clip1Video.load(.preferredTransform)

        try await runJoinMOV(inputPaths: [clip1Path, clip2Path], outputPath: outputPath)

        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        #expect(outputVideoTracks.count == 1, "Output should have one video track")

        let outputTransform = try await outputVideoTracks[0].load(.preferredTransform)
        #expect(
            outputTransform == sourceTransform,
            "Output video preferredTransform should match the source clips"
        )
    }

    @Test func testRunJoinMOVFailsWhenFormatMismatch() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")

        let apacClipPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_apac.mov").path
        let lpcmClipPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_lpcm.mov").path
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_mismatch_output.mov").path

        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: apacClipPath,
            outputAudioFormat: .apac
        )
        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: lpcmClipPath,
            outputAudioFormat: .lpcm
        )

        await #expect(throws: AmbiMuxError.self) {
            try await runJoinMOV(
                inputPaths: [apacClipPath, lpcmClipPath],
                outputPath: outputPath
            )
        }

        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(!outputExists, "Output file should not be created on format mismatch")
    }

    @Test func testRunJoinMOVFailsWhenOnlyOneInput() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_single_output.mov").path

        await #expect(throws: AmbiMuxError.concatRequiresAtLeastTwoInputs) {
            try await runJoinMOV(
                inputPaths: ["/tmp/nonexistent.mov"],
                outputPath: outputPath
            )
        }
    }
}
