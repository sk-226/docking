import AppKit
import XCTest
@testable import DockingCore

final class DockItemInteractionTests: XCTestCase {
    func testNativeFivePointThresholdUsesEachAxisRatherThanEuclideanDistance() {
        let start = CGPoint(x: -1200, y: 80)
        for offset in [CGPoint.zero, CGPoint(x: 5, y: 5), CGPoint(x: -5, y: -5), CGPoint(x: 4.9, y: 4.9)] {
            XCTAssertFalse(DockItemInteractionView.shouldBeginDrag(from: start, to: CGPoint(x: start.x + offset.x, y: start.y + offset.y)))
        }
        XCTAssertTrue(DockItemInteractionView.shouldBeginDrag(from: start, to: CGPoint(x: start.x + 5.001, y: start.y)))
        XCTAssertTrue(DockItemInteractionView.shouldBeginDrag(from: start, to: CGPoint(x: start.x, y: start.y - 5.001)))
    }
    @MainActor
    func testIconImageIsRetainedAcrossMagnificationFrames() throws {
        let image = try XCTUnwrap(NSImage(systemSymbolName: "square.fill", accessibilityDescription: nil))
        let view = DockItemInteractionView(frame: CGRect(x: 0, y: 0, width: 36, height: 42))
        view.updateIcon(image: image, size: 36, maximumSize: 128, position: .bottomCenter, launchProgress: 0,
                        isRunning: true, isDragged: false, indicatorColor: .black)
        let icon = try XCTUnwrap(view.layer?.sublayers?.first)
        let contents = try XCTUnwrap(icon.contents as AnyObject?)
        for size in [36.1, 48, 64, 79, 36] {
            view.setFrameSize(CGSize(width: size, height: size + 6))
            view.updateIcon(image: image, size: size, maximumSize: 128, position: .bottomCenter, launchProgress: 0,
                            isRunning: true, isDragged: false, indicatorColor: .black)
            XCTAssertTrue(icon.contents as AnyObject? === contents)
            XCTAssertEqual(icon.frame.width, size, accuracy: 1e-9)
            XCTAssertEqual(icon.frame.maxY, size + 0.5, accuracy: 1e-9)
        }
    }

    @MainActor
    func testLaunchAndDragFeedbackLeaveTheRunningIndicatorAtTheScreenEdge() throws {
        let image = try XCTUnwrap(NSImage(systemSymbolName: "square.fill", accessibilityDescription: nil))
        for position in [DockPosition.bottomCenter, .left, .right] {
            let view = DockItemInteractionView(frame: CGRect(x: 0, y: 0,
                                                             width: position.isVertical ? 42 : 36,
                                                             height: position.isVertical ? 36 : 42))
            view.updateIcon(image: image, size: 36, maximumSize: 128, position: position, launchProgress: 0,
                            isRunning: true, isDragged: false, indicatorColor: .black)
            let layers = try XCTUnwrap(view.layer?.sublayers)
            XCTAssertEqual(layers.count, 2)
            let iconFrame = layers[0].frame
            let dotFrame = layers[1].frame
            view.updateIcon(image: image, size: 36, maximumSize: 128, position: position, launchProgress: 1,
                            isRunning: true, isDragged: false, indicatorColor: .black)
            let offset = DockLaunchAnimation.offset(value: 1, iconSize: 36, position: position)
            XCTAssertEqual(layers[0].frame, iconFrame.offsetBy(dx: offset.width, dy: offset.height))
            XCTAssertEqual(layers[1].frame, dotFrame)
            XCTAssertFalse(layers[1].isHidden)
            view.updateIcon(image: image, size: 36, maximumSize: 128, position: position, launchProgress: 0,
                            isRunning: true, isDragged: true, indicatorColor: .black)
            XCTAssertTrue(layers[0].isHidden)
            XCTAssertFalse(layers[1].isHidden)
        }
    }

    @MainActor
    func testAppIconRetainsEnoughPixelsForMaximumMagnification() throws {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 128, height: 134),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.close() }
        let view = DockItemInteractionView(frame: CGRect(x: 0, y: 0, width: 128, height: 134))
        let image = NSWorkspace.shared.icon(forFile: "/System/Applications/Calculator.app")
        view.updateIcon(image: image, size: 128, position: .bottomCenter, launchProgress: 0,
                        isRunning: false, isDragged: false, indicatorColor: .black)
        window.contentView = view
        let contents = try XCTUnwrap(view.layer?.sublayers?.first?.contents)
        guard CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
            return XCTFail("Expected a decoded icon image")
        }
        let raster = contents as! CGImage
        XCTAssertGreaterThanOrEqual(raster.width, Int(ceil(128 * window.backingScaleFactor)))
        XCTAssertGreaterThanOrEqual(raster.height, Int(ceil(128 * window.backingScaleFactor)))
    }

    @MainActor
    func testMagnifiedIconUsesTheHighResolutionImageRepresentation() throws {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        for (pixels, color) in [(32, NSColor.red), (256, NSColor.blue)] {
            let context = try XCTUnwrap(CGContext(data: nil, width: pixels, height: pixels,
                                                  bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            let representation = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
            representation.size = image.size
            image.addRepresentation(representation)
        }
        let view = DockItemInteractionView(frame: CGRect(x: 0, y: 0, width: 36, height: 42))
        view.updateIcon(image: image, size: 36, maximumSize: 128, position: .bottomCenter, launchProgress: 0,
                        isRunning: false, isDragged: false, indicatorColor: .black)
        let contents = try XCTUnwrap(view.layer?.sublayers?.first?.contents)
        guard CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
            return XCTFail("Expected a decoded icon image")
        }
        let raster = contents as! CGImage
        let bitmap = NSBitmapImageRep(cgImage: raster)
        let color = try XCTUnwrap(bitmap.colorAt(x: raster.width / 2, y: raster.height / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.blueComponent, 0.9)
        XCTAssertLessThan(color.redComponent, 0.1)
    }

}
