import Foundation

struct DockAutoHideAnimation {
    private(set) var fraction: Double
    private(set) var target: Double
    private(set) var duration: TimeInterval = 0
    private var start: Double
    private var elapsed: TimeInterval = 0

    init(hidden: Bool = false) {
        fraction = hidden ? 1 : 0
        target = fraction
        start = fraction
    }

    var isAnimating: Bool { fraction != target }

    static func duration(distance: Double, timeModifier: Double = 1) -> TimeInterval {
        floor(1 + log1p(abs(distance) / 2)) * 0.060 * max(0, timeModifier)
    }

    mutating func setHidden(_ hidden: Bool, distance: Double, timeModifier: Double = 1) {
        let next = hidden ? 1.0 : 0.0
        guard next != target else { return }
        start = fraction
        target = next
        elapsed = 0
        duration = Self.duration(distance: distance, timeModifier: timeModifier)
        if duration == 0 { fraction = target }
    }

    mutating func advance(by interval: TimeInterval) {
        guard isAnimating else { return }
        elapsed = min(duration, elapsed + max(0, interval))
        if elapsed == duration { fraction = target }
        else {
            let eased = (1 - cos(DockMagnificationLens.nativePi * elapsed / duration)) / 2
            fraction = start + (target - start) * eased
        }
    }

    func offset(distance: Double, position: DockPosition) -> CGSize {
        switch position {
        case .left: return CGSize(width: -distance * fraction, height: 0)
        case .right: return CGSize(width: distance * fraction, height: 0)
        case .bottomCenter, .bottomLeft, .bottomRight: return CGSize(width: 0, height: -distance * fraction)
        }
    }
}
