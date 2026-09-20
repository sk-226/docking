import Foundation
import XCTest
@testable import DockingCore

final class DockDisplayPolicyTests: XCTestCase {
    private let displays: [UInt32] = [11, 22, 33]

    private func selected(_ settings: DockingSettings = .default, current: UInt32? = nil,
                          displays: [UInt32]? = nil, separate: Bool = true) -> UInt32? {
        DockDisplayPolicy.selectedDisplayID(settings: settings, currentDisplayID: current,
            availableDisplayIDs: displays ?? self.displays, screensHaveSeparateSpaces: separate)
    }

    private func triggers(_ settings: DockingSettings = .default, current: UInt32? = 22,
                          displays: [UInt32]? = nil, separate: Bool = true) -> [UInt32] {
        DockDisplayPolicy.triggerDisplayIDs(settings: settings, currentDisplayID: current,
            availableDisplayIDs: displays ?? self.displays, screensHaveSeparateSpaces: separate)
    }

    func testOnlyAutomaticAndFixedAreOffered() {
        XCTAssertEqual(DockDisplayMode.allCases, [.automatic, .specific])
        XCTAssertEqual(DockingSettings.default.displayMode, .automatic)
        XCTAssertEqual(selected(), 11)
    }

    func testAutomaticPreservesCurrentDisplayAcrossUnrelatedUpdates() {
        var settings = DockingSettings.default
        for visibility in DockVisibilityMode.allCases {
            settings.dockVisibility = visibility
            settings.iconSize = 60
            settings.weatherEnabled = false
            settings.calendarWidgetSizePreset = .compact
            settings.theme = .dark
            XCTAssertEqual(selected(settings, current: 22), 22)
        }
    }

    func testSharedSpacesUsesPrimaryRegardlessOfPreviousSummon() {
        for visibility in DockVisibilityMode.allCases {
            var settings = DockingSettings.default
            settings.dockVisibility = visibility
            XCTAssertEqual(selected(settings, current: 22, separate: false), 11)
            XCTAssertEqual(triggers(settings, separate: false), visibility == .autoHide ? [11] : [])
        }
    }

    func testFixedSelectionWinsImmediatelyOverPreviousDisplay() {
        var settings = DockingSettings.default
        settings.displayMode = .specific
        for visibility in DockVisibilityMode.allCases {
            settings.dockVisibility = visibility
            settings.dockDisplayID = 33
            XCTAssertEqual(selected(settings, current: 22), 33)
            settings.dockDisplayID = 11
            XCTAssertEqual(selected(settings, current: 33), 11)
            XCTAssertEqual(selected(settings, current: 33, separate: false), 11)
        }
    }

    func testFixedDisplayCannotBeOverriddenByAnEdgeSummon() {
        var settings = DockingSettings.default
        settings.displayMode = .specific
        settings.dockDisplayID = 33
        for separate in [false, true] {
            settings.dockVisibility = .autoHide
            XCTAssertEqual(triggers(settings, separate: separate), [33])
            settings.dockVisibility = .alwaysVisible
            XCTAssertEqual(triggers(settings, separate: separate), [])
        }
    }

    func testDisconnectedAutomaticFallsBackAndDoesNotBounceOnReconnect() {
        let fallback = selected(current: 22, displays: [11, 33])
        XCTAssertEqual(fallback, 11)
        XCTAssertEqual(selected(current: fallback), 11)
    }

    func testFixedReconnectRestoresRequestedDisplayWithoutChangingPreference() {
        var settings = DockingSettings.default
        settings.displayMode = .specific
        settings.dockDisplayID = 22
        XCTAssertEqual(selected(settings, current: 22, displays: [11, 33]), 11)
        XCTAssertEqual(settings.dockDisplayID, 22)
        XCTAssertEqual(selected(settings, current: 11), 22)
        settings.dockDisplayID = nil
        XCTAssertEqual(selected(settings, current: 33), 11)
    }

    func testPrimaryChangeDoesNotMoveAutomaticDockWithSeparateSpaces() {
        XCTAssertEqual(selected(current: 22, displays: [33, 11, 22]), 22)
        XCTAssertEqual(selected(current: 22, displays: [33, 11, 22], separate: false), 33)
    }

    func testNoConnectedDisplaysHasNoPlacementOrTriggers() {
        for mode in DockDisplayMode.allCases {
            var settings = DockingSettings.default
            settings.displayMode = mode
            settings.dockDisplayID = 22
            XCTAssertNil(selected(settings, current: 22, displays: []))
            XCTAssertEqual(triggers(settings, displays: []), [])
        }
    }

    func testBottomSummoningIsIndependentOfVisibility() {
        for position in [DockPosition.bottomCenter, .bottomLeft, .bottomRight] {
            var settings = DockingSettings.default
            settings.dockPosition = position
            XCTAssertEqual(triggers(settings), displays)
            settings.dockVisibility = .alwaysVisible
            XCTAssertEqual(triggers(settings), [11, 33])
            XCTAssertEqual(triggers(settings, current: 33), [11, 22])
        }
    }

    func testSideDocksDoNotInstallCrossDisplayStrips() {
        for position in [DockPosition.left, .right] {
            var settings = DockingSettings.default
            settings.dockPosition = position
            XCTAssertEqual(selected(settings, current: 22), 22)
            XCTAssertEqual(triggers(settings), [22])
            settings.dockVisibility = .alwaysVisible
            XCTAssertEqual(triggers(settings), [])
        }
    }

    func testSwitchingBackToAutomaticPreservesTheCurrentDisplayNotOldPreference() {
        var settings = DockingSettings.default
        settings.displayMode = .specific
        settings.dockDisplayID = 33
        let fixed = selected(settings, current: 22)
        settings.displayMode = .automatic
        XCTAssertEqual(selected(settings, current: fixed), 33)
        // A later valid edge summon, not a settings refresh, chooses display 22.
        XCTAssertTrue(triggers(settings, current: fixed).contains(22))
        XCTAssertEqual(selected(settings, current: 22), 22)
    }

    func testPendingGestureConfigurationIgnoresContentAndSizeUpdates() {
        var settings = DockingSettings.default
        let before = DockEdgeConfiguration(settings: settings, currentDisplayID: 22, separateSpaces: true)
        settings.iconSize = 60
        settings.magnificationSize = 120
        settings.theme = .light
        settings.weatherEnabled = false
        settings.autoHideDelay = 1.5
        XCTAssertEqual(before, DockEdgeConfiguration(settings: settings, currentDisplayID: 22, separateSpaces: true))
    }

    func testPendingGestureConfigurationChangesWithPlacementAndSpaces() {
        let settings = DockingSettings.default
        let before = DockEdgeConfiguration(settings: settings, currentDisplayID: 22, separateSpaces: true)
        let mutations: [(inout DockingSettings) -> Void] = [
            { $0.displayMode = .specific }, { $0.dockDisplayID = 33 },
            { $0.dockPosition = .right }, { $0.dockVisibility = .alwaysVisible },
            { $0.dockAutoHideResponsePreset = .instant },
            { $0.showOnAllSpaces = false }, { $0.showOnFullScreenSpaces = false }
        ]
        for mutate in mutations {
            var changed = settings
            mutate(&changed)
            XCTAssertNotEqual(before, DockEdgeConfiguration(settings: changed, currentDisplayID: 22, separateSpaces: true))
        }
        XCTAssertNotEqual(before, DockEdgeConfiguration(settings: settings, currentDisplayID: 33, separateSpaces: true))
        XCTAssertNotEqual(before, DockEdgeConfiguration(settings: settings, currentDisplayID: 22, separateSpaces: false))
    }

    func testUnknownDisplayChoiceDoesNotResetOtherSettings() throws {
        let data = Data(#"{"displayMode":"unknown","iconSize":60,"weatherEnabled":false,"dockDisplayID":33}"#.utf8)
        let settings = try JSONDecoder().decode(DockingSettings.self, from: data)
        XCTAssertEqual(settings.displayMode, .automatic)
        XCTAssertEqual(settings.iconSize, 60)
        XCTAssertFalse(settings.weatherEnabled)
        XCTAssertEqual(settings.dockDisplayID, 33)
    }

    func testDisplayChoicesRoundTrip() throws {
        for mode in DockDisplayMode.allCases {
            var settings = DockingSettings.default
            settings.displayMode = mode
            settings.dockDisplayID = 33
            let data = try JSONEncoder().encode(settings)
            XCTAssertEqual(try JSONDecoder().decode(DockingSettings.self, from: data), settings)
        }
    }
}
