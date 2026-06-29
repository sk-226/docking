import DockingCore
import SwiftUI

@main
struct DockingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DockingAppModel.shared

    var body: some Scene {
        WindowGroup("Docking", id: "main") {
            ControlCenterView()
                .environmentObject(model)
                .preferredColorScheme(model.appPreferredColorScheme)
                .tint(model.appAccentColor)
                .frame(minWidth: 520, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Open Control Center...") {
                    model.openControlCenterWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button("Show Docking") {
                    model.showDock()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Hide Docking") {
                    model.hideDock()
                }

                Button("Open Calendar Widget") {
                    model.openCalendarPanel()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!model.canOpenCalendarPanel)

                Button("Open Weather Widget") {
                    model.openWeatherPanel()
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(!model.canOpenWeatherPanel)
            }
        }
    }
}
