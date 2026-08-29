import AVFoundation
import CoreAudioTypes
import Foundation
import Testing

@testable import AmbiMuxCore

struct AudioAttenuateTests {

    /// テスト用リソース WAV は無音のため、W に 997 Hz 正弦波を入れた 4ch WAV を作る。
    private func writeAmbisonicsToneWAV(in cachePath: String, name: String = "tone_4ch.wav") throws
        -> String
    {
        let sampleRate = 48_000.0
        let duration = 2.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let layout = try #require(
            AVAudioChannelLayout(
                layoutTag: kAudioChannelLayoutTag_HOA_ACN_SN3D | AudioChannelLayoutTag(4)
            )
        )
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            interleaved: false,
            channelLayout: layout
        )
        let path = URL(fileURLWithPath: cachePath).appendingPathComponent(name).path
        let file = try AVAudioFile(
            forWriting: URL(fileURLWithPath: path), settings: format.settings)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let omega = 2.0 * Double.pi * 997.0 / sampleRate
        let channels = try #require(buffer.floatChannelData)
        for frame in 0..<Int(frameCount) {
            channels[0][frame] = Float(sin(Double(frame) * omega) * 0.2)
        }
        try file.write(from: buffer)
        return path
    }

    private func muxAPACClip(
        in cachePath: String,
        name: String,
        audioPath: String? = nil
    ) async throws -> String {
        let resolvedAudioPath: String
        if let audioPath {
            resolvedAudioPath = audioPath
        } else {
            resolvedAudioPath = try writeAmbisonicsToneWAV(in: cachePath)
        }
        let videoPath = try TestResourceHelper.resourcePath(for: "test_2ch", withExtension: "mov")
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent(name).path
        try await runAmbiMux(
            audioPath: resolvedAudioPath,
            videoPath: videoPath,
            outputPath: outputPath,
            outputAudioFormat: .apac
        )
        return outputPath
    }

    private func wChannelRMS(ofMOV path: String) async throws -> Double {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let track = try await requireAPACAmbisonicsTrack(in: asset)
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first,
            let asbd = formatDescription.audioStreamBasicDescription
        else {
            throw AmbiMuxError.couldNotGetAudioStreamDescription
        }
        let channelCount = Int(asbd.mChannelsPerFrame)
        let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: linearPCMReaderOutputSettings(
                channelCount: channelCount, sampleRate: sampleRate)
        )
        reader.add(output)
        try reader.start()

        var sumSquares = 0.0
        var sampleCount = 0
        while let buffer = output.copyNextSampleBuffer() {
            let samples = try copyInterleavedFloat32(from: buffer)
            for index in stride(from: 0, to: samples.count, by: channelCount) {
                let w = Double(samples[index])
                sumSquares += w * w
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else {
            throw AmbiMuxError.couldNotAccessAudioSampleData
        }
        return sqrt(sumSquares / Double(sampleCount))
    }

    @Test func testAttenuateGainMinus6HalvesWChannelRMS() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let clipPath = try await muxAPACClip(in: cachePath, name: "attenuate_src.mov")
        let before = try await wChannelRMS(ofMOV: clipPath)
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("attenuate_minus6.mov").path

        try await runAttenuateMOV(inputPath: clipPath, outputPath: outputPath, gainDb: -6)

        let after = try await wChannelRMS(ofMOV: outputPath)
        #expect(abs((before * 0.5) - after) / before < 0.15)

        let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        #expect(audioTracks.count == 2, "Output should keep ambisonics + fallback")

        let primaryFormat = try await audioTracks[0].load(.formatDescriptions)
        guard let primaryFD = primaryFormat.first,
            let primaryASBD = primaryFD.audioStreamBasicDescription
        else {
            Issue.record("Could not get primary audio format")
            return
        }
        #expect(primaryASBD.mFormatID == kAudioFormatAPAC)
        #expect(Int(primaryASBD.mChannelsPerFrame) == 4)
    }

    @Test func testAttenuateRejectsPositiveGain() async throws {
        let cachePath = try TestResourceHelper.createTestDirectory()
        defer { try? TestResourceHelper.removeTestDirectory(at: cachePath) }

        let clipPath = try await muxAPACClip(in: cachePath, name: "attenuate_boost_src.mov")
        let outputPath = URL(fileURLWithPath: cachePath)
            .appendingPathComponent("attenuate_boost.mov").path

        await #expect(throws: AmbiMuxError.attenuateGainMustNotBoost) {
            try await runAttenuateMOV(inputPath: clipPath, outputPath: outputPath, gainDb: 3)
        }
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }
}
