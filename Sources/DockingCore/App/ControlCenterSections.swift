import AppKit
import SwiftUI

struct GeneralControlCenterSection: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("General")
                    .font(.headline)

                ControlCenterSettingsGroup("Startup") {
                    Toggle(
                        "Launch at login",
                        isOn: Binding(
                            get: { model.settings.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    ControlCenterHelpText(model.launchAtLoginStatusMessage)
                    Toggle("Show menu bar icon", isOn: $model.settings.showMenuBarIcon)
                }

                ControlCenterSettingsGroup("Dock behavior") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        GridRow {
                            Text("Visibility")
                                .frame(width: 150, alignment: .leading)
                            Picker("Dock visibility", selection: $model.settings.dockVisibility) {
                                ForEach(DockVisibilityMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 240, alignment: .leading)
                        }

                        if model.settings.dockVisibility == .autoHide {
                            GridRow {
                                Text("Hide delay")
                                    .frame(width: 150, alignment: .leading)
                                HStack(spacing: 10) {
                                    Slider(
                                        value: $model.settings.autoHideDelay,
                                        in: DockingSettingLimits.autoHideDelay,
                                        step: DockingSettingLimits.autoHideDelayStep
                                    )
                                    .frame(width: 240)
                                    Text(DockingFormatters.seconds(model.settings.autoHideDelay))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 64, alignment: .trailing)
                                }
                            }
                        }

                        GridRow {
                            Color.clear
                                .frame(width: 1, height: 1)
                            Button("Match Apple Dock visibility") {
                                model.matchAppleDockVisibility()
                            }
                        }
                    }
                    ControlCenterHelpText(model.appleDockVisibilityStatusMessage)
                }

                ControlCenterSettingsGroup("Placement") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        GridRow {
                            Text("Dock edge")
                                .frame(width: 150, alignment: .leading)
                            Picker("Dock edge", selection: dockEdge) {
                                ForEach(DockEdgeChoice.allCases) { edge in
                                    Text(edge.label).tag(edge)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 240, alignment: .leading)
                        }

                        if model.settings.dockPosition.isBottom {
                            GridRow {
                                Text("Bottom alignment")
                                    .frame(width: 150, alignment: .leading)
                                Picker("Bottom alignment", selection: bottomAlignment) {
                                    ForEach(BottomDockAlignment.allCases) { alignment in
                                        Text(alignment.label).tag(alignment)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 240, alignment: .leading)
                            }
                        }

                        GridRow {
                            Text("Placement display")
                                .frame(width: 150, alignment: .leading)
                            Picker("Placement display", selection: $model.settings.displayMode) {
                                ForEach(DockDisplayMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 240, alignment: .leading)
                        }
                    }

                    if model.settings.displayMode == .specific {
                        Picker(
                            "Selected display",
                            selection: Binding(
                                get: { model.settings.dockDisplayID ?? model.availableDisplays.first?.id ?? 0 },
                                set: { model.settings.dockDisplayID = $0 == 0 ? nil : $0 }
                            )
                        ) {
                            ForEach(model.availableDisplays) { display in
                                Text("\(display.name) · \(display.frameDescription)").tag(display.id)
                            }
                        }
                    }
                    ControlCenterHelpText(placementHelpText)
                }

                ControlCenterSettingsGroup("Spaces") {
                    Toggle("Keep above app windows", isOn: $model.settings.keepAboveOtherWindows)
                    Toggle("Available on every desktop", isOn: $model.settings.showOnAllSpaces)
                    Toggle("Available over full-screen apps", isOn: $model.settings.showOnFullScreenSpaces)
                    ControlCenterHelpText("These options control whether Docking behaves like system chrome or like an ordinary app overlay.")
                }

                ControlCenterSettingsGroup("Running apps") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        GridRow {
                            Text("Apps not pinned")
                                .frame(width: 150, alignment: .leading)
                            Picker("Apps not pinned", selection: $model.settings.unpinnedRunningAppVisibility) {
                                ForEach(UnpinnedRunningAppVisibility.allCases) { visibility in
                                    Text(visibility.label).tag(visibility)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 240, alignment: .leading)
                        }
                    }
                    ControlCenterHelpText("Open apps that are not permanently kept in Docking can appear in a separated running-app area, or stay hidden until you pin them.")
                }
            }
            .padding()
            .frame(maxWidth: 560, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dockEdge: Binding<DockEdgeChoice> {
        Binding(
            get: { DockEdgeChoice(position: model.settings.dockPosition) },
            set: { edge in
                // The renderer still wants one concrete DockPosition, but users
                // reason about this as two separate questions: which screen edge
                // owns the dock, and how a bottom dock is aligned. Splitting the
                // controls avoids a misleading "Position" menu where "Bottom
                // center" appears to decide multi-display behavior even though
                // bottom auto-hide intentionally reveals from every display.
                switch edge {
                case .bottom:
                    model.settings.dockPosition = bottomAlignment.wrappedValue.position
                case .left:
                    model.settings.dockPosition = .left
                case .right:
                    model.settings.dockPosition = .right
                }
            }
        )
    }

    private var bottomAlignment: Binding<BottomDockAlignment> {
        Binding(
            get: { BottomDockAlignment(position: model.settings.dockPosition) },
            set: { alignment in
                model.settings.dockPosition = alignment.position
            }
        )
    }

    private var placementHelpText: String {
        if model.settings.dockPosition.isBottom, model.settings.dockVisibility == .autoHide {
            return "Bottom auto-hide can be revealed from the bottom edge of every display. Placement display sets the default anchor before a reveal and for manual Show Dock."
        }

        if model.settings.dockPosition.isBottom {
            return "Placement display sets where the always-visible bottom dock stays."
        }

        return "Side docks stay on one display so their edge trigger does not intercept gestures on every monitor."
    }
}

private struct ControlCenterSettingsGroup<Content: View>: View {
    let title: String
    private let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }
}

private struct ControlCenterHelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum DockEdgeChoice: String, CaseIterable, Identifiable {
    case bottom
    case left
    case right

    var id: String { rawValue }

    init(position: DockPosition) {
        switch position {
        case .bottomCenter, .bottomLeft, .bottomRight:
            self = .bottom
        case .left:
            self = .left
        case .right:
            self = .right
        }
    }

    var label: String {
        switch self {
        case .bottom:
            return "Bottom"
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }
}

private enum BottomDockAlignment: String, CaseIterable, Identifiable {
    case left
    case center
    case right

    var id: String { rawValue }

    init(position: DockPosition) {
        switch position {
        case .bottomLeft:
            self = .left
        case .bottomRight:
            self = .right
        case .bottomCenter, .left, .right:
            self = .center
        }
    }

    var position: DockPosition {
        switch self {
        case .left:
            return .bottomLeft
        case .center:
            return .bottomCenter
        case .right:
            return .bottomRight
        }
    }

    var label: String {
        switch self {
        case .left:
            return "Left"
        case .center:
            return "Center"
        case .right:
            return "Right"
        }
    }
}

struct AppearanceControlCenterSection: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Appearance")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Dock scale")
                            .frame(width: AppearanceLayout.labelWidth, alignment: .leading)
                        Picker("Dock scale", selection: dockScale) {
                            ForEach(DockScalePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: AppearanceLayout.segmentedControlWidth)
                    }

                    GridRow {
                        Text("Calendar widget")
                            .frame(width: AppearanceLayout.labelWidth, alignment: .leading)
                        Picker("Calendar widget size", selection: $model.settings.calendarWidgetSizePreset) {
                            ForEach(WidgetSizePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: AppearanceLayout.segmentedControlWidth)
                    }

                    GridRow {
                        Text("Weather widget")
                            .frame(width: AppearanceLayout.labelWidth, alignment: .leading)
                        Picker("Weather widget size", selection: $model.settings.weatherWidgetSizePreset) {
                            ForEach(WidgetSizePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: AppearanceLayout.segmentedControlWidth)
                    }
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        surfaceControls
                        LiquidGlassPreview(settings: model.settings)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        surfaceControls
                        LiquidGlassPreview(settings: model.settings)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 760, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dockScale: Binding<DockScalePreset> {
        Binding(
            get: { DockScalePreset.nearest(to: model.settings) },
            set: { preset in
                // Store concrete dimensions instead of the preset enum so the
                // model stays honest about what the renderer needs. The preset
                // is a control-center affordance, not a second source of truth.
                model.settings.dockSize = preset.dockSize
                model.settings.iconSize = preset.iconSize
                model.settings.spacing = preset.spacing
            }
        )
    }

    private var surfaceControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Liquid Glass")
                        .frame(width: AppearanceLayout.labelWidth, alignment: .leading)
                    Picker("Liquid Glass", selection: $model.settings.liquidGlassSurfaceStyle) {
                        ForEach(LiquidGlassSurfaceStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: AppearanceLayout.segmentedControlWidth)
                }

                GridRow {
                    Text("Theme")
                        .frame(width: AppearanceLayout.labelWidth, alignment: .leading)
                    Picker("Theme", selection: $model.settings.theme) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .leading)
                }

                GridRow {
                    Text("Accent color")
                        .frame(width: AppearanceLayout.labelWidth, alignment: .leading)
                    Picker("Accent color", selection: $model.settings.accentColorName) {
                        ForEach(DockingAccentColor.allCases) { accent in
                            HStack {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 10, height: 10)
                                Text(accent.label)
                            }
                            .tag(accent.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .leading)
                }
            }
        }
    }
}

private enum AppearanceLayout {
    // These widths intentionally stay below the old 280px controls. The Control
    // Center should keep its compact, Settings-like window size; widening the
    // whole window just to make the Appearance preview fit made core chrome
    // such as the sidebar toggle feel unstable. The labels remain wide enough
    // for the current English copy, while the preview gets a permanent right
    // column at the user's normal window size.
    static let labelWidth: CGFloat = 104
    static let segmentedControlWidth: CGFloat = 230
    static let previewWidth: CGFloat = 232
    static let previewHeight: CGFloat = 126
    static let previewScale: CGFloat = 0.36
}

private struct LiquidGlassPreview: View {
    let settings: DockingSettings

    var body: some View {
        let previewScale = AppearanceLayout.previewScale
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            settings.accentColor.opacity(0.22),
                            Color(nsColor: .windowBackgroundColor),
                            Color.primary.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: min(settings.spacing * previewScale, 6)) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(index == 0 ? settings.accentColor.opacity(0.78) : Color.primary.opacity(0.18))
                        .frame(width: settings.iconSize * previewScale, height: settings.iconSize * previewScale)
                        .overlay(alignment: .bottom) {
                            Circle()
                                .fill(index == 2 ? settings.accentColor : Color.clear)
                                .frame(width: 5, height: 5)
                                .offset(y: 8)
                        }
                }

                Divider()
                    .frame(height: min(settings.iconSize * previewScale, 34))

                previewWidget(title: "17", subtitle: "Today", width: settings.calendarWidgetWidth, height: settings.widgetTileHeight, scale: previewScale)
                previewWidget(title: "24", subtitle: "Clear", width: settings.weatherWidgetWidth, height: settings.widgetTileHeight, scale: previewScale)
            }
            .padding(.horizontal, 12)
            // The preview is intentionally scaled, not pixel-for-pixel. It must
            // show the relationship between presets without creating a second
            // layout problem inside Control Center when the user chooses the
            // largest Dock and widget sizes.
            .frame(height: settings.effectiveDockThickness * 0.64)
            .dockingSurface(settings: settings)
            .padding(16)
        }
        .frame(width: AppearanceLayout.previewWidth, height: AppearanceLayout.previewHeight)
        .preferredColorScheme(settings.theme.colorScheme)
        .tint(settings.accentColor)
        .accessibilityLabel("Liquid Glass preview")
    }

    private func previewWidget(title: String, subtitle: String, width: Double, height: Double, scale: Double) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width * scale, height: height * scale)
        .background {
            RoundedRectangle(cornerRadius: min(12, height * 0.18), style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: min(12, height * 0.18), style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
        }
    }
}

struct WidgetsControlCenterSection: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        // Widgets can expose permission-sensitive Calendar controls and
        // network-backed Weather controls. Keeping this surface in the single
        // Control Center avoids duplicate configuration surfaces, while the
        // explicit scroll container keeps the lower Weather controls reachable
        // in compact window sizes.
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calendar Widget")
                        .font(.headline)
                    Toggle("Enable Calendar widget", isOn: $model.settings.calendarEnabled)
                    Stepper("Lookahead days: \(model.settings.calendarLookaheadDays)", value: $model.settings.calendarLookaheadDays, in: DockingSettingLimits.calendarLookaheadDays)
                    Stepper("Max events: \(model.settings.calendarMaxEventCount)", value: $model.settings.calendarMaxEventCount, in: DockingSettingLimits.calendarMaxEventCount)
                    Toggle("Show event locations", isOn: $model.settings.calendarShowsLocation)
                    CalendarSourcePicker()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Weather Widget")
                        .font(.headline)
                    Toggle("Enable Weather widget", isOn: $model.settings.weatherEnabled)
                    Toggle("Use current location", isOn: $model.settings.weatherUsesCurrentLocation)

                    HStack {
                        Text("Manual location")
                        TextField("Tokyo", text: $model.settings.weatherManualLocation)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                    }
                    Text("Manual location is used for weather without Location Services, and as the fallback if current-location weather is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Temperature unit", selection: $model.settings.weatherUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.rawValue.capitalized).tag(unit)
                        }
                    }
                    .frame(maxWidth: 280, alignment: .leading)

                    Stepper("Refresh interval: \(model.settings.weatherRefreshIntervalMinutes) min", value: $model.settings.weatherRefreshIntervalMinutes, in: DockingSettingLimits.weatherRefreshIntervalMinutes, step: DockingSettingLimits.weatherRefreshIntervalStep)
                    Toggle("Show humidity", isOn: $model.settings.weatherShowsHumidity)
                    Toggle("Show AQI if available", isOn: $model.settings.weatherShowsAQI)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CalendarSourcePicker: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calendars")
                Spacer()
                Button {
                    Task {
                        await model.calendarViewModel.refreshAvailableCalendars(settings: model.settings)
                    }
                } label: {
                    Label("Load", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!model.settings.calendarEnabled)
                Button("All") {
                    model.settings.calendarSelectedCalendarIDs = []
                }
                .buttonStyle(.borderless)
            }

            if !model.settings.calendarEnabled {
                // Keep the selector's location stable, but do not enumerate
                // calendars while the widget is off. Hiding the entire control
                // would make the setting feel like it moved; loading sources
                // here would violate the user's expectation that "off" means no
                // Calendar access.
                Text("Enable the Calendar widget to choose calendars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                switch model.calendarViewModel.sourceState {
                case .idle:
                    // Do not enumerate calendars merely because the user opened
                    // Control Center. EventKit can display a system permission dialog,
                    // and surprising permission prompts made the Widgets tab
                    // feel broken. The explicit Load action keeps the settings
                    // surface inspectable even before the user is ready to grant
                    // Calendar access.
                    Text("Load calendars when you want to choose specific sources. Leaving this empty uses all calendars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                case .permissionDenied:
                    Text("Calendar access is off. Enable it in System Settings to choose calendars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .error(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .loaded:
                    if model.calendarViewModel.availableCalendars.isEmpty {
                        Text("No calendars found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.calendarViewModel.availableCalendars) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { isSelected(calendar.id) },
                                    set: { setSelected($0, id: calendar.id) }
                                )
                            ) {
                                HStack(spacing: 8) {
                                    CalendarColorDot(hex: calendar.colorHex)
                                    Text(calendar.title)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func isSelected(_ id: String) -> Bool {
        let selected = model.settings.calendarSelectedCalendarIDs
        // Empty selection intentionally means "all calendars"; every row appears
        // checked so users do not misread the default as "none selected".
        return selected.isEmpty || selected.contains(id)
    }

    private func setSelected(_ selected: Bool, id: String) {
        var ids = Set(model.settings.calendarSelectedCalendarIDs)
        if ids.isEmpty {
            ids = Set(model.calendarViewModel.availableCalendars.map(\.id))
        }

        if selected {
            ids.insert(id)
        } else {
            ids.remove(id)
        }

        let allIDs = Set(model.calendarViewModel.availableCalendars.map(\.id))
        model.settings.calendarSelectedCalendarIDs = ids == allIDs ? [] : Array(ids).sorted()
    }
}

private struct CalendarColorDot: View {
    let hex: String?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var color: Color {
        guard let hex,
              hex.count == 7,
              let value = Int(hex.dropFirst(), radix: 16) else {
            return .accentColor
        }

        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct AppsControlCenterSection: View {
    var body: some View {
        AppsControlCenterContent()
            .frame(minHeight: 220)
    }
}

private struct AppsControlCenterContent: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Applications")
                    .font(.headline)
                Spacer()
                Button {
                    model.addApplication()
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                Button {
                    model.resetAppList()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
            }

            List {
                ForEach(Array(model.dockItems.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Image(nsImage: model.icon(for: item))
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.bundleIdentifier ?? item.appURL?.path ?? "Unknown app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        // Dock drag-reorder remains the fastest path while the
                        // dock is visible, but settings needs an explicit
                        // keyboard- and VoiceOver-friendly reorder affordance.
                        // Relying only on List's platform-specific edit mode
                        // made the Apps section look editable without giving a
                        // clear way to change order in this Control Center.
                        HStack(spacing: 4) {
                            Button {
                                model.moveDockItem(item, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .dockTooltip("Move up")

                            Button {
                                model.moveDockItem(item, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == model.dockItems.count - 1)
                            .dockTooltip("Move down")
                        }
                        .accessibilityElement(children: .contain)
                        Button {
                            model.remove(item)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .dockTooltip("Remove")
                    }
                }
                .onMove(perform: model.moveDockItem)
            }
        }
    }
}
