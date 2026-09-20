import Foundation

// Display order follows NSScreen.screens: the first display is the primary
// display, not the display currently hosting the keyboard-focused window.
enum DockDisplayPolicy {
    static func selectedDisplayID(
        settings: DockingSettings,
        currentDisplayID: UInt32?,
        availableDisplayIDs: [UInt32],
        screensHaveSeparateSpaces: Bool
    ) -> UInt32? {
        if settings.displayMode == .specific {
            if let id = settings.dockDisplayID, availableDisplayIDs.contains(id) {
                return id
            }
            return availableDisplayIDs.first
        }
        if screensHaveSeparateSpaces,
           let id = currentDisplayID, availableDisplayIDs.contains(id) {
            return id
        }
        return availableDisplayIDs.first
    }

    static func triggerDisplayIDs(
        settings: DockingSettings,
        currentDisplayID: UInt32?,
        availableDisplayIDs: [UInt32],
        screensHaveSeparateSpaces: Bool
    ) -> [UInt32] {
        guard let selected = selectedDisplayID(
            settings: settings, currentDisplayID: currentDisplayID,
            availableDisplayIDs: availableDisplayIDs,
            screensHaveSeparateSpaces: screensHaveSeparateSpaces
        ) else { return [] }

        // Side-dock migration needs a native comparison of exposed edges. Do
        // not install new strips on shared left/right edges by guessing.
        let canMove = settings.displayMode == .automatic
            && screensHaveSeparateSpaces && settings.dockPosition.isBottom
        let eligible = canMove ? availableDisplayIDs : [selected]
        // A visible dock needs only the other-display summon targets. Hiding
        // and choosing a display are otherwise independent decisions.
        return settings.dockVisibility == .autoHide
            ? eligible : eligible.filter { $0 != selected }
    }
}

// Only these settings invalidate a pending edge gesture. Content/size/theme
// updates deliberately do not restart the user's reveal delay.
struct DockEdgeConfiguration: Equatable {
    let displayMode: DockDisplayMode
    let fixedDisplayID: UInt32?
    let currentDisplayID: UInt32?
    let position: DockPosition
    let visibility: DockVisibilityMode
    let response: DockAutoHideResponsePreset
    let separateSpaces: Bool
    let allSpaces: Bool
    let fullScreenSpaces: Bool

    init(settings: DockingSettings, currentDisplayID: UInt32?, separateSpaces: Bool) {
        displayMode = settings.displayMode
        fixedDisplayID = settings.dockDisplayID
        self.currentDisplayID = currentDisplayID
        position = settings.dockPosition
        visibility = settings.dockVisibility
        response = settings.dockAutoHideResponsePreset
        self.separateSpaces = separateSpaces
        allSpaces = settings.showOnAllSpaces
        fullScreenSpaces = settings.showOnFullScreenSpaces
    }
}
