import Foundation

// Mouse deltas continue at a clamped screen edge; arriving there is not a push.
struct DockEdgeIntent {
    static let minimumPush: CGFloat = 5
    static let maximumLateralDrift: CGFloat = 8
    static let pushWindow: TimeInterval = 0.3

    private var targetKey: String?
    private var anchor: CGFloat = 0
    private var push: CGFloat = 0
    private var lastPushTime: TimeInterval?
    private var consumed = false

    mutating func update(targetKey: String?, position: DockPosition, location: CGPoint,
                         delta: CGSize, now: TimeInterval) -> Bool {
        guard let targetKey, location.x.isFinite, location.y.isFinite,
              delta.width.isFinite, delta.height.isFinite, now.isFinite else {
            reset()
            return false
        }
        let lateral = position.isVertical ? location.y : location.x
        if self.targetKey != targetKey {
            reset()
            self.targetKey = targetKey
            anchor = lateral
            return false
        }
        guard !consumed else { return false }

        let outward: CGFloat
        switch position {
        case .bottomCenter, .bottomLeft, .bottomRight: outward = delta.height
        case .left: outward = -delta.width
        case .right: outward = delta.width
        }
        let sideways = position.isVertical ? delta.height : delta.width
        if abs(lateral - anchor) > Self.maximumLateralDrift
            || outward < 0 || abs(sideways) > outward {
            push = 0
            lastPushTime = nil
            anchor = lateral
            return false
        }
        if push < Self.minimumPush,
           let lastPushTime, now - lastPushTime > Self.pushWindow {
            push = 0
        }
        if outward > 0 {
            push += outward
            lastPushTime = now
        }
        return canReveal(targetKey: targetKey, position: position, location: location)
    }

    func canReveal(targetKey: String, position: DockPosition, location: CGPoint) -> Bool {
        let lateral = position.isVertical ? location.y : location.x
        return self.targetKey == targetKey && !consumed && push >= Self.minimumPush
            && abs(lateral - anchor) <= Self.maximumLateralDrift
    }

    mutating func didReveal(targetKey: String) {
        // A reveal can rebuild the edge targets. Consume after that callback,
        // so the same continuous contact cannot schedule another reveal.
        self.targetKey = targetKey
        consumed = true
    }

    mutating func reset() {
        self = Self()
    }
}
