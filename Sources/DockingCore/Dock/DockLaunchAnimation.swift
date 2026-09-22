import Foundation

struct DockLaunchAnimation {
    private(set) var elapsed = 0.0
    private var end = 120.0
    var isAnimating: Bool { elapsed < end }

    var value: Double {
        guard isAnimating else { return 0 }
        let halfPeriod: Float = 350
        let phase = Float((elapsed * 1_000 + Double(halfPeriod)).truncatingRemainder(dividingBy: Double(2 * halfPeriod)))
        let reflected = phase > halfPeriod ? 2 * halfPeriod - phase : phase
        return Double(1 - reflected * reflected / (halfPeriod * halfPeriod))
    }

    mutating func finish() {
        end = min(end, (floor(elapsed / 0.7) + 1) * 0.7)
    }

    mutating func advance(by interval: TimeInterval) {
        elapsed = min(end, elapsed + max(0, interval))
    }

    static func height(iconSize: Double) -> Double {
        Double(Float(6).addingProduct(Float(iconSize) - 8, Float(bitPattern: 0x3e4ccccd)))
    }

    static func offset(value: Double, iconSize: Double, position: DockPosition) -> CGSize {
        let distance = height(iconSize: iconSize) * value
        switch position {
        case .left: return CGSize(width: distance, height: 0)
        case .right: return CGSize(width: -distance, height: 0)
        case .bottomCenter, .bottomLeft, .bottomRight: return CGSize(width: 0, height: -distance)
        }
    }
}
