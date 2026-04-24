import Foundation
import AVFoundation

/// Decodes any container/codec macOS supports natively (wav, mp3, m4a, aac,
/// flac, alac, caf, aiff, mp4, mov, m4v; mkv/webm/ogg depend on installed
/// system codecs — we use AVURLAsset which accepts whatever AVFoundation can
/// read) into 16 kHz mono Float32 PCM — the format WhisperKit expects.
public struct FileImportService: Sendable {
    public init() {}

    /// Supported drop/pick extensions.
    public static let supportedExtensions: [String] = [
        "wav", "mp3", "m4a", "aac", "flac", "aiff", "aif", "caf",
        "mp4", "mov", "m4v", "mkv", "webm", "ogg", "opus"
    ]

    public struct StreamHandle: Sendable {
        public let samples: AsyncThrowingStream<[Float], Error>
        public let totalFrameEstimate: Int64?
    }

    /// Returns a stream of PCM chunks (~0.5 s each) plus an estimate of total
    /// frames so callers can compute progress. Caller advances through the
    /// stream, pushes chunks into the live streamer, then can snapshot the
    /// full buffer for a final-quality pass.
    public func stream(url: URL) throws -> StreamHandle {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)

        let audioTracks = asset.tracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw NSError(domain: "OAE.FileImport", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File has no decodable audio track."])
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw NSError(domain: "OAE.FileImport", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot attach PCM reader to this file."])
        }
        reader.add(readerOutput)
        reader.startReading()

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let totalFrames: Int64? = durationSeconds.isFinite ? Int64(durationSeconds * 16_000) : nil

        let stream = AsyncThrowingStream<[Float], Error> { continuation in
            Task.detached(priority: .userInitiated) {
                while reader.status == .reading {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else { break }
                    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                        CMSampleBufferInvalidate(sampleBuffer)
                        continue
                    }
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    let floatCount = length / MemoryLayout<Float>.size
                    if floatCount == 0 {
                        CMSampleBufferInvalidate(sampleBuffer)
                        continue
                    }
                    var chunk = [Float](repeating: 0, count: floatCount)
                    let copied: Bool = chunk.withUnsafeMutableBytes { ptr in
                        guard ptr.count >= length, let base = ptr.baseAddress else { return false }
                        _ = CMBlockBufferCopyDataBytes(blockBuffer,
                            atOffset: 0,
                            dataLength: length,
                            destination: base)
                        return true
                    }
                    guard copied else {
                        CMSampleBufferInvalidate(sampleBuffer)
                        continue
                    }
                    CMSampleBufferInvalidate(sampleBuffer)
                    continuation.yield(chunk)
                }
                if reader.status == .failed, let err = reader.error {
                    continuation.finish(throwing: err)
                } else {
                    continuation.finish()
                }
            }
        }

        return StreamHandle(samples: stream, totalFrameEstimate: totalFrames)
    }

    /// Loads the complete file into a single `[Float]`. Used for the final
    /// high-quality pass after the live streaming preview finishes.
    public func loadAll(url: URL) async throws -> [Float] {
        let handle = try stream(url: url)
        var out: [Float] = []
        if let estimate = handle.totalFrameEstimate {
            out.reserveCapacity(Int(estimate))
        }
        for try await chunk in handle.samples {
            out.append(contentsOf: chunk)
        }
        return out
    }
}
