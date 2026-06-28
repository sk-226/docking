import AppKit
import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var model: DockingAppModel

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            AppsSettingsTab()
                .tabItem { Label("Apps", systemImage: "app.badge") }

            WidgetsSettingsTab()
                .tabItem { Label("Widgets", systemImage: "calendar.badge.clock") }

            DockRestoreView()
                .tabItem { Label("Restore", systemImage: "arrow.counterclockwise") }
        }
        .frame(width: 620, height: 520)
        .scenePadding()
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        Form {
            Section("General") {
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
                Picker("Dock visibility", selection: $model.settings.dockVisibility) {
                    ForEach(DockVisibilityMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if model.settings.dockVisibility == .autoHide {
                    Slider(value: $model.settings.autoHideDelay, in: DockingSettingLimits.autoHideDelay, step: 0.1) {
                        Text("Auto-hide delay")
                    }
                }
                Button("Match Apple Dock visibility") {
                    model.matchAppleDockVisibility()
                }
                Text(model.appleDockVisibilityStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show on all Spaces", isOn: $model.settings.showOnAllSpaces)
                Toggle("Show on full-screen spaces", isOn: $model.settings.showOnFullScreenSpaces)
                Picker("Position", selection: $model.settings.dockPosition) {
                    ForEach(DockPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                Picker("Display", selection: $model.settings.displayMode) {
                    ForEach(DockDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
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
        }
        .padding()
    }
}

private struct AppearanceSettingsTab: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        Form {
            Section("Sizing") {
                Slider(value: $model.settings.dockSize, in: DockingSettingLimits.dockSize, step: 1) {
                    Text("Dock size")
                }
                Slider(value: $model.settings.iconSize, in: DockingSettingLimits.iconSize, step: 1) {
                    Text("Icon size")
                }
                Slider(value: $model.settings.widgetSize, in: DockingSettingLimits.widgetSize, step: 1) {
                    Text("Widget size")
                }
                Slider(value: $model.settings.spacing, in: DockingSettingLimits.spacing, step: 1) {
                    Text("Spacing")
                }
            }

            Section("Surface") {
                Slider(value: $model.settings.cornerRadius, in: DockingSettingLimits.cornerRadius, step: 1) {
                    Text("Corner radius")
                }
                Slider(value: $model.settings.materialStrength, in: DockingSettingLimits.materialStrength, step: 0.05) {
                    Text("Material strength")
                }
                Slider(value: $model.settings.opacity, in: DockingSettingLimits.opacity, step: 0.01) {
                    Text("Opacity")
                }
                Picker("Theme", selection: $model.settings.theme) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
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
            }
        }
        .padding()
    }
}

private struct AppsSettingsTab: View {
    var body: some View {
        AppsSettingsContent()
            .padding()
    }
}

struct WidgetsSettingsTab: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        // The same widget settings surface is embedded in both the standalone
        // Settings scene and the main Docking control window. A bare macOS
        // Form can be clipped when reused inside NavigationSplitView detail
        // content, which made the Weather controls disappear in the smaller
        // control window. Owning the scroll container here makes the section
        // robust in both hosts without adding per-host layout hacks.
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
                    // Settings. EventKit can display a system permission dialog,
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

struct AppListSettingsSection: View {
    var body: some View {
        AppsSettingsContent()
            .frame(minHeight: 220)
    }
}

private struct AppsSettingsContent: View {
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
                ForEach(model.dockItems) { item in
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
