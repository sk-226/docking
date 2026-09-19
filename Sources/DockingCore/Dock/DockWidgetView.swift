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
        let vertical = model.settings.dockPosition.isVertical
        let scale = vertical ? min(model.settings.effectiveWidgetScale, width / 36) : model.settings.effectiveWidgetScale
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: 1))
            : AnyLayout(HStackLayout(spacing: 5))

        Button(action: action) {
            layout {
                Image(systemName: systemImage)
                    .symbolRenderingMode(iconStyle.renderingMode)
                    .font(.system(size: vertical ? 16 : min(22, 16 * iconScale), weight: .medium))
                    .modifier(DockWidgetIconForegroundModifier(style: iconStyle))
                    .frame(width: vertical ? nil : 24)
                    .accessibilityHidden(true)
                content
                    .frame(maxWidth: .infinity, alignment: vertical ? .center : .leading)
            }
            .padding(.horizontal, vertical ? 0 : 4)
            .frame(width: width / scale, height: height / scale)
            .scaleEffect(scale, anchor: .center)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
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
