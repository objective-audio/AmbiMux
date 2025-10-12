import Foundation
import Testing

@testable import AmbiMuxCore

struct AudioValidationTests {

    @Test(
        "Audio channel validation",
        arguments: [
            ("test_48k_1ch", false),
            ("test_48k_2ch", false),
            ("test_48k_4ch", true),
            ("test_44k_4ch", true),
            ("test_96k_4ch", true),
        ])
    func testAudioChannelValidation(
        fileName: String,
        shouldSucceed: Bool
    ) async throws {
        let audioPath = try TestResourceHelper.wavPath(for: fileName)

        do {
            try await validateAudioFile(audioPath: audioPath)
            // No error occurred
            #expect(shouldSucceed, "\(fileName): Validation succeeded but should have failed")
        } catch {
            // Error occurred
            #expect(!shouldSucceed, "\(fileName): Validation failed but should have succeeded")
        }
    }
}
