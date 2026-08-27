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

    @Test func testRunJoinMOVFailsWhenNoInputs() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_empty_output.mov").path

        await #expect(throws: AmbiMuxError.concatRequiresAtLeastOneInput) {
            try await runJoinMOV(
                inputPaths: [],
                outputPath: outputPath
            )
        }
    }

    @Test func testRunJoinMOVSucceedsWithSingleRangedInput() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")

        let clipPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_single_clip.mov").path
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_single_output.mov").path

        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: videoPath,
            outputPath: clipPath,
            outputAudioFormat: .apac
        )

        let clipAsset = AVURLAsset(url: URL(fileURLWithPath: clipPath))
        let clipVideo = try await clipAsset.loadTracks(withMediaType: .video)[0]
        let clipDuration = CMTimeGetSeconds(try await clipVideo.load(.timeRange).duration)
        #expect(clipDuration > 1.0, "Test clip should be longer than 1s for range trim")

        let segmentDuration = 0.5
        try await runJoinMOV(
            segments: [
                JoinSegment(path: clipPath, startSeconds: 0, endSeconds: segmentDuration)
            ],
            outputPath: outputPath
        )

        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Trimmed output file should be created")

        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        #expect(outputVideoTracks.count == 1, "Output should have one video track")

        let outputDuration = CMTimeGetSeconds(
            try await outputVideoTracks[0].load(.timeRange).duration)
        #expect(
            abs(outputDuration - segmentDuration) < 0.15,
            "Output duration should equal the trimmed segment"
        )
    }

    @Test func testParseJoinSegmentArgument() throws {
        let full = try parseJoinSegmentArgument("/tmp/clip.mov")
        #expect(full == JoinSegment(path: "/tmp/clip.mov"))

        let ranged = try parseJoinSegmentArgument("/tmp/clip.mov@1.5-12")
        #expect(
            ranged == JoinSegment(path: "/tmp/clip.mov", startSeconds: 1.5, endSeconds: 12)
        )

        let atInName = try parseJoinSegmentArgument("/tmp/clip@name.mov")
        #expect(atInName == JoinSegment(path: "/tmp/clip@name.mov"))

        #expect(throws: AmbiMuxError.self) {
            try parseJoinSegmentArgument("/tmp/clip.mov@5-1")
        }
    }

    @Test func testRunJoinMOVWithTimeRanges() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")

        let clip1Path = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_range_clip1.mov").path
        let clip2Path = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_range_clip2.mov").path
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_range_output.mov").path

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
        let clip1Duration = CMTimeGetSeconds(try await clip1Video.load(.timeRange).duration)
        #expect(clip1Duration > 1.0, "Test clip should be longer than 1s for range join")

        let segmentDuration = 0.5
        try await runJoinMOV(
            segments: [
                JoinSegment(path: clip1Path, startSeconds: 0, endSeconds: segmentDuration),
                JoinSegment(path: clip2Path, startSeconds: 0, endSeconds: segmentDuration),
            ],
            outputPath: outputPath
        )

        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        #expect(outputVideoTracks.count == 1)

        let outputDuration = CMTimeGetSeconds(
            try await outputVideoTracks[0].load(.timeRange).duration)
        #expect(
            abs(outputDuration - (segmentDuration * 2)) < 0.15,
            "Output duration should equal sum of trimmed segments"
        )
    }

    @Test func testRunJoinMOVFailsWhenTimeRangeOutOfBounds() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(
            for: "test_48k_4ch", withExtension: "wav")
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")

        let clip1Path = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_oob_clip1.mov").path
        let clip2Path = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_oob_clip2.mov").path
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("join_oob_output.mov").path

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

        await #expect(throws: AmbiMuxError.self) {
            try await runJoinMOV(
                segments: [
                    JoinSegment(path: clip1Path, startSeconds: 0, endSeconds: 9999),
                    JoinSegment(path: clip2Path),
                ],
                outputPath: outputPath
            )
        }

        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }
}
