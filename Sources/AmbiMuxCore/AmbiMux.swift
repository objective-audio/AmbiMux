import AVFoundation
import Foundation

nonisolated public func runAmbiMux(audioPath: String, videoPath: String, outputPath: String? = nil)
    async throws {
    // Validate audio file
    try await validateAudioFile(audioPath: audioPath)

    // Generate output file path
    let finalOutputPath = generateOutputPath(
        outputPath: outputPath, videoPath: videoPath)

    // Execute conversion
    try await convertVideoWithAudioToMOV(
        audioPath: audioPath, videoPath: videoPath, outputPath: finalOutputPath)

    // Verify output file
    try await verifyOutputFileDetails(outputPath: finalOutputPath)
}
