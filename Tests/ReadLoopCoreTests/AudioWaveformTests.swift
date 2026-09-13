import AVFoundation
import AppInfrastructure
import Foundation
import Testing

@Test func waveformAnalyzerTracksQuietThenLoudAudio() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("waveform-\(UUID().uuidString).caf")
    defer { try? FileManager.default.removeItem(at: url) }

    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44_100,
        channels: 1,
        interleaved: false
    ))
    let frames: AVAudioFrameCount = 44_100
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(frames) {
        channel[index] = index < Int(frames) / 2 ? 0.05 : 0.5
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)

    let waveform = try AudioWaveformAnalyzer.analyze(url: url, sampleCount: 20)

    #expect(waveform.peaks.count == 20)
    let quiet = waveform.peaks.prefix(5).reduce(0, +)
    let loud = waveform.peaks.suffix(5).reduce(0, +)
    #expect(loud > quiet * 3)
}
