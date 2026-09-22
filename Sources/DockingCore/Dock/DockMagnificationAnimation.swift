import Foundation

struct DockMagnificationAnimation {
    private(set) var value = 0.0
    private(set) var duration: TimeInterval = 0
    private var start = 0.0
    private var target = 0.0
    private var elapsed: TimeInterval = 0

    var isAnimating: Bool { value != target }

    mutating func setActive(_ active: Bool, maximumGrowth: Double) {
        let next = active ? 1.0 : 0.0
        guard next != target else { return }
        start = value
        target = next
        elapsed = 0
        duration = floor(1 + 42 * log1p(max(0, maximumGrowth) * abs(target - start) / 2)) / 1_000
    }

    @discardableResult
    mutating func advance(by interval: TimeInterval) -> Double {
        guard isAnimating else { return value }
        elapsed = min(duration, elapsed + max(0, interval))
        if elapsed == duration {
            value = target
        } else {
            let progress = (1 - cos(DockMagnificationLens.nativePi * elapsed / duration)) / 2
            value = start + (target - start) * progress
        }
        return value
    }
}
