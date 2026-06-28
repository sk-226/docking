import SwiftUI

struct DockWidgetShell<Content: View>: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @ViewBuilder var content: Content
    @EnvironmentObject private var model: DockingAppModel
    @State private var isHovering = false

    var body: some View {
        let metrics = DockWidgetMetrics(size: model.settings.widgetSize)

        Button(action: action) {
            VStack(spacing: metrics.iconContentSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.iconFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: metrics.iconHeight)
                    .accessibilityHidden(true)

                VStack(spacing: metrics.textSpacing) {
                    content
                }
                // Widget settings are user-controlled, and an earlier 44pt
                // lower bound left too little vertical room for icon + two text
                // lines. Clipping only the content area is deliberate: it keeps
                // the icon from visually colliding with text while still letting
                // long event/weather labels truncate inside their own lines.
                // The alternative, hiding the icon at small sizes, made the
                // Calendar and Weather widgets harder to scan in a dock where
                // icons are the primary visual affordance.
                .frame(maxWidth: .infinity, minHeight: metrics.contentHeight, maxHeight: metrics.contentHeight)
                .clipped()
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(width: model.settings.widgetSize, height: model.settings.widgetSize)
            .background {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    // Widgets should read as compact controls embedded in the
                    // dock surface, not as separate dark cards. A material base
                    // keeps them adaptive, while hover uses a soft accent wash
                    // rather than a hard outline.
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                            .fill(isHovering ? model.settings.accentColor.opacity(0.14) : Color.primary.opacity(0.035))
                    }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .dockTooltip(title)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title) details")
    }
}

struct DockWidgetMetrics {
    let size: Double
    let horizontalPadding: Double
    let verticalPadding: Double
    let iconFontSize: Double
    let iconHeight: Double
    let iconContentSpacing: Double
    let textSpacing: Double
    let contentHeight: Double
    let cornerRadius: Double

    init(size: Double) {
        self.size = max(1, size)

        // The compact widget has a hard vertical budget: outer padding, an SF
        // Symbol row, a gap, then two short text rows. Keeping these numbers in
        // one place makes the invariant testable and prevents future visual
        // tweaks from reintroducing Calendar text/icon overlap at the small end
        // of the user-controlled size range.
        let isTight = self.size < DockingSettingLimits.widgetReadableMinimum
        horizontalPadding = isTight ? 4 : 5
        verticalPadding = isTight ? 3 : 5
        iconFontSize = isTight ? 9 : 11
        iconHeight = isTight ? 9 : 12
        iconContentSpacing = isTight ? 1 : 2
        textSpacing = isTight ? 0 : 2

        // We keep a real content slot instead of letting SwiftUI negotiate the
        // height from fixed fonts. That negotiation was the source of the bug:
        // at small sizes the text kept its ideal height and visually ran into
        // the icon. A fixed slot makes truncation predictable.
        contentHeight = max(0, self.size - (verticalPadding * 2) - iconHeight - iconContentSpacing)
        cornerRadius = min(14, max(10, self.size * 0.24))
    }

    var allocatedHeight: Double {
        verticalPadding * 2 + iconHeight + iconContentSpacing + contentHeight
    }
}
