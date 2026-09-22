import Foundation

enum DockDragRemovalPolicy {
    static func canRemove(at point: CGPoint, from frame: CGRect, position: DockPosition,
                          elapsed: TimeInterval, isFixed: Bool, menuBarFrame: CGRect?) -> Bool {
        guard elapsed >= 0.5, !isFixed, menuBarFrame?.contains(point) != true else { return false }
        switch position {
        case .left: return point.x > frame.maxX + frame.width
        case .right: return point.x < frame.minX - frame.width
        case .bottomCenter, .bottomLeft, .bottomRight: return point.y > frame.maxY + frame.height
        }
    }
}
