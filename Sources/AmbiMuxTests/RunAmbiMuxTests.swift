import Foundation
import Testing

@testable import AmbiMuxCore

struct RunAmbiMuxTests {

	@Test func testRunAmbiMuxSuccess() async throws {
		// Create test directory
		let cachePath = try TestResourceHelper.createTestDirectory()
		defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

		// Get resource file paths
		let audioPath = try TestResourceHelper.wavPath(for: "test_48k_4ch")
		let videoPath = try TestResourceHelper.movPath(for: "test")

		// Execute with explicit output path
		let outputPath = URL(fileURLWithPath: cachePath).appendingPathComponent("runAmbi_output.mov").path
		try await runAmbiMux(audioPath: audioPath, videoPath: videoPath, outputPath: outputPath)

		// Verify output file was created
		let outputExists = FileManager.default.fileExists(atPath: outputPath)
		#expect(outputExists, "Output file should be created at \(outputPath)")
	}
}


