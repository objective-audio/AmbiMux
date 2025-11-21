import Foundation
import Testing

@testable import AmbiMuxCore

struct TestResourceHelperTests {

    @Test func testCacheDirectory() throws {
        // Create test directory
        let cachePath = try TestResourceHelper.createTestDirectory()

        // Verify directory was created
        let exists = FileManager.default.fileExists(atPath: cachePath)
        #expect(exists, "Test cache directory should exist at \(cachePath)")

        // Remove test directory
        try TestResourceHelper.removeTestDirectory(at: cachePath)

        // Verify directory was removed
        let stillExists = FileManager.default.fileExists(atPath: cachePath)
        #expect(!stillExists, "Test cache directory should be removed")

    }

    @Test func testResourcePaths() throws {
        // Directly check resource file paths in test bundle
        let wavPath = try TestResourceHelper.resourcePath(for: "test_48k_4ch", withExtension: "wav")
        let movPath = try TestResourceHelper.resourcePath(for: "test", withExtension: "mov")

        // Verify files exist
        let wavExists = FileManager.default.fileExists(atPath: wavPath)
        let movExists = FileManager.default.fileExists(atPath: movPath)

        #expect(wavExists, "test_48k_4ch.wav should exist at \(wavPath)")
        #expect(movExists, "test.mov should exist at \(movPath)")
    }
}
