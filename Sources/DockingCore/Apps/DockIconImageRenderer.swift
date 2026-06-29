import AppKit

enum DockIconImageRenderer {
    private static let pointSize = NSSize(width: 256, height: 256)
    private static let backingScale: CGFloat = 2

    static func render(_ draw: (NSRect) -> Void) -> NSImage {
        // The point size is intentionally larger than any current Docking tile.
        // This renderer is for Docking-generated folder previews, not for app
        // icons. App icons already carry native multi-size representations from
        // LaunchServices; flattening them would throw away exactly the fidelity
        // users expect from the Dock. Generated previews need their own 512px
        // backing image because otherwise a 128px composition becomes visibly
        // rough in the always-visible dock, especially after hover scale.
        let pixelsWide = Int(pointSize.width * backingScale)
        let pixelsHigh = Int(pointSize.height * backingScale)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return NSImage(size: pointSize)
        }

        bitmap.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // NSBitmapImageRep's pixel dimensions are larger than the logical point
        // size so generated icons stay sharp on Retina displays. AppKit does
        // not automatically map our 256 pt drawing commands onto the 512 px
        // backing store for this offscreen context, so without this scale the
        // rendered artwork lands in the lower-left quarter and looks both tiny
        // and off-center in the Dock. Scaling the context keeps call sites in
        // point units while using every backing pixel.
        context.cgContext.scaleBy(x: backingScale, y: backingScale)
        context.imageInterpolation = .high
        context.shouldAntialias = true
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: pointSize).fill()
        draw(NSRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: pointSize)
        image.addRepresentation(bitmap)
        return image
    }
}
