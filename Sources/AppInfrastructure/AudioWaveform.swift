import AVFoundation
import Foundation

public struct AudioWaveform: Codable, Hashable, Sendable {
    public let duration: TimeInterval
    /// Normalized RMS envelope, 0...1, ordered from start to end.
    public let peaks: [Float]

    public init(duration: TimeInterval, peaks: [Float]) {
        self.duration = duration
        self.peaks = peaks
    }
}

public enum AudioWaveformAnalyzer {
    public static func analyze(url: URL, sampleCount: Int = 240) throws -> AudioWaveform {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = max(0, file.length)
        guard frameCount > 0, format.sampleRate > 0 else {
            return AudioWaveform(duration: 0, peaks: [])
        }

        let bins = max(1, sampleCount)
        var energy = [Double](repeating: 0, count: bins)
        var counts = [Int](repeating: 0, count: bins)
        let capacity: AVAudioFrameCount = 4_096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioWaveformError.cannotAllocateBuffer
        }

        var frameOffset: AVAudioFramePosition = 0
        while frameOffset < frameCount {
            buffer.frameLength = 0
            try file.read(into: buffer)
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { break }
            guard let channels = buffer.floatChannelData else {
                throw AudioWaveformError.unsupportedSampleFormat
            }

            let channelCount = Int(format.channelCount)
            for frame in 0..<frames {
                let globalFrame = frameOffset + AVAudioFramePosition(frame)
                let position = Double(globalFrame) / Double(frameCount)
                let bin = min(bins - 1, max(0, Int(position * Double(bins))))
                for channel in 0..<channelCount {
                    let sample = Double(channels[channel][frame])
                    energy[bin] += sample * sample
                }
                counts[bin] += channelCount
            }
            frameOffset += AVAudioFramePosition(frames)
        }

        let rms = zip(energy, counts).map { total, count in
            count > 0 ? sqrt(total / Double(count)) : 0
        }
        let maximum = rms.max() ?? 0
        let peaks: [Float] = maximum > 0
            ? rms.map { Float($0 / maximum) }
            : rms.map { _ in 0 }
        return AudioWaveform(
            duration: Double(frameCount) / format.sampleRate,
            peaks: peaks
        )
    }
}

public enum AudioWaveformError: Error, Equatable, Sendable {
    case cannotAllocateBuffer
    case unsupportedSampleFormat
}

/// Disk-backed derived waveform cache. Missing/corrupt entries are rebuilt
/// from the current audio file; cache deletion never affects the recording.
public actor AudioWaveformStore {
    public static let shared = AudioWaveformStore()

    private let cacheDirectory: URL
    private var inFlight: [String: Task<AudioWaveform, Error>] = [:]

    public init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ReadLoop/AudioWaveforms", isDirectory: true)
    }

    public func waveform(for url: URL, cacheKey: String, sampleCount: Int = 240) async throws -> AudioWaveform {
        let key = "\(cacheKey)-\(sampleCount)"
        if let task = inFlight[key] {
            return try await task.value
        }
        let cacheURL = cacheDirectory.appendingPathComponent(key).appendingPathExtension("json")
        let task = Task.detached(priority: .utility) {
            if let data = try? Data(contentsOf: cacheURL),
               let cached = try? JSONDecoder().decode(AudioWaveform.self, from: data) {
                return cached
            }
            let waveform = try AudioWaveformAnalyzer.analyze(url: url, sampleCount: sampleCount)
            try? FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let data = try? JSONEncoder().encode(waveform) {
                try? data.write(to: cacheURL, options: .atomic)
            }
            return waveform
        }
        inFlight[key] = task
        do {
            let waveform = try await task.value
            inFlight[key] = nil
            return waveform
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    public func remove(cacheKey: String, sampleCount: Int = 240) throws {
        let url = cacheDirectory
            .appendingPathComponent("\(cacheKey)-\(sampleCount)")
            .appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func clearAll() throws {
        guard FileManager.default.fileExists(atPath: cacheDirectory.path) else { return }
        try FileManager.default.removeItem(at: cacheDirectory)
    }
}
