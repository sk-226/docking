import AppKit
import Foundation
import SwiftUI

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension View {
    func dockTooltip(_ text: String) -> some View {
        // macOS exposes help text as a native tooltip. Keeping this as a tiny
        // wrapper makes icon-only controls understandable without adding visible
        // instructional copy to the dock itself.
        help(text)
    }

    func dockingSurface(settings: DockingSettings, cornerRadius: Double? = nil) -> some View {
        modifier(DockingSurfaceModifier(settings: settings, cornerRadius: cornerRadius))
    }
}

private struct DockingSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let settings: DockingSettings
    let cornerRadius: Double?

    func body(content: Content) -> some View {
        let radius = cornerRadius ?? settings.cornerRadius
        let strength = min(max(settings.materialStrength, 0), 1)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .background {
                // Keep the dock rooted in AppKit/SwiftUI system materials. A
                // hand-painted translucent black rectangle looks harsh on macOS,
                // and it is the reason the previous dock read as having a black
                // outline. The neutral fill is only a damping layer for the
                // user-facing "material strength" setting; it never replaces the
                // native material as the base surface.
                shape.fill(systemMaterial)
                    .opacity(settings.opacity)
                shape.fill(Color(nsColor: .controlBackgroundColor).opacity((1 - strength) * 0.28))

                // Accent color belongs inside the glass, not on the outer edge.
                // A colored border makes the dock look like custom web chrome;
                // this soft tint keeps the setting visible while preserving an
                // Apple-like system surface.
                shape.fill(settings.accentColor.opacity(0.035 * strength))
            }
            .clipShape(shape)
            .overlay {
                // This is an inner highlight, not a frame. Using a light,
                // adaptive hairline avoids the black rim that appeared when the
                // border/shadow stack was darker than the material underneath.
                shape.strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.52),
                    lineWidth: 0.6
                )
                .blendMode(.plusLighter)
            }
    }

    private var systemMaterial: Material {
        // The named presets should be visibly different, not just numerically
        // different. Keeping all three on `.thinMaterial` made "Liquid Glass"
        // feel like a label that barely changed anything. These are still
        // system materials, so the dock remains adaptive instead of becoming a
        // hand-painted translucent rectangle.
        switch settings.liquidGlassSurfaceStyle {
        case .clear:
            return .ultraThinMaterial
        case .balanced:
            return .thinMaterial
        case .dense:
            return .regularMaterial
        }
    }
}

extension ThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

extension DockingAccentColor {
    var color: Color {
        switch self {
        case .blue:
            return .blue
        case .teal:
            return .teal
        case .green:
            return .green
        case .amber:
            return .orange
        case .red:
            return .red
        case .pink:
            return .pink
        case .purple:
            return .purple
        case .graphite:
            return Color(nsColor: .systemGray)
        }
    }
}

extension DockingSettings {
    var accentColor: Color {
        DockingAccentColor(rawValue: accentColorName)?.color ?? .blue
    }
}

enum AppSupportDirectory {
    static func url() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Docking", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
