import AppKit
import SwiftUI

struct GeneralControlCenterSection: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("General")
                    .font(.headline)
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                Text(model.launchAtLoginStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show menu bar icon", isOn: $model.settings.showMenuBarIcon)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Dock visibility")
                        Picker("Dock visibility", selection: $model.settings.dockVisibility) {
                            ForEach(DockVisibilityMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    if model.settings.dockVisibility == .autoHide {
                        GridRow {
                            Text("Auto-hide delay")
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
                Text(model.appleDockVisibilityStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Unpinned running apps")
                        Picker("Unpinned running apps", selection: $model.settings.unpinnedRunningAppVisibility) {
                            ForEach(UnpinnedRunningAppVisibility.allCases) { visibility in
                                Text(visibility.label).tag(visibility)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220, alignment: .leading)
                    }
                }
                Toggle("Keep above other windows", isOn: $model.settings.keepAboveOtherWindows)
                Text("Turn this off if you want Docking to behave like an ordinary overlay while testing another full-screen or always-on-top workflow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Show on all Spaces", isOn: $model.settings.showOnAllSpaces)
                Toggle("Show on full-screen spaces", isOn: $model.settings.showOnFullScreenSpaces)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Position")
                        Picker("Position", selection: $model.settings.dockPosition) {
                            ForEach(DockPosition.allCases) { position in
                                Text(position.label).tag(position)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220, alignment: .leading)
                    }

                    GridRow {
                        Text("Display")
                        Picker("Display", selection: $model.settings.displayMode) {
                            ForEach(DockDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220, alignment: .leading)
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
            }
            .padding()
            .frame(maxWidth: 560, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                            .frame(width: 120, alignment: .leading)
                        Picker("Dock scale", selection: dockScale) {
                            ForEach(DockScalePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }

                    GridRow {
                        Text("Calendar widget")
                            .frame(width: 120, alignment: .leading)
                        Picker("Calendar widget size", selection: $model.settings.calendarWidgetSizePreset) {
                            ForEach(WidgetSizePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }

                    GridRow {
                        Text("Weather widget")
                            .frame(width: 120, alignment: .leading)
                        Picker("Weather widget size", selection: $model.settings.weatherWidgetSizePreset) {
                            ForEach(WidgetSizePreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
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
                        .frame(width: 120, alignment: .leading)
                    Picker("Liquid Glass", selection: $model.settings.liquidGlassSurfaceStyle) {
                        ForEach(LiquidGlassSurfaceStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }

                GridRow {
                    Text("Theme")
                        .frame(width: 120, alignment: .leading)
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
                        .frame(width: 120, alignment: .leading)
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

private struct LiquidGlassPreview: View {
    let settings: DockingSettings

    var body: some View {
        let previewScale = 0.45
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
        .frame(width: 260, height: 138)
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
