import Foundation

// SwiftUI coordinates: y grows downwards.
enum DockSurfaceGeometry {
    static func frame(in bounds: CGRect, size: CGSize, position: DockPosition) -> CGRect {
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        switch position {
        case .bottomCenter, .bottomLeft, .bottomRight:
            return CGRect(x: bounds.midX - width / 2, y: bounds.maxY - height, width: width, height: height)
        case .left:
            return CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: width, height: height)
        case .right:
            return CGRect(x: bounds.maxX - width, y: bounds.midY - height / 2, width: width, height: height)
        }
    }
}
