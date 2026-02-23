import AVFoundation
import Foundation

nonisolated public func runAmbiMux(
    audioPath: String,
    audioMode: AudioInputMode,
    videoPath: String,
    outputPath: String? = nil,
    outputAudioFormat: AudioOutputFormat? = nil
)
    async throws
{
    // APAC 入力に対して lpcm 出力は指定できない
    if case .apac = audioMode, outputAudioFormat == .lpcm {
        throw AmbiMuxError.invalidOutputFormatForAPACInput
    }

    // Validate audio file
    try await validateAudioFile(audioPath: audioPath, audioMode: audioMode)

    // Generate output file path
    let finalOutputPath = generateOutputPath(
        outputPath: outputPath, videoPath: videoPath)

    // Execute conversion
    try await convertVideoWithAudioToMOV(
        audioPath: audioPath,
        audioMode: audioMode,
        videoPath: videoPath,
        outputPath: finalOutputPath,
        outputAudioFormat: outputAudioFormat
    )

    // Verify output file
    try await verifyOutputFileDetails(outputPath: finalOutputPath)
}
