import AVFoundation
import Foundation

nonisolated public func runAmbiMux(
    audioPath: String?,
    videoPath: String,
    outputPath: String? = nil,
    outputAudioFormat: AudioOutputFormat? = nil
)
    async throws
{
    let audioMode: AudioInputMode
    let actualAudioPath: String

    if let path = audioPath {
        audioMode = try await detectAudioInputMode(audioPath: path)
        actualAudioPath = path
    } else {
        try await validateEmbeddedLpcmAudio(videoPath: videoPath)
        audioMode = .embeddedLpcm
        actualAudioPath = videoPath
    }

    // APAC 入力に対して lpcm 出力は指定できない
    if case .apac = audioMode, outputAudioFormat == .lpcm {
        throw AmbiMuxError.invalidOutputFormatForAPACInput
    }

    // Generate output file path
    let finalOutputPath = generateOutputPath(
        outputPath: outputPath, videoPath: videoPath)

    // Execute conversion
    try await convertVideoWithAudioToMOV(
        audioPath: actualAudioPath,
        audioMode: audioMode,
        videoPath: videoPath,
        outputPath: finalOutputPath,
        outputAudioFormat: outputAudioFormat
    )

    // Verify output file
    try await verifyOutputFileDetails(outputPath: finalOutputPath)
}
