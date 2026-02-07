import Foundation
import Testing

@testable import AmbiMuxCore

struct AudioValidationTests {

    @Test(
        "Audio channel validation",
        arguments: [
            ("test_48k_1ch", "wav", AudioInputMode.lpcm, false),
            ("test_48k_2ch", "wav", AudioInputMode.lpcm, false),
            ("test_48k_4ch", "wav", AudioInputMode.lpcm, true),
            ("test_48k_9ch", "wav", AudioInputMode.lpcm, true),
            ("test_48k_16ch", "wav", AudioInputMode.lpcm, true),
            ("test_44k_4ch", "wav", AudioInputMode.lpcm, true),
            ("test_96k_4ch", "wav", AudioInputMode.lpcm, true),
            ("test_apac", "mp4", AudioInputMode.apac, true),
        ])
    func testAudioChannelValidation(
        fileName: String,
        fileExtension: String,
        audioMode: AudioInputMode,
        shouldSucceed: Bool
    ) async throws {
        let audioPath = try TestResourceHelper.resourcePath(
            for: fileName, withExtension: fileExtension)

        do {
            try await validateAudioFile(audioPath: audioPath, audioMode: audioMode)
            // No error occurred
            #expect(shouldSucceed, "\(fileName): Validation succeeded but should have failed")
        } catch {
            // Error occurred
            #expect(!shouldSucceed, "\(fileName): Validation failed but should have succeeded")
        }
    }
}
