import Foundation

struct DockMagnificationFrameState {
    struct TargetUpdate: Equatable {
        let pointerOffset: Double?
    }

    private var pointerOffset: Double?
    private var needsTargetUpdate = false
    private var previousTargetTimestamp: TimeInterval?

    mutating func request(pointerOffset: Double?) -> Bool {
        let offset = pointerOffset.flatMap { $0.isFinite ? $0 : nil }
        guard offset != self.pointerOffset else { return false }
        self.pointerOffset = offset
        needsTargetUpdate = true
        return true
    }

    // Mouse events only replace the pending input; the display link consumes it.
    mutating func takeTargetUpdate() -> TargetUpdate? {
        guard needsTargetUpdate else { return nil }
        needsTargetUpdate = false
        return TargetUpdate(pointerOffset: pointerOffset)
    }

    mutating func elapsedTime(timestamp: TimeInterval, targetTimestamp: TimeInterval) -> TimeInterval {
        let previous = previousTargetTimestamp ?? timestamp
        previousTargetTimestamp = targetTimestamp
        return max(0, targetTimestamp - previous)
    }

    mutating func resetClock() {
        previousTargetTimestamp = nil
    }
}
