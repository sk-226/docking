import AppKit
import SwiftUI

struct DockRestoreView: View {
    @EnvironmentObject private var model: DockingAppModel
    @State private var confirmsPrimaryMode = false
    @State private var confirmsAppleDockReload = false
    @State private var confirmsDisableReplacementMode = false
    @State private var confirmsRestoreOriginalDock = false

    var body: some View {
        ControlCenterScrollPage(maxContentWidth: 700) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Primary Dock Mode")
                        .font(.headline)
                    Text(primaryModeSummary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Current mode", value: currentModeLabel)
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
                            // Disabling replacement mode writes Apple Dock
                            // preferences. It is tempting to treat this as a
                            // harmless "turn off" toggle, but the user can
                            // experience visible system Dock changes, so it
                            // belongs behind the same explicit confirmation
                            // boundary as enabling primary mode.
                            confirmsDisableReplacementMode = true
                        } label: {
                            Label("Disable Docking replacement mode", systemImage: "xmark.circle")
                        }
                        .disabled(!model.settings.dockReplacementModeEnabled)
                    }

                    Button {
                        model.matchOriginalAppleDockLayout()
                    } label: {
                        Label("Match Original Apple Dock Layout", systemImage: "square.stack.3d.up")
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
                    Text("Docking saves Apple Dock preferences before primary mode changes them. Restore writes those saved values back and verifies readable preferences after writing. Docking never modifies system files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            // Restoring is a safety feature, but it still
                            // writes into com.apple.dock. Keeping it
                            // confirm-first prevents an accidental click from
                            // changing the user's current Dock setup while
                            // they are only inspecting uninstall instructions.
                            confirmsRestoreOriginalDock = true
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

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Emergency Manual Restore")
                        .font(.headline)
                    Text(model.manualRestoreInstructions)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            Text("Docking will save your current Apple Dock settings, import the readable Apple Dock layout and pinned apps into Docking, then move Apple Dock out of the way with auto-hide and a long delay. You can restore the saved Apple Dock settings from this screen.")
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
            Text("This runs killall Dock so macOS restarts Apple Dock and applies preference changes. It does not import Apple Dock apps into Docking; use Match Original Apple Dock Layout for that. Open windows stay open, but Mission Control and Dock may briefly refresh.")
        }
        .confirmationDialog(
            "Disable primary dock mode?",
            isPresented: $confirmsDisableReplacementMode,
            titleVisibility: .visible
        ) {
            Button("Disable and Restore Apple Dock") {
                model.disableDockReplacementMode()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Docking will write the saved Apple Dock settings back, turn off primary dock mode, and keep manual restore instructions visible if macOS does not report the expected values.")
        }
        .confirmationDialog(
            "Restore original macOS Dock settings?",
            isPresented: $confirmsRestoreOriginalDock,
            titleVisibility: .visible
        ) {
            Button("Restore Apple Dock Settings") {
                model.restoreOriginalDockSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Docking will write the saved Apple Dock preference snapshot back. It will not run killall Dock here; use Reload Apple Dock to Apply only if you want macOS to restart Apple Dock after restoring.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var currentModeLabel: String {
        if model.settings.dockReplacementModeEnabled {
            return "Primary dock"
        }
        if model.dockRestoreStatus.hasSnapshot {
            return "Overlay, restore available"
        }
        return "Overlay"
    }

    private var primaryModeSummary: String {
        if model.settings.dockReplacementModeEnabled {
            return "Docking is configured as the primary dock. Apple Dock settings were changed only after explicit confirmation and can be restored here."
        }

        // The product intent is that the user interacts with Docking's own dock,
        // not Apple's Dock. We still keep this opt-in because changing Apple
        // Dock preferences is visible system behavior and should never happen
        // just because the app launched or the user opened Control Center.
        if model.dockRestoreStatus.hasSnapshot {
            return "Docking is active as its own dock and a saved Apple Dock snapshot is available. If Apple Dock still looks displaced, restore it here or match the saved layout into Docking."
        }
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
