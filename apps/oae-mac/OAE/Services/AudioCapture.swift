import Foundation
import AVFoundation
import AppKit
import Combine

/// Captures 16 kHz mono Float32 PCM from the default input device using `AVAudioEngine`.
/// Emits samples via a continuous `[Float]` append buffer exposed by `samples` and publishes
/// a low-rate peak-meter for the waveform view. Audio I/O runs on CoreAudio's realtime
/// thread; our tap only does a `convert()` + array append.
@MainActor
public final class AudioCapture: ObservableObject {
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var levels: [Float] = Array(repeating: 0, count: 64)
    @Published public private(set) var error: String?
    @Published public private(set) var micAuthorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    public static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let ringLock = NSLock()
    private var ring: [Float] = []

    /// Snapshot a copy of everything captured since `start()`. Safe to call from the UI thread.
    public func snapshotSamples() -> [Float] {
        ringLock.lock(); defer { ringLock.unlock() }
        return ring
    }

    /// Reset the capture buffer without tearing down the engine.
    public func clearBuffer() {
        ringLock.lock(); ring.removeAll(keepingCapacity: true); ringLock.unlock()
    }

    /// Request mic permission once, early. Safe to call from `@MainActor` — we use the
    /// async variant so the main runloop stays unblocked and the OS prompt's Allow click
    /// is delivered. Returns `true` only when currently authorized.
    @discardableResult
    public static func ensureMicPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Start capturing. Requires mic permission; if it's not yet granted, opens
    /// System Settings and sets `error`.
    public func start() async throws {
        guard !isRecording else { return }
        clearBuffer()

        let granted = await Self.ensureMicPermission()
        micAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
        if !granted {
            openMicSystemSettings()
            throw NSError(domain: "OAE.AudioCapture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Microphone access is required. Enable it in System Settings > Privacy & Security > Microphone, then try again."
            ])
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        converter?.sampleRateConverterQuality = .max

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.handleInput(buffer: buffer, targetFormat: targetFormat)
        }

        try engine.start()
        isRecording = true
    }

    public func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
    }

    private func handleInput(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }
        outBuf.frameLength = 0

        var err: NSError?
        var consumed = false
        let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || status == .endOfStream { return }

        guard let ch = outBuf.floatChannelData?.pointee else { return }
        let n = Int(outBuf.frameLength)
        guard n > 0 else { return }

        let chunk = Array(UnsafeBufferPointer(start: ch, count: n))

        ringLock.lock()
        ring.append(contentsOf: chunk)
        ringLock.unlock()

        let peak = chunk.reduce(Float(0)) { max($0, abs($1)) }
        Task { @MainActor [peak] in
            var l = self.levels
            l.removeFirst()
            l.append(peak)
            self.levels = l
        }
    }

    /// Open the Microphone pane of System Settings so the user can flip the switch without
    /// hunting through menus.
    public func openMicSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
