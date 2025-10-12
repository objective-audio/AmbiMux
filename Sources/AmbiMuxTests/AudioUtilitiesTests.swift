import Foundation
import Testing

@testable import AmbiMuxCore

struct AudioUtilitiesTests {

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
}
