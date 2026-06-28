import AppKit
import SwiftUI

struct DockRestoreView: View {
    @EnvironmentObject private var model: DockingAppModel
    @State private var confirmsPrimaryMode = false
    @State private var confirmsAppleDockReload = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Primary Dock Mode")
                        .font(.headline)
                    Text(primaryModeSummary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Current mode", value: model.settings.dockReplacementModeEnabled ? "Primary dock" : "Overlay")
                        LabeledContent("Saved snapshot", value: snapshotSummary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            confirmsPrimaryMode = true
                        } label: {
                            Label("Use Docking as Primary Dock", systemImage: "dock.rectangle")
                        }
                        .disabled(model.settings.dockReplacementModeEnabled)

                        Button {
                            model.disableDockReplacementMode()
                        } label: {
                            Label("Disable Docking replacement mode", systemImage: "xmark.circle")
                        }
                        .disabled(!model.settings.dockReplacementModeEnabled)
                    }

                    Button {
                        confirmsAppleDockReload = true
                    } label: {
                        Label("Reload Apple Dock to Apply", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Text(model.restoreStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Restore and Uninstall Safety")
                        .font(.headline)
                    Text("Docking saves Apple Dock preferences before primary mode changes them. Restore writes those saved values back. Docking never modifies system files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            model.restoreOriginalDockSettings()
                        } label: {
                            Label("Restore Original macOS Dock Settings", systemImage: "arrow.counterclockwise")
                        }

                        Button(role: .destructive) {
                            NSApplication.shared.terminate(nil)
                        } label: {
                            Label("Quit Docking", systemImage: "power")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .topLeading)
        }
        .confirmationDialog(
            "Use Docking as the primary dock?",
            isPresented: $confirmsPrimaryMode,
            titleVisibility: .visible
        ) {
            Button("Enable Primary Dock Mode") {
                model.enableDockReplacementMode()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Docking will save your current Apple Dock settings, move Apple Dock out of the way with auto-hide and a long delay, and keep using Docking's current visibility mode. You can restore the saved Apple Dock settings from this screen.")
        }
        .confirmationDialog(
            "Reload Apple Dock now?",
            isPresented: $confirmsAppleDockReload,
            titleVisibility: .visible
        ) {
            Button("Reload Apple Dock") {
                model.reloadAppleDockToApplyPreferences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs killall Dock so macOS restarts Apple Dock and applies preference changes. Open windows stay open, but Mission Control and Dock may briefly refresh.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var primaryModeSummary: String {
        if model.settings.dockReplacementModeEnabled {
            return "Docking is configured as the primary dock. Apple Dock settings were changed only after explicit confirmation and can be restored here."
        }

        // The product intent is that the user interacts with Docking's own dock,
        // not Apple's Dock. We still keep this opt-in because changing Apple
        // Dock preferences is visible system behavior and should never happen
        // just because the app launched or the user opened Control Center.
        return "Docking is active as its own dock. To make it the primary dock, enable this mode explicitly; Docking will save your current Apple Dock settings first."
    }

    private var snapshotSummary: String {
        guard let createdAt = model.dockRestoreStatus.snapshotCreatedAt else {
            return "None"
        }

        // This timestamp is user-facing operational state, not a log-only
        // detail. Showing it in the Restore tab makes it clear which Apple Dock
        // preferences will be written back before the user disables primary
        // mode or uninstalls Docking.
        let dateText = DockingFormatters.dateTimeFormatter.string(from: createdAt)
        let versionText = model.dockRestoreStatus.snapshotAppVersion.map { "Docking \($0)" } ?? "unknown version"
        return "\(dateText) · \(model.dockRestoreStatus.savedPreferenceCount) values · \(versionText)"
    }
}
