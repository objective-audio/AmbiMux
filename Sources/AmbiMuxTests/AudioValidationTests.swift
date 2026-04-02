import Foundation
import Testing

@testable import AmbiMuxCore

struct AudioValidationTests {

    @Test(
        "Audio channel validation",
        arguments: [
            ("test_48k_1ch", "wav", false),
            ("test_48k_2ch", "wav", false),
            ("test_48k_4ch", "wav", true),
            ("test_48k_9ch", "wav", true),
            ("test_48k_16ch", "wav", true),
            ("test_44k_4ch", "wav", true),
            ("test_96k_4ch", "wav", true),
            ("test_apac", "mp4", true),
        ])
    func testAudioChannelValidation(
        fileName: String,
        fileExtension: String,
        shouldSucceed: Bool
    ) async throws {
        let audioPath = try TestResourceHelper.resourcePath(
            for: fileName, withExtension: fileExtension)

        do {
            _ = try await detectAudioInputMode(audioPath: audioPath)
            // No error occurred
            #expect(shouldSucceed, "\(fileName): Detection succeeded but should have failed")
        } catch {
            // Error occurred
            #expect(!shouldSucceed, "\(fileName): Detection failed but should have succeeded")
        }
    }

    @Test func testValidateAudioInputEligibilityAPAC() async throws {
        let audioPath = try TestResourceHelper.resourcePath(for: "test_apac", withExtension: "mp4")
        let result = try await validateAudioInputEligibility(audioPath: audioPath)

        #expect(result.isEligible)
        if case .audioHasAPAC = result.reason {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .audioHasAPAC, got \(result.reason)")
        }
    }

    @Test func testValidateAudioInputEligibilityAmbisonics() async throws {
        let audioPath = try TestResourceHelper.resourcePath(for: "test_48k_4ch", withExtension: "wav")
        let result = try await validateAudioInputEligibility(audioPath: audioPath)

        #expect(result.isEligible)
        if case .audioHasAmbisonics(let order) = result.reason {
            #expect(order == .first)
        } else {
            Issue.record("Expected .audioHasAmbisonics(order:), got \(result.reason)")
        }
    }

    @Test func testValidateAudioInputEligibilityUnsupported() async throws {
        let audioPath = try TestResourceHelper.resourcePath(for: "test_48k_2ch", withExtension: "wav")
        let result = try await validateAudioInputEligibility(audioPath: audioPath)

        #expect(!result.isEligible)
        if case .audioMissingAPACAndAmbisonics = result.reason {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .audioMissingAPACAndAmbisonics, got \(result.reason)")
        }
    }

    @Test func testValidateVideoInputEligibilityAmbisonicsWithoutAPAC() async throws {
        let videoPath = try TestResourceHelper.resourcePath(for: "test_4ch", withExtension: "mov")
        let result = try await validateVideoInputEligibility(videoPath: videoPath)

        #expect(result.isEligible)
        if case .videoAmbisonicsWithoutAPAC = result.reason {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .videoAmbisonicsWithoutAPAC, got \(result.reason)")
        }
    }

    @Test func testValidateVideoInputEligibilityMissingAmbisonics() async throws {
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")
        let result = try await validateVideoInputEligibility(videoPath: videoPath)

        #expect(!result.isEligible)
        if case .videoMissingAmbisonics = result.reason {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .videoMissingAmbisonics, got \(result.reason)")
        }
    }

    @Test func testValidateVideoInputEligibilityAlreadyHasAPAC() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let audioPath = try TestResourceHelper.resourcePath(for: "test_48k_4ch", withExtension: "wav")
        let sourceVideoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")
        let apacVideoPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("video_with_apac.mov").path

        try await runAmbiMux(
            audioPath: audioPath,
            videoPath: sourceVideoPath,
            outputPath: apacVideoPath,
            outputAudioFormat: .apac
        )

        let result = try await validateVideoInputEligibility(videoPath: apacVideoPath)
        #expect(!result.isEligible)
        if case .videoAlreadyHasAPAC = result.reason {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .videoAlreadyHasAPAC, got \(result.reason)")
        }
    }
}
