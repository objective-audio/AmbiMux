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
}
