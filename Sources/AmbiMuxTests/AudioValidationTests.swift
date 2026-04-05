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

        if case .eligible(.apac) = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .eligible(.apac), got \(result)")
        }
    }

    @Test func testValidateAudioInputEligibilityAmbisonics() async throws {
        let audioPath = try TestResourceHelper.resourcePath(for: "test_48k_4ch", withExtension: "wav")
        let result = try await validateAudioInputEligibility(audioPath: audioPath)

        if case .eligible(.ambisonics(let order)) = result {
            #expect(order == .first)
        } else {
            Issue.record("Expected .eligible(.ambisonics), got \(result)")
        }
    }

    @Test func testValidateAudioInputEligibilityUnsupported() async throws {
        let audioPath = try TestResourceHelper.resourcePath(for: "test_48k_2ch", withExtension: "wav")
        let result = try await validateAudioInputEligibility(audioPath: audioPath)

        if case .ineligible(.missingAPACAndAmbisonics) = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .ineligible(.missingAPACAndAmbisonics), got \(result)")
        }
    }

    @Test func testValidateVideoInputEligibilityAmbisonicsWithoutAPAC() async throws {
        let videoPath = try TestResourceHelper.resourcePath(for: "test_4ch", withExtension: "mov")
        let result = try await validateVideoInputEligibility(videoPath: videoPath)

        if case .eligible(.ambisonicsWithoutAPAC) = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .eligible(.ambisonicsWithoutAPAC), got \(result)")
        }
    }

    @Test func testValidateVideoInputEligibilityNoEmbeddedAudio() async throws {
        let videoPath = try TestResourceHelper.resourcePath(for: "test_no_audio", withExtension: "mov")
        let result = try await validateVideoInputEligibility(videoPath: videoPath)

        if case .eligible(.noEmbeddedAudioUseExternal) = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .eligible(.noEmbeddedAudioUseExternal), got \(result)")
        }
    }

    @Test func testValidateVideoInputEligibilityMissingAmbisonics() async throws {
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")
        let result = try await validateVideoInputEligibility(videoPath: videoPath)

        if case .ineligible(.missingAmbisonicsTrack) = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .ineligible(.missingAmbisonicsTrack), got \(result)")
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
        if case .ineligible(.alreadyHasAPAC) = result {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .ineligible(.alreadyHasAPAC), got \(result)")
        }
    }
}
