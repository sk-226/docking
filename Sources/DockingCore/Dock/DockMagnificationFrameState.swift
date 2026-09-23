import Foundation

struct DockMagnificationFrameState {
    struct TargetUpdate: Equatable {
        let pointerOffset: Double?
    }

    private var pointerOffset: Double?
    private var needsTargetUpdate = false
    private var previousTargetTimestamp: TimeInterval?
    private var lastInputTime: TimeInterval?

    var hasPendingTarget: Bool { needsTargetUpdate }

    func isTrackingInput(at timestamp: TimeInterval) -> Bool {
        guard pointerOffset != nil, let lastInputTime else { return false }
        return timestamp - lastInputTime < 0.1
    }

    mutating func request(pointerOffset: Double?, at timestamp: TimeInterval = 0) -> Bool {
        let offset = pointerOffset.flatMap { $0.isFinite ? $0 : nil }
        guard offset != self.pointerOffset else { return false }
        self.pointerOffset = offset
        lastInputTime = timestamp
        needsTargetUpdate = true
        return true
    }

    // Mouse events only replace the pending input; the display link consumes it.
    mutating func takeTargetUpdate() -> TargetUpdate? {
        guard needsTargetUpdate else { return nil }
        needsTargetUpdate = false
        return TargetUpdate(pointerOffset: pointerOffset)
    }

    mutating func elapsedTime(timestamp: TimeInterval, targetTimestamp: TimeInterval,
                              currentTime: TimeInterval? = nil) -> TimeInterval {
        let presentationTime = max(targetTimestamp, currentTime ?? targetTimestamp)
        let previous = previousTargetTimestamp ?? (presentationTime - max(0, targetTimestamp - timestamp))
        previousTargetTimestamp = max(previous, presentationTime)
        return max(0, presentationTime - previous)
    }

    mutating func resetClock() {
        previousTargetTimestamp = nil
    }
}
