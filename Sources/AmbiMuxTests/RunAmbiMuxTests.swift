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
        try await runAmbiMux(audioPath: audioPath, videoPath: videoPath, outputPath: outputPath)

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
        try await runAmbiMux(audioPath: audioPath, videoPath: videoPath, outputPath: outputPath)

        // Verify output file was created
        let outputExists = FileManager.default.fileExists(atPath: outputPath)
        #expect(outputExists, "Output file should be created at \(outputPath)")
    }
}
