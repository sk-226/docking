#!/usr/bin/env swift

import AppKit
import Foundation

private enum DockingIconRenderer {
    static let canvas: CGFloat = 1024

    static func appIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.saveGState()
        context.scaleBy(x: size / canvas, y: size / canvas)
        drawAppIcon()
        context.restoreGState()

        return image
    }

    static func menuBarTemplate(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.saveGState()
        context.scaleBy(x: size / 36, y: size / 36)
        drawMenuBarGlyph()
        context.restoreGState()

        return image
    }

    private static func drawAppIcon() {
        NSGraphicsContext.current?.imageInterpolation = .high

        let background = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 210, yRadius: 210)
        let backgroundShadow = NSShadow()
        backgroundShadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        backgroundShadow.shadowBlurRadius = 42
        backgroundShadow.shadowOffset = NSSize(width: 0, height: -18)
        backgroundShadow.set()

        // Keep the app icon quiet and system-like. A literal rocket illustration
        // would read as a launcher brand first and a Dock replacement second;
        // this pale rounded-square surface lets the dock shelf remain the main
        // product cue while still giving the icon enough depth for Finder/Dock.
        NSGradient(
            starting: NSColor(red: 0.965, green: 0.980, blue: 1.000, alpha: 1),
            ending: NSColor(red: 0.865, green: 0.910, blue: 0.985, alpha: 1)
        )?.draw(in: background, angle: -36)

        NSShadow().set()
        NSColor.white.withAlphaComponent(0.78).setStroke()
        background.lineWidth = 4
        background.stroke()

        drawExhaust()
        drawShelf()
        drawRocket()
    }

    private static func drawShelf() {
        let shelf = NSBezierPath(roundedRect: NSRect(x: 164, y: 166, width: 696, height: 172), xRadius: 86, yRadius: 86)
        let shelfShadow = NSShadow()
        shelfShadow.shadowColor = NSColor(red: 0.22, green: 0.36, blue: 0.58, alpha: 0.24)
        shelfShadow.shadowBlurRadius = 26
        shelfShadow.shadowOffset = NSSize(width: 0, height: -10)
        shelfShadow.set()

        // The chosen concept is "rocket over a translucent dock shelf". The
        // shelf is intentionally one low pill, not a full macOS Dock clone: a
        // faithful Dock surface would become visual noise at 32px and could
        // imply this app is Apple's Dock instead of a Docking-owned surface.
        NSGradient(
            starting: NSColor.white.withAlphaComponent(0.88),
            ending: NSColor(red: 0.70, green: 0.80, blue: 0.94, alpha: 0.50)
        )?.draw(in: shelf, angle: -90)

        NSShadow().set()
        NSColor.white.withAlphaComponent(0.82).setStroke()
        shelf.lineWidth = 5
        shelf.stroke()

        let tileColors: [(NSColor, NSColor)] = [
            (NSColor(red: 0.74, green: 0.62, blue: 0.98, alpha: 1), NSColor(red: 0.55, green: 0.45, blue: 0.86, alpha: 1)),
            (NSColor(red: 0.49, green: 0.68, blue: 0.96, alpha: 1), NSColor(red: 0.30, green: 0.52, blue: 0.86, alpha: 1)),
            (NSColor(red: 0.43, green: 0.80, blue: 0.79, alpha: 1), NSColor(red: 0.30, green: 0.64, blue: 0.66, alpha: 1)),
            (NSColor(red: 0.77, green: 0.80, blue: 0.86, alpha: 1), NSColor(red: 0.56, green: 0.60, blue: 0.68, alpha: 1))
        ]

        for (index, colors) in tileColors.enumerated() {
            let x = 258 + CGFloat(index) * 128
            let tile = NSBezierPath(roundedRect: NSRect(x: x, y: 214, width: 88, height: 88), xRadius: 24, yRadius: 24)
            let shadow = NSShadow()
            shadow.shadowColor = colors.1.withAlphaComponent(0.38)
            shadow.shadowBlurRadius = 13
            shadow.shadowOffset = NSSize(width: 0, height: -5)
            shadow.set()
            NSGradient(starting: colors.0, ending: colors.1)?.draw(in: tile, angle: -55)

            NSShadow().set()
            NSColor.white.withAlphaComponent(0.70).setStroke()
            tile.lineWidth = 3
            tile.stroke()
        }
    }

    private static func drawRocket() {
        let rocket = NSBezierPath()
        rocket.move(to: NSPoint(x: 512, y: 824))
        rocket.curve(to: NSPoint(x: 454, y: 594), controlPoint1: NSPoint(x: 450, y: 768), controlPoint2: NSPoint(x: 426, y: 684))
        rocket.curve(to: NSPoint(x: 386, y: 492), controlPoint1: NSPoint(x: 418, y: 572), controlPoint2: NSPoint(x: 392, y: 536))
        rocket.curve(to: NSPoint(x: 492, y: 556), controlPoint1: NSPoint(x: 430, y: 500), controlPoint2: NSPoint(x: 466, y: 520))
        rocket.line(to: NSPoint(x: 492, y: 510))
        rocket.curve(to: NSPoint(x: 532, y: 510), controlPoint1: NSPoint(x: 492, y: 488), controlPoint2: NSPoint(x: 532, y: 488))
        rocket.line(to: NSPoint(x: 532, y: 556))
        rocket.curve(to: NSPoint(x: 638, y: 492), controlPoint1: NSPoint(x: 558, y: 520), controlPoint2: NSPoint(x: 594, y: 500))
        rocket.curve(to: NSPoint(x: 570, y: 594), controlPoint1: NSPoint(x: 632, y: 536), controlPoint2: NSPoint(x: 606, y: 572))
        rocket.curve(to: NSPoint(x: 512, y: 824), controlPoint1: NSPoint(x: 598, y: 684), controlPoint2: NSPoint(x: 574, y: 768))
        rocket.close()

        let rocketShadow = NSShadow()
        rocketShadow.shadowColor = NSColor(red: 0.03, green: 0.07, blue: 0.14, alpha: 0.34)
        rocketShadow.shadowBlurRadius = 16
        rocketShadow.shadowOffset = NSSize(width: 0, height: -8)
        rocketShadow.set()

        // The silhouette is one filled shape so the icon survives very small
        // sizes. Keeping fins and body merged also avoids a cartoony "toy
        // rocket" read, which would fight the simple utility feel of Docking.
        NSGradient(
            starting: NSColor(red: 0.12, green: 0.21, blue: 0.38, alpha: 1),
            ending: NSColor(red: 0.04, green: 0.07, blue: 0.13, alpha: 1)
        )?.draw(in: rocket, angle: -90)

        NSShadow().set()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        rocket.lineWidth = 3
        rocket.stroke()

        let window = NSBezierPath(ovalIn: NSRect(x: 480, y: 662, width: 64, height: 64))
        NSColor.white.withAlphaComponent(0.96).setFill()
        window.fill()
    }

    private static func drawExhaust() {
        let beam = NSBezierPath()
        beam.move(to: NSPoint(x: 490, y: 560))
        beam.curve(to: NSPoint(x: 392, y: 340), controlPoint1: NSPoint(x: 455, y: 500), controlPoint2: NSPoint(x: 415, y: 420))
        beam.curve(to: NSPoint(x: 632, y: 340), controlPoint1: NSPoint(x: 470, y: 314), controlPoint2: NSPoint(x: 554, y: 314))
        beam.curve(to: NSPoint(x: 534, y: 560), controlPoint1: NSPoint(x: 609, y: 420), controlPoint2: NSPoint(x: 569, y: 500))
        beam.close()

        NSColor(red: 0.35, green: 0.62, blue: 1.0, alpha: 0.22).setFill()
        beam.fill()

        let center = NSBezierPath()
        center.move(to: NSPoint(x: 504, y: 560))
        center.curve(to: NSPoint(x: 472, y: 346), controlPoint1: NSPoint(x: 492, y: 482), controlPoint2: NSPoint(x: 474, y: 420))
        center.curve(to: NSPoint(x: 552, y: 346), controlPoint1: NSPoint(x: 500, y: 334), controlPoint2: NSPoint(x: 524, y: 334))
        center.curve(to: NSPoint(x: 520, y: 560), controlPoint1: NSPoint(x: 550, y: 420), controlPoint2: NSPoint(x: 532, y: 482))
        center.close()

        NSColor(red: 0.82, green: 0.92, blue: 1.0, alpha: 0.38).setFill()
        center.fill()
    }

    private static func drawMenuBarGlyph() {
        NSColor.black.setFill()

        // TODO(icon-design): Treat this menu-bar rocket as WIP. The current
        // mark is intentionally simple so it remains legible as a template
        // status icon, but the final brand direction is still unsettled. Keep
        // this renderer easy to replace rather than tuning tiny curve points as
        // if this were the permanent design.
        // The menu bar version is a brand glyph, not a miniature copy of the
        // app icon. A straight vertical rocket reads like a sword in the menu
        // bar, so this one is drawn as a larger diagonal silhouette. The single
        // oversized porthole is the only cut-out we keep: it is large enough to
        // survive template rendering and is the cue that distinguishes the mark
        // from an arrow, upload icon, or blade.
        NSGraphicsContext.current?.cgContext.saveGState()
        NSGraphicsContext.current?.cgContext.translateBy(x: 1.0, y: -1.2)
        NSGraphicsContext.current?.cgContext.translateBy(x: 18, y: 18)
        NSGraphicsContext.current?.cgContext.scaleBy(x: 1.08, y: 1.08)
        NSGraphicsContext.current?.cgContext.rotate(by: -.pi / 5.2)
        NSGraphicsContext.current?.cgContext.translateBy(x: -18, y: -18)

        let rocket = NSBezierPath()
        rocket.move(to: NSPoint(x: 18, y: 33))
        rocket.curve(to: NSPoint(x: 10.8, y: 17.6), controlPoint1: NSPoint(x: 11.8, y: 28.4), controlPoint2: NSPoint(x: 9.4, y: 23.0))
        rocket.curve(to: NSPoint(x: 5.6, y: 11.6), controlPoint1: NSPoint(x: 7.8, y: 16.1), controlPoint2: NSPoint(x: 5.9, y: 14.1))
        rocket.curve(to: NSPoint(x: 14.8, y: 14.7), controlPoint1: NSPoint(x: 9.2, y: 11.7), controlPoint2: NSPoint(x: 12.0, y: 12.7))
        rocket.line(to: NSPoint(x: 14.8, y: 7.2))
        rocket.curve(to: NSPoint(x: 21.2, y: 7.2), controlPoint1: NSPoint(x: 14.8, y: 5.4), controlPoint2: NSPoint(x: 21.2, y: 5.4))
        rocket.line(to: NSPoint(x: 21.2, y: 14.7))
        rocket.curve(to: NSPoint(x: 30.4, y: 11.6), controlPoint1: NSPoint(x: 24.0, y: 12.7), controlPoint2: NSPoint(x: 26.8, y: 11.7))
        rocket.curve(to: NSPoint(x: 25.2, y: 17.6), controlPoint1: NSPoint(x: 30.1, y: 14.1), controlPoint2: NSPoint(x: 28.2, y: 16.1))
        rocket.curve(to: NSPoint(x: 18, y: 33), controlPoint1: NSPoint(x: 26.6, y: 23.0), controlPoint2: NSPoint(x: 24.2, y: 28.4))
        rocket.close()
        rocket.fill()

        let window = NSBezierPath(ovalIn: NSRect(x: 15.2, y: 23.0, width: 5.6, height: 5.6))
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        window.fill()
        NSGraphicsContext.current?.cgContext.restoreGState()
    }
}

private func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "DockingIconRender", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode \(url.lastPathComponent)"])
    }

    try data.write(to: url, options: .atomic)
}

private func render() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let resources = root.appendingPathComponent("Resources", isDirectory: true)
    let iconset = resources.appendingPathComponent("DockingAppIcon.iconset", isDirectory: true)
    let icns = resources.appendingPathComponent("DockingAppIcon.icns")

    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: iconset.path) {
        try FileManager.default.removeItem(at: iconset)
    }
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    let sizes: [(String, CGFloat)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for (name, size) in sizes {
        try writePNG(DockingIconRenderer.appIcon(size: size), to: iconset.appendingPathComponent(name))
    }

    try writePNG(DockingIconRenderer.menuBarTemplate(size: 36), to: resources.appendingPathComponent("DockingMenuBarTemplate.png"))

    if FileManager.default.fileExists(atPath: icns.path) {
        try FileManager.default.removeItem(at: icns)
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try iconutil.run()
    iconutil.waitUntilExit()

    guard iconutil.terminationStatus == 0 else {
        throw NSError(domain: "DockingIconRender", code: Int(iconutil.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }

    print("Rendered \(icns.path)")
}

do {
    try render()
} catch {
    fputs("Icon render failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
