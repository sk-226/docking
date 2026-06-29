import SwiftUI

struct DockWidgetShell<Content: View>: View {
    let title: String
    let systemImage: String
    let iconStyle: DockWidgetIconStyle
    let iconScale: Double
    let width: Double
    let height: Double
    let action: () -> Void
    @ViewBuilder var content: Content
    @EnvironmentObject private var model: DockingAppModel
    @State private var isHovering = false

    init(
        title: String,
        systemImage: String,
        iconStyle: DockWidgetIconStyle = .neutral,
        iconScale: Double = 1,
        width: Double,
        height: Double,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.iconStyle = iconStyle
        self.iconScale = iconScale
        self.width = width
        self.height = height
        self.action = action
        self.content = content()
    }

    var body: some View {
        let metrics = DockWidgetMetrics(width: width, height: height)
        let effectiveIconScale = metrics.usesHorizontalLayout ? iconScale : 1
        let contentAlignment: HorizontalAlignment = metrics.usesHorizontalLayout ? .leading : .center
        let contentFrameAlignment: Alignment = metrics.usesHorizontalLayout ? .leading : .center

        Button(action: action) {
            let layout = metrics.usesHorizontalLayout
                ? AnyLayout(HStackLayout(alignment: .center, spacing: metrics.iconContentSpacing))
                : AnyLayout(VStackLayout(spacing: metrics.iconContentSpacing))

            layout {
                Image(systemName: systemImage)
                    .symbolRenderingMode(iconStyle.renderingMode)
                    .font(.system(size: metrics.iconFontSize * effectiveIconScale, weight: .medium))
                    .modifier(DockWidgetIconForegroundModifier(style: iconStyle))
                    .frame(
                        width: metrics.iconExtent * effectiveIconScale,
                        height: metrics.iconExtent * effectiveIconScale
                    )
                    .accessibilityHidden(true)

                VStack(alignment: contentAlignment, spacing: metrics.textSpacing) {
                    content
                }
                // Widget width can grow to two or three app-icon slots, but
                // the Dock height remains constrained. A fixed content budget
                // keeps the icon from competing with text; wide widgets switch
                // to a horizontal layout so extra width becomes real
                // information density instead of empty square area.
                .frame(
                    maxWidth: .infinity,
                    minHeight: metrics.contentHeight,
                    maxHeight: metrics.contentHeight,
                    alignment: contentFrameAlignment
                )
                .clipped()
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(width: width, height: height)
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

struct DockWidgetIconStyle {
    let renderingMode: SymbolRenderingMode
    let foreground: DockWidgetIconForeground

    static let neutral = DockWidgetIconStyle(
        renderingMode: .monochrome,
        foreground: .palette(.gray, .gray)
    )

    static let systemMulticolor = DockWidgetIconStyle(
        renderingMode: .multicolor,
        foreground: .system
    )

    static let calendar = DockWidgetIconStyle(
        renderingMode: .palette,
        // Calendar needs a stronger identity than the neutral gray default,
        // but Docking should not mimic or bundle Apple's Calendar.app artwork.
        // A red SF Symbol palette gives the expected macOS calendar cue while
        // keeping the widget clearly inside Docking's own UI system.
        foreground: .palette(.red, .gray)
    )
}

enum DockWidgetIconForeground {
    case system
    case palette(Color, Color)
}

private struct DockWidgetIconForegroundModifier: ViewModifier {
    let style: DockWidgetIconStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style.foreground {
        case .system:
            // Multicolor SF Symbols already carry Apple-designed semantic
            // color. Applying our own foreground style would flatten that back
            // into a custom palette, which is exactly what makes small weather
            // icons feel less native.
            content
        case .palette(let primary, let secondary):
            content.foregroundStyle(primary, secondary)
        }
    }
}

struct DockWidgetLine: View {
    let text: String
    let font: Font
    let isSecondary: Bool

    init(_ text: String, font: Font, isSecondary: Bool = false) {
        self.text = text
        self.font = font
        self.isSecondary = isSecondary
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(isSecondary ? .secondary : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .truncationMode(.tail)
    }
}

struct DockWidgetMetrics {
    let width: Double
    let height: Double
    let horizontalPadding: Double
    let verticalPadding: Double
    let iconFontSize: Double
    let iconExtent: Double
    let iconContentSpacing: Double
    let textSpacing: Double
    let contentHeight: Double
    let cornerRadius: Double
    let usesHorizontalLayout: Bool

    init(width: Double, height: Double? = nil) {
        self.width = max(1, width)
        self.height = max(1, height ?? width)

        // The compact widget has a hard vertical budget: outer padding, an SF
        // Symbol row, a gap, then two short text rows. Keeping these numbers in
        // one place makes the invariant testable and prevents future visual
        // tweaks from reintroducing Calendar text/icon overlap at the small end
        // of the user-controlled size range.
        usesHorizontalLayout = self.width >= self.height * 1.45
        let isTight = self.height < DockingSettingLimits.widgetReadableMinimum
        horizontalPadding = isTight ? 4 : 5
        verticalPadding = isTight ? 3 : 5
        iconFontSize = usesHorizontalLayout ? 13 : (isTight ? 9 : 11)
        iconExtent = usesHorizontalLayout ? 18 : (isTight ? 9 : 12)
        iconContentSpacing = usesHorizontalLayout ? 5 : (isTight ? 1 : 2)
        textSpacing = isTight ? 0 : 2

        // We keep a real content slot instead of letting SwiftUI negotiate the
        // height from fixed fonts. That negotiation was the source of the bug:
        // at small sizes the text kept its ideal height and visually ran into
        // the icon. A fixed slot makes truncation predictable.
        if usesHorizontalLayout {
            contentHeight = max(0, self.height - (verticalPadding * 2))
        } else {
            contentHeight = max(0, self.height - (verticalPadding * 2) - iconExtent - iconContentSpacing)
        }
        cornerRadius = min(14, max(10, self.height * 0.24))
    }

    var allocatedHeight: Double {
        if usesHorizontalLayout {
            return verticalPadding * 2 + contentHeight
        }
        return verticalPadding * 2 + iconExtent + iconContentSpacing + contentHeight
    }
}
