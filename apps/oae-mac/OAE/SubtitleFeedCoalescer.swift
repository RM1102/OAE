import Combine
import Foundation
import SwiftUI

/// Reads the latest `TranscriptStore` subtitle feed and commits through the compositor at most ~60 Hz on the main actor.
@MainActor
final class SubtitleFeedCoalescer: ObservableObject {
    @Published private(set) var displayedSlots: [String] = []
    @Published private(set) var isRunning: Bool = false

    private weak var transcript: TranscriptStore?
    private var compositor = SubtitleIslandCompositor()
    private var capacity: Int = 15
    private var tick: AnyCancellable?

    private let instrument = SubtitleIslandInstrumentation.shared

    func start(transcript: TranscriptStore, capacity: Int) {
        stop()
        self.transcript = transcript
        self.capacity = max(4, capacity)
        compositor.reset()
        displayedSlots = []
        isRunning = true

        tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.flush()
            }

        flush()
    }

    func stop() {
        tick?.cancel()
        tick = nil
        transcript = nil
        isRunning = false
    }

    func resetCompositor(capacity newCapacity: Int) {
        capacity = max(4, newCapacity)
        compositor.reset()
        flush()
    }

    private func flush() {
        guard isRunning, let transcript else { return }
        let inst = instrument.isEnabled ? instrument : nil
        let isDictate = transcript.source == .dictate
        let session = transcript.subtitleFeedDictateSessionID
        let C = isDictate ? transcript.subtitleConfirmedWords : []
        let V = isDictate ? transcript.subtitleVolatileWords : []

        let (slots, _) = compositor.compose(
            capacity: capacity,
            sessionID: session,
            confirmed: C,
            volatile: V,
            instrument: inst
        )
        displayedSlots = slots
        instrument.recordFlushForHz()
    }
}
