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
        dockingSurface(settings: settings, in: RoundedRectangle(cornerRadius: cornerRadius ?? settings.cornerRadius, style: .continuous))
    }

    func dockingSurface<S: Shape>(settings: DockingSettings, in shape: S) -> some View {
        modifier(DockingSurfaceModifier(settings: settings, shape: shape))
    }
}

private struct DockingSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let settings: DockingSettings
    let shape: S

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.regularMaterial, in: shape)
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        switch settings.liquidGlassSurfaceStyle {
        case .clear: return .clear
        case .balanced: return .regular
        case .dense: return .regular.tint(Color(nsColor: .controlBackgroundColor).opacity(0.18))
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
