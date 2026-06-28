import AppKit

@MainActor
final class MenuBarStatusController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var model: DockingAppModel?
    private weak var openCalendarItem: NSMenuItem?
    private weak var openWeatherItem: NSMenuItem?

    func update(isVisible: Bool, model: DockingAppModel) {
        self.model = model

        if isVisible {
            ensureStatusItem()
        } else {
            removeStatusItem()
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Docking")
        item.button?.toolTip = "Docking"
        item.menu = makeMenu()
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else {
            return
        }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        openCalendarItem = nil
        openWeatherItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Show and Hide stay as separate commands instead of one dynamic menu
        // title. The status item is an AppKit bridge around SwiftUI-owned state,
        // and avoiding menu validation keeps this bridge small while still
        // satisfying the dock utility expectation that both actions are nearby.
        menu.addItem(menuItem("Show Docking", action: #selector(showDock)))
        menu.addItem(menuItem("Hide Docking", action: #selector(hideDock)))
        menu.addItem(menuItem("Open Control Center", action: #selector(openControlCenter)))
        menu.addItem(.separator())
        let calendarItem = menuItem("Open Calendar Widget", action: #selector(openCalendarWidget))
        let weatherItem = menuItem("Open Weather Widget", action: #selector(openWeatherWidget))
        menu.addItem(calendarItem)
        menu.addItem(weatherItem)
        openCalendarItem = calendarItem
        openWeatherItem = weatherItem
        menu.addItem(.separator())
        menu.addItem(menuItem("Restore macOS Dock", action: #selector(restoreDock)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Docking", action: #selector(quit)))

        return menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showDock() {
        model?.showDock()
    }

    @objc private func hideDock() {
        model?.hideDock()
    }

    @objc private func openControlCenter() {
        model?.openControlCenterWindow()
    }

    @objc private func openCalendarWidget() {
        model?.openCalendarPanel()
    }

    @objc private func openWeatherWidget() {
        model?.openWeatherPanel()
    }

    @objc private func restoreDock() {
        model?.restoreOriginalDockSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension MenuBarStatusController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            // Widget availability can change from Control Center after the
            // status item has already been created. Updating the two items when
            // the menu opens avoids a heavier menu-rebuild path while still
            // keeping the always-reachable menu honest about disabled widgets.
            self.openCalendarItem?.isEnabled = self.model?.canOpenCalendarPanel == true
            self.openWeatherItem?.isEnabled = self.model?.canOpenWeatherPanel == true
        }
    }
}
