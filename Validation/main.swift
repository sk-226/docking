import AppKit
import Foundation
@testable import DockingCore

struct ValidationFailure: Error, CustomStringConvertible {
    var description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw ValidationFailure(description: message)
    }
}

func validateFormatters() throws {
    let start = Date(timeIntervalSince1970: 0)
    let end = start.addingTimeInterval(100 * 60)
    try expect(DockingFormatters.durationString(from: start, to: end) == "1 hr 40 min", "duration formatter should use compact hour/minute output")
    try expect(DockingFormatters.seconds(0.05) == "0.05 sec", "seconds formatter should preserve fast auto-hide precision")
    try expect(DockingFormatters.seconds(0.7) == "0.7 sec", "seconds formatter should avoid noisy precision for ordinary auto-hide delays")
    try expect(DockingFormatters.seconds(2.0) == "2 sec", "seconds formatter should keep whole-second delays compact")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    try expect(DockingFormatters.sectionTitle(for: now, calendar: calendar, now: now) == "Today", "today section title should be stable")
    try expect(DockingFormatters.sectionTitle(for: tomorrow, calendar: calendar, now: now) == "Tomorrow", "tomorrow section title should be stable")
}

func validateCalendarGrouping() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let later = day.addingTimeInterval(3_600)
    let earlier = day.addingTimeInterval(600)
    let events = [
        CalendarEventSummary(id: "later", title: "Later", calendarName: "Work", startDate: later, endDate: later.addingTimeInterval(1_800), location: nil),
        CalendarEventSummary(id: "earlier", title: "Earlier", calendarName: "Work", startDate: earlier, endDate: earlier.addingTimeInterval(1_800), location: nil)
    ]

    let grouped = CalendarGrouping.groupEvents(events, calendar: calendar)
    try expect(grouped.count == 1, "events on the same day should share one section")
    try expect(grouped[0].events.map(\.id) == ["earlier", "later"], "events should sort by start time inside each section")

    try expect(
        CalendarDetailPanelPresentation.summaryEvent(from: events)?.id == "earlier",
        "calendar detail summary should promote the actual next event even when provider/test data arrives unsorted"
    )
    let detailGroups = CalendarDetailPanelPresentation.groupedEventsAfterSummary(events, calendar: calendar)
    try expect(
        detailGroups.flatMap(\.events).map(\.id) == ["later"],
        "calendar detail list should not duplicate the event already shown in the next-event summary"
    )
}

func validateDockLayout() throws {
    let settings = DockingSettings.default
    var appOnlySettings = settings
    appOnlySettings.calendarEnabled = false
    appOnlySettings.weatherEnabled = false
    let appOnly = DockLayout.panelSize(itemCount: 3, settings: appOnlySettings)
    let withWidgets = DockLayout.panelSize(itemCount: 3, settings: settings)
    try expect(withWidgets.width > appOnly.width, "dock width should grow when widgets are enabled")
    try expect(appOnly.height == appOnlySettings.effectiveDockThickness, "dock height should follow effective dock thickness")

    var verticalSettings = settings
    verticalSettings.dockPosition = .left
    let vertical = DockLayout.panelSize(itemCount: 3, settings: verticalSettings)
    try expect(vertical.width == verticalSettings.effectiveDockThickness, "vertical dock width should use effective dock thickness")
    try expect(vertical.height > vertical.width, "vertical dock should put items on the long vertical axis")
}

func validateDockIconRendererUsesFullBackingScale() throws {
    let image = DockIconImageRenderer.render { rect in
        NSColor.systemBlue.setFill()
        rect.fill()
    }

    guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first else {
        throw ValidationFailure(description: "generated dock icons should contain a bitmap representation")
    }

    try expect(bitmap.pixelsWide == 512, "generated dock icons should keep a Retina-width bitmap backing")
    try expect(bitmap.pixelsHigh == 512, "generated dock icons should keep a Retina-height bitmap backing")

    let topRightColor = bitmap.colorAt(x: bitmap.pixelsWide - 8, y: bitmap.pixelsHigh - 8)
    try expect(
        (topRightColor?.alphaComponent ?? 0) > 0.8,
        "generated dock icons should scale point drawing across the full Retina backing instead of the lower-left quarter"
    )
}

func validateDetailPanelAnchoring() throws {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
        // The product is a macOS GUI app, so a screen normally exists. Keeping
        // this validation non-fatal lets package checks still run in unusual
        // headless contexts while the app build remains the real AppKit gate.
        print("SKIP detail panel anchoring (no screen)")
        return
    }

    let visible = screen.visibleFrame
    let dockFrame = NSRect(x: visible.midX - 220, y: visible.minY + 10, width: 440, height: 72)
    let anchorFrame = NSRect(x: dockFrame.maxX - 96, y: dockFrame.minY + 8, width: 58, height: 58)
    let detailFrame = ScreenPlacementService.detailFrame(
        size: CGSize(width: 280, height: 200),
        dockFrame: dockFrame,
        anchorFrame: anchorFrame,
        on: screen
    )

    try expect(abs(detailFrame.midX - anchorFrame.midX) < 1, "detail panel should center on the widget anchor when there is room")
    try expect(detailFrame.minY > dockFrame.maxY, "detail panel should open above the dock")
}

func validateWidgetPanelDismissHitTesting() throws {
    let panelFrame = NSRect(x: 100, y: 100, width: 380, height: 430)
    let widgetFrame = NSRect(x: 260, y: 40, width: 58, height: 58)

    try expect(
        !WidgetDetailPanelController.shouldDismissPointerEvent(
            pointerLocation: NSPoint(x: panelFrame.midX, y: panelFrame.midY),
            panelFrame: panelFrame,
            anchorFrame: widgetFrame
        ),
        "clicks inside the widget detail panel should not dismiss it"
    )
    try expect(
        !WidgetDetailPanelController.shouldDismissPointerEvent(
            pointerLocation: NSPoint(x: widgetFrame.midX, y: widgetFrame.midY),
            panelFrame: panelFrame,
            anchorFrame: widgetFrame
        ),
        "clicking the source widget should be left for toggle(kind:) so a second click closes the panel"
    )
    try expect(
        WidgetDetailPanelController.shouldDismissPointerEvent(
            pointerLocation: NSPoint(x: 20, y: 20),
            panelFrame: panelFrame,
            anchorFrame: widgetFrame
        ),
        "ordinary outside clicks should still dismiss widget detail panels"
    )
    try expect(
        WidgetDetailPanelController.shouldSuppressImmediateRetoggle(
            recentlyDismissedKind: .weather,
            dismissedAt: 100,
            requestedKind: .weather,
            now: 100.1
        ),
        "same-click widget dismissal should not immediately reopen the same panel"
    )
    try expect(
        !WidgetDetailPanelController.shouldSuppressImmediateRetoggle(
            recentlyDismissedKind: .weather,
            dismissedAt: 100,
            requestedKind: .calendar,
            now: 100.1
        ),
        "same-click suppression should not block switching directly to a different widget"
    )
    try expect(
        !WidgetDetailPanelController.shouldSuppressImmediateRetoggle(
            recentlyDismissedKind: .weather,
            dismissedAt: 100,
            requestedKind: .weather,
            now: 101
        ),
        "same-click suppression should expire quickly so later widget opens still work"
    )
}

func validateSpecificDisplaySelection() throws {
    guard let display = ScreenPlacementService.availableDisplays().first else {
        print("SKIP specific display selection (no display)")
        return
    }

    var settings = DockingSettings.default
    settings.displayMode = .specific
    settings.dockDisplayID = display.id

    let frame = ScreenPlacementService.dockFrame(
        size: CGSize(width: 320, height: 72),
        on: ScreenPlacementService.dockScreen(for: settings)
    )

    try expect(frame.width > 0, "specific display mode should resolve to a usable dock frame")
}

func validateDockPositionFrames() throws {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
        print("SKIP dock position frames (no display)")
        return
    }

    let visible = screen.visibleFrame
    for position in DockPosition.allCases {
        var settings = DockingSettings.default
        settings.dockPosition = position
        let size = DockLayout.panelSize(itemCount: 4, settings: settings)
        let frame = ScreenPlacementService.dockFrame(size: size, on: screen, position: position)

        try expect(visible.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(position.label) dock frame should stay inside the visible screen")

        if position.isVertical {
            try expect(frame.width == settings.effectiveDockThickness, "\(position.label) dock should keep effective dock thickness")
            try expect(frame.height > frame.width, "\(position.label) dock should be vertical")
        } else {
            try expect(frame.height == settings.effectiveDockThickness, "\(position.label) dock should keep effective dock thickness")
            try expect(frame.width > frame.height, "\(position.label) dock should be horizontal")
        }

        let trigger = ScreenPlacementService.edgeTriggerFrame(dockFrame: frame, position: position, on: screen)
        try expect(screen.frame.insetBy(dx: -0.5, dy: -0.5).contains(trigger), "\(position.label) auto-hide trigger should stay on the physical screen edge")

        switch position {
        case .bottomCenter, .bottomLeft, .bottomRight:
            // The trigger must touch the physical screen edge, not merely fit
            // inside visibleFrame. visibleFrame can be shifted by Apple's Dock,
            // which is exactly what made Docking's auto-hide reveal feel dead
            // when the standard Dock was still visible.
            try expect(abs(trigger.minY - screen.frame.minY) < 0.5, "\(position.label) auto-hide trigger should touch the bottom screen edge")
            try expect(trigger.height >= 4, "\(position.label) auto-hide trigger should have enough thickness to catch pointer entry")
            let fullBottomTrigger = ScreenPlacementService.edgeTriggerFrame(dockFrame: frame, position: position, on: screen, spansFullBottomEdge: true)
            try expect(abs(fullBottomTrigger.minX - screen.frame.minX) < 0.5, "\(position.label) full-width trigger should start at the screen edge")
            try expect(abs(fullBottomTrigger.width - screen.frame.width) < 0.5, "\(position.label) full-width trigger should cover the whole display bottom")
        case .left:
            try expect(abs(trigger.minX - screen.frame.minX) < 0.5, "left auto-hide trigger should touch the left screen edge")
            try expect(trigger.width >= 4, "left auto-hide trigger should have enough thickness to catch pointer entry")
        case .right:
            try expect(abs(trigger.maxX - screen.frame.maxX) < 0.5, "right auto-hide trigger should touch the right screen edge")
            try expect(trigger.width >= 4, "right auto-hide trigger should have enough thickness to catch pointer entry")
        }
    }
}

func validateAutoHideTriggerScreens() throws {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
        print("SKIP auto-hide trigger screens (no display)")
        return
    }

    var bottomSettings = DockingSettings.default
    bottomSettings.dockPosition = .bottomCenter
    let bottomScreens = AutoHideController.triggerScreens(
        for: bottomSettings,
        selectedScreen: screen,
        availableScreens: NSScreen.screens
    )
    try expect(
        bottomScreens.count == NSScreen.screens.count,
        "bottom auto-hide should install an edge trigger on every connected display"
    )
    try expect(
        !bottomScreens.isEmpty,
        "bottom auto-hide should still have at least one edge trigger when displays are available"
    )

    var leftSettings = DockingSettings.default
    leftSettings.dockPosition = .left
    let leftScreens = AutoHideController.triggerScreens(
        for: leftSettings,
        selectedScreen: screen,
        availableScreens: NSScreen.screens
    )
    try expect(
        leftScreens.count == 1 && leftScreens.first === screen,
        "side auto-hide should stay scoped to the selected display instead of creating edge strips everywhere"
    )

    let fallbackScreens = AutoHideController.triggerScreens(
        for: bottomSettings,
        selectedScreen: screen,
        availableScreens: []
    )
    try expect(
        fallbackScreens.count == 1 && fallbackScreens.first === screen,
        "bottom auto-hide should fall back to the selected display when AppKit reports no screen list"
    )
}

func validateDockingWindowCollectionBehavior() throws {
    let defaultBehavior = DockingWindowBehavior.collectionBehavior(for: .default)
    try expect(defaultBehavior.contains(.transient), "dock panels should be transient system-style surfaces")
    try expect(defaultBehavior.contains(.ignoresCycle), "dock panels should stay out of normal window cycling")
    try expect(defaultBehavior.contains(.canJoinAllSpaces), "default dock panels should be available on every Space")
    try expect(defaultBehavior.contains(.fullScreenAuxiliary), "default dock panels should be available in full-screen Spaces")

    var scopedSettings = DockingSettings.default
    scopedSettings.showOnAllSpaces = false
    scopedSettings.showOnFullScreenSpaces = false
    let scopedBehavior = DockingWindowBehavior.collectionBehavior(for: scopedSettings)

    // These toggles are user-facing escape hatches. If a workflow needs Docking
    // to stay scoped to the current desktop, turning them off must remove the
    // cross-Space flags while preserving the non-document panel semantics.
    try expect(scopedBehavior.contains(.transient), "scoped dock panels should remain transient")
    try expect(scopedBehavior.contains(.ignoresCycle), "scoped dock panels should still stay out of window cycling")
    try expect(!scopedBehavior.contains(.canJoinAllSpaces), "turning off all-Spaces should remove canJoinAllSpaces")
    try expect(!scopedBehavior.contains(.fullScreenAuxiliary), "turning off full-screen Spaces should remove fullScreenAuxiliary")
}

func validateAppleDockMirroring() throws {
    let suiteName = "docking.validation.apple-mirror.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppleDockMirror-\(UUID().uuidString)", isDirectory: true)
    let downloadsURL = root.appendingPathComponent("Downloads", isDirectory: true)
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)

    defaults.set(true, forKey: "autohide")
    defaults.set("right", forKey: "orientation")
    defaults.set(40.0, forKey: "tilesize")
    defaults.set(
        [
            [
                "tile-type": "file-tile",
                "tile-data": [
                    "bundle-identifier": "com.example.Foo",
                    "file-label": "Foo",
                    "file-data": [
                        "_CFURLString": URL(fileURLWithPath: "/Applications/Foo.app").absoluteString
                    ]
                ]
            ],
            [
                "tile-type": "directory-tile",
                "tile-data": [
                    "file-label": "Downloads"
                ]
            ]
        ],
        forKey: "persistent-apps"
    )
    defaults.set(
        [
            [
                "tile-type": "directory-tile",
                "tile-data": [
                    "file-label": "Downloads",
                    "displayas": 0,
                    "showas": 2,
                    "arrangement": 3,
                    "file-data": [
                        "_CFURLString": downloadsURL.absoluteString
                    ]
                ]
            ]
        ],
        forKey: "persistent-others"
    )

    var settings = DockingSettings.default
    let appliedFromDefaults = AppleDockPreferences.mirrorOriginalDock(into: &settings, savedValues: nil, dockDefaults: defaults)
    try expect(appliedFromDefaults, "Apple Dock mirror should apply readable defaults")
    try expect(settings.dockVisibility == .autoHide, "Apple Dock autohide should map to Docking visibility")
    try expect(settings.dockPosition == .right, "Apple Dock orientation should map to Docking position")
    try expect(settings.iconSize == 40.0, "Apple Dock tile size should map to Docking icon size")

    let savedValues: [String: DockPreferenceValue] = [
        "autohide": .bool(false),
        "orientation": .string("left"),
        "tilesize": .double(44.0)
    ]
    let appliedFromSnapshot = AppleDockPreferences.mirrorOriginalDock(into: &settings, savedValues: savedValues, dockDefaults: defaults)
    try expect(appliedFromSnapshot, "saved Apple Dock snapshot should override already-mutated Dock defaults")
    try expect(settings.dockVisibility == .alwaysVisible, "saved autohide should restore original visibility intent")
    try expect(settings.dockPosition == .left, "saved orientation should restore original Dock edge")
    try expect(settings.iconSize == 44.0, "saved tile size should restore original icon size")

    let items = AppleDockPreferences.persistentDockItems(from: defaults)
    try expect(items.count == 2, "Apple Dock mirror should import apps and folder stack tiles")
    try expect(items[0].kind == .application, "Apple Dock app tiles should remain application items")
    try expect(items[0].title == "Foo", "Apple Dock mirror should preserve app labels")
    try expect(items[0].bundleIdentifier == "com.example.Foo", "Apple Dock mirror should preserve bundle identifiers")
    try expect(items[0].url?.path == "/Applications/Foo.app", "Apple Dock mirror should preserve app URLs")
    try expect(items[1].kind == .folder, "Apple Dock persistent-others directory tiles should become folder items")
    try expect(items[1].title == "Downloads", "Apple Dock mirror should preserve folder labels")
    try expect(items[1].url?.path == downloadsURL.path, "Apple Dock mirror should preserve folder URLs")
    try expect(items[1].folderDisplayMode == .stack, "Apple Dock displayas should map to folder display mode")
    try expect(items[1].folderViewMode == .grid, "Apple Dock showas should map to folder view mode")
    try expect(items[1].folderSortMode == .dateModified, "Apple Dock arrangement should map to folder sort mode")
}

func validateAppCatalogRecognizesApplicationsAndFolders() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppCatalogValidation-\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("Sample.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let folderURL = root.appendingPathComponent("Projects", isDirectory: true)
    let plainFileURL = root.appendingPathComponent("NotSupported.txt")
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    try Data("nope".utf8).write(to: plainFileURL)

    let infoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>com.example.Sample</string>
      <key>CFBundleName</key>
      <string>Sample App</string>
    </dict>
    </plist>
    """
    try infoPlist.data(using: .utf8)?.write(to: contentsURL.appendingPathComponent("Info.plist"))

    let appItem = AppCatalogService.dockItemIfSupported(for: appURL)
    try expect(appItem?.kind == .application, "application bundle drops should create application items")
    try expect(appItem?.bundleIdentifier == "com.example.Sample", "application bundle drops should preserve bundle identifier")
    try expect(appItem?.title == "Sample App", "application bundle drops should use bundle display metadata")

    let folderItem = AppCatalogService.dockItemIfSupported(for: folderURL)
    try expect(folderItem?.kind == .folder, "plain directory drops should create folder stack items")
    try expect(folderItem?.title == "Projects", "folder drops should use folder display names")
    try expect(folderItem?.bundleIdentifier == nil, "folder stack items should not pretend to be applications")
    try expect(AppCatalogService.dockItemIfSupported(for: plainFileURL) == nil, "plain file drops should not create dock items yet")
}

func validateFolderStackPresentation() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let older = now.addingTimeInterval(-3_600)
    let entries = [
        FolderStackEntry(
            title: "Beta",
            url: URL(fileURLWithPath: "/tmp/Beta.txt"),
            isDirectory: false,
            kindDescription: "Plain Text",
            dateAdded: older,
            dateModified: older,
            dateCreated: older
        ),
        FolderStackEntry(
            title: "Alpha",
            url: URL(fileURLWithPath: "/tmp/Alpha.app"),
            isDirectory: true,
            kindDescription: "Application",
            dateAdded: now,
            dateModified: now,
            dateCreated: now
        )
    ]

    try expect(
        FolderStackService.sorted(entries, by: .name).map(\.title) == ["Alpha", "Beta"],
        "folder stacks should sort by localized name"
    )
    try expect(
        FolderStackService.sorted(entries, by: .dateModified).map(\.title) == ["Alpha", "Beta"],
        "folder stacks should put newest modified items first"
    )
    try expect(
        FolderStackService.sorted(entries, by: .kind).map(\.title) == ["Alpha", "Beta"],
        "folder stacks should group by kind before falling back to name"
    )

    let item = DockItem(
        kind: .folder,
        title: "Downloads",
        bundleIdentifier: nil,
        url: URL(fileURLWithPath: "/tmp/Downloads"),
        iconCacheKey: "folder:/tmp/Downloads",
        folderViewMode: .automatic
    )
    try expect(FolderStackPresentation.resolvedViewMode(for: item, entryCount: 4) == .fan, "small automatic folder stacks should use fan")
    try expect(FolderStackPresentation.resolvedViewMode(for: item, entryCount: 20) == .grid, "medium automatic folder stacks should use grid")
    try expect(FolderStackPresentation.resolvedViewMode(for: item, entryCount: 80) == .list, "large automatic folder stacks should use list")

    let downloadsURL = URL(fileURLWithPath: "/tmp/DockingValidation/Downloads", isDirectory: true)
    try expect(
        FolderStackService.isDownloadsFolder(downloadsURL, downloadsDirectory: downloadsURL),
        "Downloads folder detection should allow the caller to compare against a known Downloads URL"
    )
    try expect(
        SpecialFolderIconFactory.symbolName(forFolderAt: downloadsURL, downloadsDirectory: downloadsURL) == "arrow.down.circle.fill",
        "Downloads should use the Finder-style symbolic folder icon"
    )
    if let standardDownloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
        let standardDownloadsStackItem = DockItem(
            kind: .folder,
            title: "Downloads",
            bundleIdentifier: nil,
            url: standardDownloadsURL,
            iconCacheKey: "folder:\(standardDownloadsURL.path)",
            folderDisplayMode: .stack
        )
        try expect(
            FolderStackIconFactory.icon(for: standardDownloadsStackItem) == nil,
            "Downloads should bypass Docking's stack-preview composition so the Dock icon stays visually full-size"
        )
        let specialDownloadsIcon = SpecialFolderIconFactory.icon(for: standardDownloadsStackItem)
        try expect(
            specialDownloadsIcon?.size == NSSize(width: 256, height: 256),
            "Downloads should render a high-resolution Finder-style icon for the normal Dock tile"
        )
    }

    let recentSourceEntries = (0..<14).map { index in
        FolderStackEntry(
            title: "Item \(index)",
            url: URL(fileURLWithPath: "/tmp/DockingValidation/Downloads/Item-\(index)"),
            isDirectory: false,
            kindDescription: "File",
            dateAdded: now.addingTimeInterval(TimeInterval(index)),
            dateModified: nil,
            dateCreated: nil
        )
    }
    let recentDownloads = FolderStackService.recentDownloads(recentSourceEntries, limit: FolderStackService.downloadsInitialVisibleCount)
    try expect(recentDownloads.count == 12, "Downloads stacks should initially show 12 recent entries")
    try expect(
        Array(recentDownloads.map(\.title).prefix(3)) == ["Item 13", "Item 12", "Item 11"],
        "Downloads recent entries should be newest first"
    )
    try expect(recentDownloads.last?.title == "Item 2", "Downloads initial entries should drop older items beyond 12")
    let allRecentDownloads = FolderStackService.recentDownloads(recentSourceEntries)
    try expect(allRecentDownloads.count == 14, "Downloads panel data should keep older entries available for scroll reveal")
    try expect(allRecentDownloads.last?.title == "Item 0", "Downloads full recent list should preserve the oldest direct entry at the end")
    try expect(
        !FolderStackPanelView.shouldRevealMoreDownloads(
            isDownloadsStack: true,
            visibleCount: 12,
            totalCount: 24,
            isUserScroll: false,
            contentOffsetY: 0,
            visibleMaxY: 320,
            contentHeight: 340
        ),
        "Downloads should not load the next page before the user scrolls"
    )
    try expect(
        FolderStackPanelView.shouldRevealMoreDownloads(
            isDownloadsStack: true,
            visibleCount: 12,
            totalCount: 24,
            isUserScroll: true,
            contentOffsetY: 16,
            visibleMaxY: 320,
            contentHeight: 380
        ),
        "Downloads should load another page after the user scrolls near the current end"
    )
    try expect(
        !FolderStackPanelView.shouldRevealMoreDownloads(
            isDownloadsStack: true,
            visibleCount: 12,
            totalCount: 24,
            isUserScroll: true,
            contentOffsetY: 16,
            visibleMaxY: 180,
            contentHeight: 420
        ),
        "Downloads should not load another page while the user is still far from the current end"
    )
    try expect(
        !FolderStackPanelView.shouldRevealMoreDownloads(
            isDownloadsStack: true,
            visibleCount: 12,
            totalCount: 24,
            isUserScroll: false,
            contentOffsetY: 16,
            visibleMaxY: 320,
            contentHeight: 380
        ),
        "Downloads should ignore layout-only geometry changes even when the current content is short"
    )
    let topVisibleRange = FolderStackPanelView.downloadsVisibleRange(
        visibleCount: 48,
        totalCount: 1_500,
        contentOffsetY: 0,
        visibleMaxY: 320,
        contentHeight: 1_280
    )
    let lowerVisibleRange = FolderStackPanelView.downloadsVisibleRange(
        visibleCount: 48,
        totalCount: 1_500,
        contentOffsetY: 640,
        visibleMaxY: 960,
        contentHeight: 1_280
    )
    try expect(
        topVisibleRange == 1...12,
        "Downloads header should return toward the first visible page when the user scrolls back up"
    )
    try expect(
        lowerVisibleRange == 25...36,
        "Downloads header should show the current loaded range, not only the total number of loaded entries"
    )

    try expect(
        SpecialFolderIconFactory.symbolName(
            forFolderAt: URL(fileURLWithPath: "/tmp/DockingValidation/Documents", isDirectory: true),
            downloadsDirectory: downloadsURL
        ) == nil,
        "ordinary folders should keep folder or stack-preview icons"
    )
}

func validateFolderStackPanelDismissHitTesting() throws {
    let panelFrame = NSRect(x: 100, y: 100, width: 360, height: 320)
    let folderIconFrame = NSRect(x: 260, y: 40, width: 58, height: 58)

    // The folder icon is intentionally exempt from the generic outside-click
    // closer. A seemingly simpler implementation would close every floating
    // stack before the SwiftUI dock item receives the click, but that can turn
    // a user's second click into "close, then immediately reopen" instead of
    // the Apple-Dock-style toggle the app promises.
    try expect(
        !FolderStackPanelController.shouldDismissPointerEvent(
            pointerLocation: NSPoint(x: panelFrame.midX, y: panelFrame.midY),
            panelFrame: panelFrame,
            anchorFrame: folderIconFrame
        ),
        "clicks inside the folder stack panel should not dismiss it"
    )
    try expect(
        !FolderStackPanelController.shouldDismissPointerEvent(
            pointerLocation: NSPoint(x: folderIconFrame.midX, y: folderIconFrame.midY),
            panelFrame: panelFrame,
            anchorFrame: folderIconFrame
        ),
        "clicking the source folder should be left for toggle(item:) so a second click closes the stack"
    )
    try expect(
        FolderStackPanelController.shouldDismissPointerEvent(
            pointerLocation: NSPoint(x: 20, y: 20),
            panelFrame: panelFrame,
            anchorFrame: folderIconFrame
        ),
        "ordinary outside clicks should still dismiss folder stack panels"
    )
    try expect(
        FolderStackPanelController.shouldDismissPointerEvent(
            pointerLocation: NSPoint(x: 20, y: 20),
            panelFrame: panelFrame,
            anchorFrame: nil
        ),
        "outside clicks should still dismiss when the folder icon frame is unavailable"
    )
}

func validateFolderDropService() throws {
    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: "/private/tmp/DockingValidation/FolderDrop", isDirectory: true)
    try? fileManager.removeItem(at: root)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

    let target = root.appendingPathComponent("Target", isDirectory: true)
    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)

    let copySource = root.appendingPathComponent("copy-source.txt")
    try "copy".write(to: copySource, atomically: true, encoding: .utf8)
    let copied = try FolderDropService.performDrop(
        sourceURL: copySource,
        into: target,
        modifierFlags: [.option],
        fileManager: fileManager
    )
    try expect(fileManager.fileExists(atPath: copySource.path), "Option-dropping onto a Dock folder should copy without removing the source")
    try expect(fileManager.fileExists(atPath: copied.path), "Option-dropping onto a Dock folder should create the destination item")

    let moveSource = root.appendingPathComponent("move-source.txt")
    try "move".write(to: moveSource, atomically: true, encoding: .utf8)
    try expect(
        FolderDropService.operation(sourceURL: moveSource, targetFolderURL: target, modifierFlags: []) == .move,
        "same-volume Dock folder drops should default to move, matching Finder-style drag semantics"
    )
    let moved = try FolderDropService.performDrop(
        sourceURL: moveSource,
        into: target,
        modifierFlags: [],
        fileManager: fileManager
    )
    try expect(!fileManager.fileExists(atPath: moveSource.path), "same-volume Dock folder drops should remove the source after moving")
    try expect(fileManager.fileExists(atPath: moved.path), "same-volume Dock folder drops should create the moved destination item")

    let duplicateSource = root.appendingPathComponent("duplicate.txt")
    let duplicateDestination = target.appendingPathComponent("duplicate.txt")
    try "source".write(to: duplicateSource, atomically: true, encoding: .utf8)
    try "existing".write(to: duplicateDestination, atomically: true, encoding: .utf8)
    do {
        _ = try FolderDropService.performDrop(sourceURL: duplicateSource, into: target, modifierFlags: [.option], fileManager: fileManager)
        throw ValidationFailure(description: "folder drops should not overwrite an existing item")
    } catch FolderDropError.destinationAlreadyExists {
        // Expected: Finder would ask the user how to resolve the collision. The
        // 0.0.0 Docking implementation refuses silent overwrite instead.
    }

    let sourceFolder = root.appendingPathComponent("SourceFolder", isDirectory: true)
    let nestedTarget = sourceFolder.appendingPathComponent("Nested", isDirectory: true)
    try fileManager.createDirectory(at: nestedTarget, withIntermediateDirectories: true)
    do {
        _ = try FolderDropService.performDrop(sourceURL: sourceFolder, into: nestedTarget, modifierFlags: [.option], fileManager: fileManager)
        throw ValidationFailure(description: "folder drops should reject copying a folder into itself")
    } catch FolderDropError.droppingFolderIntoItself {
        // Expected: recursive folder copies are invalid and should produce a
        // clear Docking-level error before FileManager returns a low-level one.
    }
}

func validateRunningApplicationMatcher() throws {
    let item = DockItem(
        title: "Editor",
        bundleIdentifier: "com.example.Editor",
        url: URL(fileURLWithPath: "/Applications/Editor.app"),
        iconCacheKey: "com.example.Editor"
    )

    try expect(
        RunningApplicationMatcher.matches(
            item: item,
            applicationBundleIdentifier: "com.example.Editor",
            applicationBundleURL: URL(fileURLWithPath: "/Different/Editor.app")
        ),
        "running-app process actions should prefer bundle identity when it is available"
    )
    try expect(
        !RunningApplicationMatcher.matches(
            item: item,
            applicationBundleIdentifier: "com.example.Other",
            applicationBundleURL: URL(fileURLWithPath: "/Different/Editor.app")
        ),
        "running-app process actions should not match unrelated bundle identifiers"
    )

    let pathOnlyItem = DockItem(
        title: "Unsigned Tool",
        bundleIdentifier: nil,
        url: URL(fileURLWithPath: "/Applications/Unsigned Tool.app"),
        iconCacheKey: "/Applications/Unsigned Tool.app"
    )
    try expect(
        RunningApplicationMatcher.matches(
            item: pathOnlyItem,
            applicationBundleIdentifier: nil,
            applicationBundleURL: URL(fileURLWithPath: "/Applications/Unsigned Tool.app")
        ),
        "running-app process actions should fall back to app path for apps without bundle identifiers"
    )
}

func validateSettingsStore() throws {
    let suiteName = "docking.validation.\(UUID().uuidString)"
    let dockSuiteName = "docking.validation.apple-dock.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let appleDockDefaults = UserDefaults(suiteName: dockSuiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        appleDockDefaults.removePersistentDomain(forName: dockSuiteName)
    }

    appleDockDefaults.set(false, forKey: "autohide")
    let store = SettingsStore(defaults: defaults, appleDockDefaults: appleDockDefaults)
    try expect(store.load().dockVisibility == .alwaysVisible, "first-run settings should mirror visible Apple Dock")

    appleDockDefaults.set(true, forKey: "autohide")
    defaults.removePersistentDomain(forName: suiteName)
    try expect(store.load().dockVisibility == .autoHide, "first-run settings should mirror auto-hide Apple Dock")

    var settings = DockingSettings.default
    settings.dockVisibility = .alwaysVisible
    settings.unpinnedRunningAppVisibility = .hidden
    settings.keepAboveOtherWindows = false
    settings.calendarWidgetSizePreset = .compact
    settings.weatherWidgetSizePreset = .detailed
    store.save(settings)
    try expect(store.load() == settings, "settings should round-trip through UserDefaults")
}

func validateSettingsRefreshKeys() throws {
    var appearanceOnly = DockingSettings.default
    appearanceOnly.dockSize = 88
    appearanceOnly.iconSize = 60
    appearanceOnly.calendarWidgetSizePreset = .detailed
    appearanceOnly.weatherWidgetSizePreset = .compact
    appearanceOnly.liquidGlassSurfaceStyle = .dense
    appearanceOnly.dockPosition = .left
    appearanceOnly.unpinnedRunningAppVisibility = .hidden
    appearanceOnly.keepAboveOtherWindows = false
    appearanceOnly.calendarShowsLocation = false
    appearanceOnly.weatherShowsHumidity = false
    appearanceOnly.weatherShowsAQI = false

    try expect(appearanceOnly.calendarRefreshKey == DockingSettings.default.calendarRefreshKey, "appearance-only settings should not trigger calendar data refresh")
    try expect(appearanceOnly.weatherRefreshKey == DockingSettings.default.weatherRefreshKey, "appearance-only settings should not trigger weather data refresh")

    var calendarData = DockingSettings.default
    calendarData.calendarLookaheadDays = 14
    try expect(calendarData.calendarRefreshKey != DockingSettings.default.calendarRefreshKey, "calendar query settings should trigger calendar data refresh")

    var weatherData = DockingSettings.default
    weatherData.weatherManualLocation = "Tokyo"
    try expect(weatherData.weatherRefreshKey != DockingSettings.default.weatherRefreshKey, "weather request settings should trigger weather data refresh")
}

func validateUnpinnedRunningAppResolver() throws {
    let pinned = DockItem(
        title: "Pinned Editor",
        bundleIdentifier: "com.example.editor",
        url: URL(fileURLWithPath: "/Applications/Pinned Editor.app"),
        iconCacheKey: "com.example.editor"
    )
    let runningPinned = DockItem(
        title: "Pinned Editor",
        bundleIdentifier: "com.example.editor",
        url: URL(fileURLWithPath: "/Applications/Pinned Editor.app"),
        iconCacheKey: "com.example.editor",
        isPinned: false
    )
    let runningTransient = DockItem(
        title: "Zed",
        bundleIdentifier: "dev.zed.Zed",
        url: URL(fileURLWithPath: "/Applications/Zed.app"),
        iconCacheKey: "dev.zed.Zed",
        isPinned: false
    )
    let duplicateTransient = DockItem(
        title: "Zed",
        bundleIdentifier: "dev.zed.Zed",
        url: URL(fileURLWithPath: "/Applications/Zed.app"),
        iconCacheKey: "dev.zed.Zed",
        isPinned: false
    )

    let visible = DockRunningItemResolver.unpinnedRunningItems(
        pinnedItems: [pinned],
        runningItems: [runningPinned, runningTransient, duplicateTransient],
        visibility: .separated
    )
    try expect(visible == [runningTransient], "unpinned running apps should appear once in their own section")

    let hidden = DockRunningItemResolver.unpinnedRunningItems(
        pinnedItems: [pinned],
        runningItems: [runningTransient],
        visibility: .hidden
    )
    try expect(hidden.isEmpty, "unpinned running apps should be hideable")
}

@MainActor
func validateExplicitAppReorderControls() async throws {
    let suiteName = "docking.validation.reorder.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let appListURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockItemsReorderValidation-\(UUID().uuidString).json")
    let weatherCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherReorderValidation-\(UUID().uuidString).json")
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: appListURL)
        try? FileManager.default.removeItem(at: weatherCacheURL)
    }

    let model = DockingAppModel(
        settingsStore: SettingsStore(defaults: defaults),
        appListStore: AppListStore(fileURL: appListURL),
        calendarViewModel: CalendarWidgetViewModel(provider: EmptyCalendarProvider()),
        weatherViewModel: WeatherWidgetViewModel(
            provider: StaticWeatherProvider(snapshot: validationWeatherSnapshot()),
            cache: WeatherCache(fileURL: weatherCacheURL)
        )
    )
    let first = DockItem(title: "First", bundleIdentifier: "com.example.first", url: nil, iconCacheKey: "first")
    let second = DockItem(title: "Second", bundleIdentifier: "com.example.second", url: nil, iconCacheKey: "second")
    let third = DockItem(title: "Third", bundleIdentifier: "com.example.third", url: nil, iconCacheKey: "third")

    model.dockItems = [first, second, third]

    model.moveDockItem(second, by: -1)
    try expect(model.dockItems.map(\.title) == ["Second", "First", "Third"], "Control Center move-up should move exactly one row")

    model.moveDockItem(first, by: 1)
    try expect(model.dockItems.map(\.title) == ["Second", "Third", "First"], "Control Center move-down should move exactly one row")

    // Boundary moves are no-ops by design: disabled buttons should already
    // prevent them in the UI, but the model still guards direct calls so a
    // future settings surface cannot accidentally rotate the app list.
    model.moveDockItem(second, by: -1)
    model.moveDockItem(first, by: 1)
    try expect(model.dockItems.map(\.title) == ["Second", "Third", "First"], "Control Center reorder should not wrap at list boundaries")
}

func validateDockWindowLevelToggle() throws {
    var settings = DockingSettings.default
    settings.keepAboveOtherWindows = true
    try expect(DockPanelController.windowLevel(for: settings) == .floating, "default dock panel should float above ordinary windows")

    settings.keepAboveOtherWindows = false
    try expect(DockPanelController.windowLevel(for: settings) == .normal, "always-on-top toggle should allow ordinary window level")
}

func validateDefaultSettingsFitEditableRanges() throws {
    let settings = DockingSettings.default

    try expect(DockingSettingLimits.autoHideDelay.contains(settings.autoHideDelay), "default auto-hide delay should be editable in Control Center")
    try expect(abs(DockingSettingLimits.autoHideDelay.lowerBound - 0.05) < 0.000_001, "auto-hide delay should allow near-instant hiding for users who prefer a faster dock")
    try expect(abs(DockingSettingLimits.autoHideDelayStep - 0.05) < 0.000_001, "auto-hide delay should expose fine-grained subsecond adjustment")
    try expect(DockingSettingLimits.dockSize.contains(settings.dockSize), "default dock size should be editable in Control Center")
    try expect(DockingSettingLimits.iconSize.contains(settings.iconSize), "default icon size should be editable in Control Center")
    try expect(WidgetSizePreset.allCases.contains(settings.calendarWidgetSizePreset), "default calendar widget size should be selectable in Control Center")
    try expect(WidgetSizePreset.allCases.contains(settings.weatherWidgetSizePreset), "default weather widget size should be selectable in Control Center")
    try expect(DockingSettingLimits.spacing.contains(settings.spacing), "default spacing should be editable in Control Center")
    try expect(LiquidGlassSurfaceStyle.allCases.contains(settings.liquidGlassSurfaceStyle), "default Liquid Glass style should be selectable in Control Center")
    try expect(DockScalePreset.nearest(to: settings) == .comfortable, "default dock scale should map to a user-facing preset")
    try expect(settings.calendarWidgetSizePreset == .standard, "default calendar widget size should map to a user-facing preset")
    try expect(settings.weatherWidgetSizePreset == .standard, "default weather widget size should map to a user-facing preset")
    try expect(WidgetSizePreset.detailed.width(iconSize: settings.iconSize) > WidgetSizePreset.standard.width(iconSize: settings.iconSize), "detailed widget preset should expose a wider dock tile")
    try expect(WidgetSizePreset.compact.width(iconSize: settings.iconSize) < WidgetSizePreset.standard.width(iconSize: settings.iconSize), "compact widget preset should remain narrower than standard")
    try expect(WidgetSizePreset.detailed.width(iconSize: settings.iconSize) >= 180, "detailed widget preset should have enough horizontal room for side-by-side context")
    try expect(WidgetSizePreset.detailed.width(iconSize: settings.iconSize) <= 205, "default detailed widget width should not create unowned blank space around concise weather context")
    var detailedWidgets = settings
    detailedWidgets.calendarWidgetSizePreset = .detailed
    detailedWidgets.weatherWidgetSizePreset = .detailed
    try expect(detailedWidgets.widgetTileHeight <= detailedWidgets.dockSize - 10, "detailed widget presets must not increase dock vertical occupation")
    try expect(DockingSettingLimits.calendarLookaheadDays.contains(settings.calendarLookaheadDays), "default calendar lookahead should be editable in Control Center")
    try expect(DockingSettingLimits.calendarMaxEventCount.contains(settings.calendarMaxEventCount), "default calendar max events should be editable in Control Center")
    try expect(DockingSettingLimits.weatherRefreshIntervalMinutes.contains(settings.weatherRefreshIntervalMinutes), "default weather refresh interval should be editable in Control Center")
    try expect(
        settings.weatherRefreshIntervalMinutes.isMultiple(of: DockingSettingLimits.weatherRefreshIntervalStep),
        "default weather refresh interval should align with the Control Center stepper"
    )
}

func validateDockWidgetMetrics() throws {
    let persistedSmallSize = 44.0
    let editableMinimumSize = DockingSettingLimits.widgetReadableMinimum

    for height in [persistedSmallSize, editableMinimumSize, DockingSettings.default.widgetTileHeight] {
        let metrics = DockWidgetMetrics(width: height, height: height)

        // This guards the specific UI regression the user saw: when SwiftUI was
        // allowed to infer the widget's internal heights, the Calendar icon and
        // labels could occupy the same pixels at compact sizes. The invariant is
        // intentionally mechanical because screenshots are still the final UI
        // check, while this catches impossible geometry during fast validation.
        try expect(metrics.allocatedHeight <= height + 0.001, "compact widget layout should not over-allocate vertical space at \(height)pt")
        try expect(metrics.iconExtent > 0, "compact widget should always reserve an icon row")
        try expect(metrics.contentHeight > 0, "compact widget should always reserve a text content row")
        try expect(metrics.cornerRadius < height / 2, "compact widget corner radius should not collapse the rounded rectangle at \(height)pt")
    }

    let wideMetrics = DockWidgetMetrics(
        width: WidgetSizePreset.detailed.width(iconSize: DockingSettings.default.iconSize),
        height: DockingSettings.default.widgetTileHeight
    )
    try expect(wideMetrics.usesHorizontalLayout, "wide widget presets should use horizontal layout to spend width instead of height")
    try expect(wideMetrics.allocatedHeight <= DockingSettings.default.widgetTileHeight + 0.001, "wide widget layout should stay within the dock tile height")
}

func validateDockItemTerminationMenuPolicy() throws {
    try expect(DockTerminationMenuPolicy.title(optionKeyIsPressed: false) == "Quit", "normal Dock item menu should expose Quit")
    try expect(DockTerminationMenuPolicy.title(optionKeyIsPressed: true) == "Force Quit...", "Option-modified Dock item menu should replace Quit with Force Quit")
    try expect(
        DockTerminationMenuPolicy.title(optionKeyIsPressed: false) != DockTerminationMenuPolicy.title(optionKeyIsPressed: true),
        "Quit and Force Quit should be mutually exclusive menu titles"
    )
}

func validateWeatherDockLocationDisplay() throws {
    var manualSettings = DockingSettings.default
    manualSettings.weatherUsesCurrentLocation = false
    manualSettings.weatherManualLocation = "Setagaya"
    try expect(
        WeatherDockLocationDisplay.name(snapshotLocationName: "Setagaya City, Tokyo, Japan", settings: manualSettings) == "Setagaya",
        "manual weather city should be shown as the user's concise dock label"
    )

    manualSettings.weatherManualLocation = "   "
    try expect(
        WeatherDockLocationDisplay.name(snapshotLocationName: "Setagaya-ku, Tokyo, Japan", settings: manualSettings) == "Setagaya",
        "cached/manual weather without a configured city should still compact provider-expanded ward names"
    )

    var currentLocationSettings = DockingSettings.default
    currentLocationSettings.weatherUsesCurrentLocation = true
    currentLocationSettings.weatherManualLocation = "Tokyo"
    try expect(
        WeatherDockLocationDisplay.name(snapshotLocationName: "Setagaya City, Tokyo, Japan", settings: currentLocationSettings) == "Setagaya",
        "current-location weather should compact the loaded location instead of using an unrelated manual fallback label"
    )

    currentLocationSettings.weatherManualLocation = "Setagaya"
    try expect(
        WeatherDockLocationDisplay.name(snapshotLocationName: "Setagaya City, Tokyo, Japan", settings: currentLocationSettings) == "Setagaya",
        "manual fallback weather should still use the user's concise city label when the snapshot matches it"
    )
}

func validateCalendarWidgetPresentation() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 28, hour: 13, minute: 40))!
    let end = calendar.date(from: DateComponents(year: 2026, month: 6, day: 28, hour: 17, minute: 30))!
    let event = CalendarEventSummary(
        id: "validation",
        title: "Design review",
        calendarName: "Work",
        startDate: start,
        endDate: end,
        location: "Studio"
    )

    let presentation = CalendarDockPresentation(
        event: event,
        state: .loaded,
        showsLocation: true,
        calendar: calendar,
        now: start
    )
    try expect(presentation.compactPrimary == "13:40", "compact calendar widget should preserve the next event start time")
    try expect(presentation.primary == "13:40-17:30", "standard/detailed calendar widget should show the event range when space allows")
    try expect(presentation.secondary == "Design review", "calendar widget should keep the event title as the second read")
    try expect(presentation.tertiary?.contains("Today") == true, "detailed calendar widget should spend width on day context")
    try expect(presentation.tertiary?.contains("Studio") == true, "detailed calendar widget should prefer location when the user enabled it")

    let calendarOnlyPresentation = CalendarDockPresentation(
        event: event,
        state: .loaded,
        showsLocation: false,
        calendar: calendar,
        now: start
    )
    try expect(calendarOnlyPresentation.tertiary?.contains("Work") == true, "calendar widget should fall back to calendar name when location is hidden")

    let emptyPresentation = CalendarDockPresentation(event: nil, state: .empty, showsLocation: true, calendar: calendar, now: start)
    try expect(emptyPresentation.primary == "Today", "empty calendar widget should stay calm instead of showing a diagnostic label")
    try expect(emptyPresentation.secondary == "No events", "empty calendar widget should tell the user the schedule is clear")
}

func validateWeatherWidgetPresentation() throws {
    try expect(
        WeatherConditionTone.resolve(conditionCode: 61, symbolName: "cloud.rain") == .rain,
        "rainy weather should use the rain visual tone"
    )
    try expect(
        WeatherConditionTone.resolve(conditionCode: 0, symbolName: "sun.max") == .clear,
        "clear weather should use the clear visual tone"
    )
    try expect(
        WeatherConditionTone.resolve(conditionCode: nil, symbolName: "cloud.bolt.rain") == .storm,
        "symbol-only storm snapshots should still get a distinct visual tone"
    )
    try expect(
        WeatherWidgetSymbol.name(for: "cloud.rain") == "cloud.rain.fill",
        "weather widgets should prefer filled system variants for small multicolor icons"
    )

    var settings = DockingSettings.default
    settings.weatherUsesCurrentLocation = false
    settings.weatherManualLocation = "Setagaya"
    settings.weatherShowsHumidity = true

    var snapshot = validationWeatherSnapshot(locationName: "Setagaya City, Tokyo, Japan")
    snapshot.current = CurrentWeatherSummary(
        temperature: 21,
        feelsLike: 20,
        conditionCode: 61,
        conditionLabel: "Drizzle",
        symbolName: "cloud.rain"
    )
    snapshot.humidity = 0.96
    snapshot.daily = [
        DailyWeatherSummary(
            date: Date(timeIntervalSince1970: 1_000),
            high: 26,
            low: 20,
            conditionCode: 61,
            symbolName: "cloud.rain"
        )
    ]

    let presentation = WeatherDockPresentation(snapshot: snapshot, state: .loaded, settings: settings)
    try expect(presentation.primary.contains("21"), "weather widget should make temperature the primary label")
    try expect(presentation.secondary == "Drizzle", "weather widget should keep the condition readable without parsing a combined label")
    try expect(presentation.tertiary?.contains("Setagaya") == true, "detailed weather widget should keep the concise location as supporting context")
    try expect(presentation.tertiary?.contains("H 26") == true, "detailed weather widget should include today's high temperature")
    try expect(presentation.tertiary?.contains("L 20") == true, "detailed weather widget should include today's low temperature")
    try expect(presentation.tertiary?.contains("Humidity 96%") == true, "detailed weather widget should use wider tiles for useful weather context")
    try expect(presentation.detailLines.count == 3, "detailed weather widget should keep the dock side column to three readable lines")
    try expect(presentation.tone == .rain, "weather widget should color the icon from the current weather semantics")
    try expect(presentation.symbolName == "cloud.rain.fill", "weather widget should use the filled rain symbol for native dock legibility")
}

func validateWeatherCodeMapping() throws {
    // Open-Meteo's 1/2/3 codes are deliberately adjacent but semantically
    // distinct. This protects the fallback provider from regressing to the
    // older broad `1...3` mapping, which made fully cloudy/overcast weather
    // show the same sun-bearing symbol as partly cloudy weather.
    try expect(WeatherCodeMapping.label(for: 1) == "Mostly Clear", "Open-Meteo code 1 should not be labeled as generic cloudy weather")
    try expect(WeatherCodeMapping.symbolName(for: 1) == "sun.max", "Open-Meteo code 1 should preserve mostly-clear semantics")
    try expect(WeatherCodeMapping.label(for: 2) == "Partly Cloudy", "Open-Meteo code 2 should stay distinct from overcast conditions")
    try expect(WeatherCodeMapping.symbolName(for: 2) == "cloud.sun", "Open-Meteo code 2 is the only clear/cloudy fallback case that should show both cloud and sun")
    try expect(WeatherCodeMapping.label(for: 3) == "Cloudy", "Open-Meteo code 3 should read as cloudy/overcast in the dock")
    try expect(WeatherCodeMapping.symbolName(for: 3) == "cloud", "Open-Meteo code 3 should not render a sun-bearing symbol")
}

func validateOpenMeteoAirQualityLabels() throws {
    try expect(OpenMeteoAirQualityFormatter.usAQILabel(nil) == nil, "missing AQI should hide the air-quality row")
    try expect(OpenMeteoAirQualityFormatter.usAQILabel(-1) == nil, "invalid negative AQI should not be shown")
    try expect(OpenMeteoAirQualityFormatter.usAQILabel(42.4) == "42 Good", "good AQI should include the rounded value and category")
    try expect(OpenMeteoAirQualityFormatter.usAQILabel(86) == "86 Moderate", "moderate AQI should include the category")
    try expect(OpenMeteoAirQualityFormatter.usAQILabel(125) == "125 Sensitive", "sensitive-group AQI should stay compact for the widget row")
    try expect(OpenMeteoAirQualityFormatter.usAQILabel(175) == "175 Unhealthy", "unhealthy AQI should include the category")
    try expect(OpenMeteoAirQualityFormatter.usAQILabel(250) == "250 Very unhealthy", "very unhealthy AQI should remain readable")
    try expect(OpenMeteoAirQualityFormatter.usAQILabel(350) == "350 Hazardous", "hazardous AQI should include the category")
}

func validateWeatherDataSourceLabels() throws {
    try expect(
        WeatherDataSource.weatherKit.controlCenterLabel == "Apple WeatherKit",
        "WeatherKit snapshots should identify the Apple provider in Control Center"
    )
    try expect(
        WeatherDataSource.openMeteo.controlCenterLabel == "Open-Meteo",
        "Open-Meteo snapshots should report the loaded provider without inferring why fallback happened"
    )
    try expect(
        WeatherDataSource.mock.controlCenterLabel == "Debug mock",
        "debug-only weather should never be confused with a production provider"
    )
}

@MainActor
func validateSettingsPersistenceIsDebounced() async throws {
    let suiteName = "docking.validation.debounce.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let appListURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockItemsValidation-\(UUID().uuidString).json")
    let weatherCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCacheDebounceValidation-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: appListURL)
        try? FileManager.default.removeItem(at: weatherCacheURL)
    }

    let store = SettingsStore(defaults: defaults)
    let model = DockingAppModel(
        settingsStore: store,
        appListStore: AppListStore(fileURL: appListURL),
        calendarViewModel: CalendarWidgetViewModel(provider: EmptyCalendarProvider()),
        weatherViewModel: WeatherWidgetViewModel(
            provider: StaticWeatherProvider(snapshot: validationWeatherSnapshot()),
            cache: WeatherCache(fileURL: weatherCacheURL)
        )
    )

    var first = model.settings
    first.dockSize = 80
    model.settings = first

    var second = model.settings
    second.dockSize = 81
    model.settings = second

    try expect(store.load().dockSize == DockingSettings.default.dockSize, "settings should not persist every transient slider value immediately")
    try await Task.sleep(nanoseconds: 900_000_000)
    try expect(store.load().dockSize == 81, "debounced settings persistence should save the latest visible value")
}

@MainActor
func validateWidgetRefreshCancellation() async throws {
    let calendarViewModel = CalendarWidgetViewModel(provider: DelayedCalendarProvider())
    let calendarTask = Task {
        await calendarViewModel.refresh(settings: .default, reason: "validation")
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    try expect(calendarViewModel.state == .loading, "calendar refresh should enter loading before cancellation")
    calendarViewModel.cancelRefresh()
    _ = await calendarTask.result
    try expect(calendarViewModel.state == .idle, "cancelled calendar refresh should not publish a late loaded/error state")

    let weatherCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCancelValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: weatherCacheURL) }

    let weatherViewModel = WeatherWidgetViewModel(
        provider: DelayedWeatherProvider(),
        cache: WeatherCache(fileURL: weatherCacheURL)
    )
    var weatherSettings = DockingSettings.default
    weatherSettings.weatherManualLocation = "Tokyo"
    let weatherTask = Task {
        await weatherViewModel.refresh(settings: weatherSettings, force: true)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    try expect(weatherViewModel.state == .loading, "weather refresh should enter loading before cancellation")
    weatherViewModel.cancelRefresh()
    _ = await weatherTask.result
    try expect(weatherViewModel.state == .idle, "cancelled weather refresh should not publish a late loaded/error state")
}

@MainActor
func validateWidgetTaskLifecycle() async throws {
    let calendarViewModel = CalendarWidgetViewModel(provider: CountingCalendarProvider())
    await calendarViewModel.refresh(settings: .default, reason: "validation-complete")
    try expect(!calendarViewModel.isRefreshing, "completed calendar refresh should release its task reference")

    await calendarViewModel.refreshAvailableCalendars(settings: .default)
    try expect(!calendarViewModel.isLoadingSources, "completed calendar source load should release its task reference")

    let weatherCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherLifecycleValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: weatherCacheURL) }

    let weatherViewModel = WeatherWidgetViewModel(
        provider: StaticWeatherProvider(snapshot: validationWeatherSnapshot(locationName: "Lifecycle")),
        cache: WeatherCache(fileURL: weatherCacheURL)
    )
    var settings = DockingSettings.default
    settings.weatherManualLocation = "Tokyo"

    await weatherViewModel.refresh(settings: settings, force: true)
    try expect(!weatherViewModel.isRefreshing, "completed weather refresh should release its task reference")
}

@MainActor
func validateCalendarLaunchDoesNotRequestPermission() async throws {
    let provider = CountingCalendarProvider(authorizationState: .notDetermined)
    let viewModel = CalendarWidgetViewModel(provider: provider)

    await viewModel.refreshIfNeeded(settings: .default)

    try expect(provider.upcomingEventRequestCount == 0, "launch/stale calendar refresh should not request EventKit permission")
    try expect(provider.availableCalendarRequestCount == 0, "launch/stale calendar refresh should not enumerate calendars before permission")
    try expect(viewModel.compactText == ("Access", "Calendar"), "calendar compact widget should show a permission state instead of claiming there are no events")
    try expect(viewModel.nextEventLine == "Calendar access has not been granted yet", "calendar detail header should explain missing access before events are loaded")
}

@MainActor
func validateDisabledCalendarIgnoresStoreChanges() async throws {
    let provider = CountingCalendarProvider()
    let viewModel = CalendarWidgetViewModel(provider: provider)

    var disabledSettings = DockingSettings.default
    disabledSettings.calendarEnabled = false
    viewModel.disable(settings: disabledSettings)

    await viewModel.refresh(settings: disabledSettings, reason: "validation-disabled")
    try expect(provider.upcomingEventRequestCount == 0, "disabled calendar widget should ignore direct refresh calls")

    await viewModel.refreshAvailableCalendars(settings: disabledSettings)
    try expect(provider.availableCalendarRequestCount == 0, "disabled calendar widget should ignore calendar source refresh calls")

    NotificationCenter.default.post(name: provider.changeNotificationName, object: provider.changeNotificationObject)
    try await Task.sleep(nanoseconds: 100_000_000)

    try expect(provider.upcomingEventRequestCount == 0, "disabled calendar widget should ignore EventKit store-change notifications")
}

@MainActor
func validateCalendarDeniedPublishesPermissionState() async throws {
    let provider = ThrowingCalendarProvider(
        authorizationState: .denied,
        error: CalendarProviderError.denied
    )
    let viewModel = CalendarWidgetViewModel(provider: provider)

    await viewModel.refreshIfNeeded(settings: .default)

    // Permission denial is an ordinary user choice, not an exceptional app
    // state. The launch/stale path should therefore publish explicit disabled
    // copy without probing EventKit again; otherwise a denied Calendar account
    // can look like an empty day or keep surfacing avoidable provider work.
    try expect(provider.upcomingEventRequestCount == 0, "denied calendar launch refresh should not request events")
    try expect(provider.availableCalendarRequestCount == 0, "denied calendar launch refresh should not enumerate calendars")
    try expect(viewModel.state == .permissionDenied, "denied calendar authorization should publish the event permission state")
    try expect(viewModel.sourceState == .permissionDenied, "denied calendar authorization should also disable source loading")
    try expect(viewModel.compactText == ("Off", "Calendar"), "denied calendar compact widget should not look like an empty calendar")
    try expect(viewModel.nextEventLine == "Calendar access is off", "denied calendar detail header should explain the permission state")

    await viewModel.refresh(settings: .default, reason: "validation-denied")
    try expect(provider.upcomingEventRequestCount == 1, "manual denied calendar refresh should make one provider attempt")
    try expect(viewModel.state == .permissionDenied, "manual denied calendar refresh should keep the permission state")

    await viewModel.refreshAvailableCalendars(settings: .default)
    try expect(provider.availableCalendarRequestCount == 1, "manual denied source refresh should make one provider attempt")
    try expect(viewModel.sourceState == .permissionDenied, "manual denied source refresh should keep source permissions explicit")
}

@MainActor
func validateCalendarRestrictedPublishesPermissionState() async throws {
    let provider = ThrowingCalendarProvider(
        authorizationState: .restricted,
        error: CalendarProviderError.restricted
    )
    let viewModel = CalendarWidgetViewModel(provider: provider)

    await viewModel.refreshIfNeeded(settings: .default)

    // System policy restrictions are not fetch errors. They need their own
    // state so the dock tile, detail panel, and source picker can all explain
    // why Calendar data is unavailable without implying that retrying will fix
    // a managed/privacy-policy decision.
    try expect(provider.upcomingEventRequestCount == 0, "restricted calendar launch refresh should not request events")
    try expect(viewModel.state == .permissionRestricted, "restricted calendar authorization should publish a permission state")
    try expect(viewModel.sourceState == .permissionRestricted, "restricted calendar authorization should disable source loading")
    try expect(viewModel.compactText == ("Off", "Calendar"), "restricted calendar compact widget should not look empty")
    try expect(viewModel.nextEventLine == "Calendar access is restricted", "restricted calendar header should explain the policy state")

    await viewModel.refresh(settings: .default, reason: "validation-restricted")
    try expect(provider.upcomingEventRequestCount == 1, "manual restricted calendar refresh should make one provider attempt")
    try expect(viewModel.state == .permissionRestricted, "manual restricted calendar refresh should keep the permission state")

    await viewModel.refreshAvailableCalendars(settings: .default)
    try expect(provider.availableCalendarRequestCount == 1, "manual restricted source refresh should make one provider attempt")
    try expect(viewModel.sourceState == .permissionRestricted, "manual restricted source refresh should keep source permissions explicit")
}

@MainActor
func validateCalendarWriteOnlyPublishesPermissionState() async throws {
    let provider = ThrowingCalendarProvider(
        authorizationState: .writeOnly,
        error: CalendarProviderError.writeOnly
    )
    let viewModel = CalendarWidgetViewModel(provider: provider)

    await viewModel.refreshIfNeeded(settings: .default)

    // Write-only Calendar access can happen on current macOS privacy APIs. A
    // widget that reads events cannot use it, so keep it out of the generic
    // error path and tell the user full access is required.
    try expect(provider.upcomingEventRequestCount == 0, "write-only calendar launch refresh should not request events")
    try expect(viewModel.state == .permissionWriteOnly, "write-only calendar authorization should publish a permission state")
    try expect(viewModel.sourceState == .permissionWriteOnly, "write-only calendar authorization should disable source loading")
    try expect(viewModel.compactText == ("Off", "Calendar"), "write-only calendar compact widget should not look empty")
    try expect(viewModel.nextEventLine == "Calendar access is write-only", "write-only calendar header should explain full access is required")

    await viewModel.refresh(settings: .default, reason: "validation-write-only")
    try expect(provider.upcomingEventRequestCount == 1, "manual write-only calendar refresh should make one provider attempt")
    try expect(viewModel.state == .permissionWriteOnly, "manual write-only calendar refresh should keep the permission state")

    await viewModel.refreshAvailableCalendars(settings: .default)
    try expect(provider.availableCalendarRequestCount == 1, "manual write-only source refresh should make one provider attempt")
    try expect(viewModel.sourceState == .permissionWriteOnly, "manual write-only source refresh should keep source permissions explicit")
}

func validateAccentColorOptionsCoverDefault() throws {
    let rawValues = Set(DockingAccentColor.allCases.map(\.rawValue))
    try expect(rawValues.contains(DockingSettings.default.accentColorName), "default accent color should be a selectable option")
}

func validateWeatherCache() throws {
    let snapshot = WeatherSnapshot(
        locationName: "Tokyo",
        fetchedAt: Date(timeIntervalSince1970: 1_000),
        unit: .celsius,
        current: CurrentWeatherSummary(temperature: 23, feelsLike: 25, conditionCode: 0, conditionLabel: "Clear", symbolName: "sun.max"),
        hourly: [],
        daily: [],
        humidity: nil,
        airQualityLabel: nil,
        dataSource: .weatherKit
    )
    try expect(WeatherCache.isFresh(snapshot, intervalMinutes: 1, now: Date(timeIntervalSince1970: 1_600)), "weather cache should enforce a 15 minute minimum freshness interval")
    try expect(!WeatherCache.isFresh(snapshot, intervalMinutes: 15, now: Date(timeIntervalSince1970: 2_000)), "weather cache should expire after the configured interval")

    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCacheValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let cache = WeatherCache(fileURL: fileURL)
    cache.save(snapshot)
    try expect(cache.load() == snapshot, "weather cache should round-trip snapshots")
}

func validationWeatherSnapshot(locationName: String = "Fallback City", fetchedAt: Date = Date(timeIntervalSince1970: 1_000)) -> WeatherSnapshot {
    WeatherSnapshot(
        locationName: locationName,
        fetchedAt: fetchedAt,
        unit: .celsius,
        current: CurrentWeatherSummary(temperature: 20, feelsLike: 21, conditionCode: nil, conditionLabel: "Clear", symbolName: "sun.max"),
        hourly: [],
        daily: [],
        humidity: nil,
        airQualityLabel: nil,
        dataSource: .openMeteo
    )
}

@MainActor
func validateWeatherFreshCacheDoesNotRefreshProvider() async throws {
    let provider = CountingWeatherProvider()
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherFreshCacheValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let cache = WeatherCache(fileURL: cacheURL)
    let cachedSnapshot = validationWeatherSnapshot(locationName: "Fresh Cache", fetchedAt: Date())
    cache.save(cachedSnapshot)

    let viewModel = WeatherWidgetViewModel(provider: provider, cache: cache)
    var settings = DockingSettings.default
    settings.weatherEnabled = true
    settings.weatherUsesCurrentLocation = false
    settings.weatherManualLocation = "Tokyo"
    settings.weatherRefreshIntervalMinutes = DockingSettings.default.weatherRefreshIntervalMinutes

    // Fresh cached weather is intentionally considered good enough for passive
    // launch/panel refresh paths. This test protects the battery/network
    // contract: opening the widget repeatedly must not create provider requests
    // until the configured refresh interval has actually elapsed. Manual
    // refresh still uses `force: true`, so this does not remove the user's
    // explicit "update now" escape hatch.
    await viewModel.refreshIfNeeded(settings: settings)
    try expect(provider.requestCount == 0, "fresh weather cache should suppress passive provider refreshes")
    try expect(viewModel.state == .loaded, "fresh weather cache should publish a loaded state")
    try expect(viewModel.snapshot == cachedSnapshot, "fresh weather cache should keep the cached snapshot")

    await viewModel.refresh(settings: settings, force: false)
    try expect(provider.requestCount == 0, "non-forced weather refresh should also honor fresh cache")

    await viewModel.refresh(settings: settings, force: true)
    try expect(provider.requestCount == 1, "forced weather refresh should remain available for the manual refresh button")
}

func validateCompositeWeatherFallback() async throws {
    let expected = validationWeatherSnapshot()
    let provider = CompositeWeatherProvider(
        primary: ThrowingWeatherProvider(error: WeatherProviderError.providerUnavailable("WeatherKit entitlement unavailable")),
        fallback: StaticWeatherProvider(snapshot: expected)
    )

    let loaded = try await provider.fetchWeather(
        configuration: WeatherRequestConfiguration(manualLocation: "Tokyo", usesCurrentLocation: false, unit: .celsius)
    )

    try expect(loaded == expected, "composite provider should use fallback when primary provider is unavailable")
}

func validateCompositeWeatherDoesNotHideLocationDenial() async throws {
    let provider = CompositeWeatherProvider(
        primary: ThrowingWeatherProvider(error: WeatherProviderError.locationDenied),
        fallback: StaticWeatherProvider(snapshot: validationWeatherSnapshot())
    )

    do {
        _ = try await provider.fetchWeather(
            configuration: WeatherRequestConfiguration(manualLocation: nil, usesCurrentLocation: true, unit: .celsius)
        )
        throw ValidationFailure(description: "location denial should not be hidden by fallback data")
    } catch WeatherProviderError.locationDenied {
        return
    }
}

@MainActor
func validateWeatherManualLocationMissingStaysLocal() async throws {
    let provider = CountingWeatherProvider()
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherManualMissingValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let viewModel = WeatherWidgetViewModel(
        provider: provider,
        cache: WeatherCache(fileURL: cacheURL)
    )
    var settings = DockingSettings.default
    settings.weatherEnabled = true
    settings.weatherUsesCurrentLocation = false
    settings.weatherManualLocation = "   "

    await viewModel.refresh(settings: settings, force: true)

    try expect(provider.requestCount == 0, "missing manual weather location should not call provider")
    try expect(viewModel.state == .manualLocationNotSet, "missing manual weather location should show local configuration state")
}

@MainActor
func validateWeatherManualLocationMissingExplainsCachedData() async throws {
    let provider = CountingWeatherProvider()
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherManualMissingCachedValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let cache = WeatherCache(fileURL: cacheURL)
    cache.save(validationWeatherSnapshot(locationName: "Cached City"))

    let viewModel = WeatherWidgetViewModel(provider: provider, cache: cache)
    var settings = DockingSettings.default
    settings.weatherEnabled = true
    settings.weatherUsesCurrentLocation = false
    settings.weatherManualLocation = "   "

    await viewModel.refresh(settings: settings, force: true)

    try expect(provider.requestCount == 0, "missing manual weather location should not call provider even when cached weather exists")
    try expect(
        viewModel.state == .stale("Showing cached weather. Choose a city in Control Center to update."),
        "cached weather with a missing manual city should explain both the stale data and the needed setting"
    )
}

@MainActor
func validateWeatherCurrentLocationFallsBackToManualCity() async throws {
    let provider = CurrentLocationDeniedManualWeatherProvider()
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherManualFallbackValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let viewModel = WeatherWidgetViewModel(
        provider: provider,
        cache: WeatherCache(fileURL: cacheURL)
    )
    var settings = DockingSettings.default
    settings.weatherEnabled = true
    settings.weatherUsesCurrentLocation = true
    settings.weatherManualLocation = "Tokyo"

    await viewModel.refresh(settings: settings, force: true)

    try expect(provider.requests.map(\.usesCurrentLocation) == [true, false], "weather should retry the manual city after current-location denial")
    try expect(provider.requests.last?.manualLocation == "Tokyo", "manual weather fallback should preserve the configured city")
    try expect(viewModel.state == .loaded, "manual weather fallback should publish loaded weather instead of a location-denied state")
    try expect(viewModel.snapshot?.locationName == "Tokyo fallback", "manual weather fallback should publish the fallback city snapshot")
}

@MainActor
func validateWeatherLocationDeniedWithoutFallbackShowsDeniedState() async throws {
    let provider = ThrowingWeatherProvider(error: WeatherProviderError.locationDenied)
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherLocationDeniedValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let viewModel = WeatherWidgetViewModel(
        provider: provider,
        cache: WeatherCache(fileURL: cacheURL)
    )
    var settings = DockingSettings.default
    settings.weatherEnabled = true
    settings.weatherUsesCurrentLocation = true
    settings.weatherManualLocation = "   "

    await viewModel.refresh(settings: settings, force: true)

    // A denied current-location request should stay visibly denied when there
    // is no user-provided fallback city. Falling back to provider fixtures or
    // an unrelated default city would make the widget appear to work while
    // hiding the privacy/configuration problem the user needs to resolve.
    try expect(viewModel.state == .locationDenied, "location-denied weather without fallback should publish the denied state")
    try expect(viewModel.snapshot == nil, "location-denied weather without cache should not fabricate a snapshot")
    try expect(viewModel.compactText == ("--", "Weather", "cloud"), "location-denied compact weather should stay neutral without fake values")
}

@MainActor
func validateWeatherLocationDeniedExplainsCachedData() async throws {
    let provider = ThrowingWeatherProvider(error: WeatherProviderError.locationDenied)
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherLocationDeniedCachedValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let cache = WeatherCache(fileURL: cacheURL)
    cache.save(validationWeatherSnapshot(locationName: "Cached City"))

    let viewModel = WeatherWidgetViewModel(provider: provider, cache: cache)
    var settings = DockingSettings.default
    settings.weatherEnabled = true
    settings.weatherUsesCurrentLocation = true
    settings.weatherManualLocation = "   "

    await viewModel.refresh(settings: settings, force: true)

    // Cached weather is useful during a permission failure, but only if the UI
    // labels it as stale. We keep this behavior separate from the no-cache
    // denial test because showing old real data and showing no data are two
    // different product states with different failure modes.
    try expect(
        viewModel.state == .stale("Location access is denied. Showing cached weather."),
        "location-denied weather with cache should explain that the displayed data is stale"
    )
    try expect(viewModel.snapshot?.locationName == "Cached City", "location-denied weather with cache should keep the cached location")
}

private struct ThrowingWeatherProvider: WeatherProvider {
    let error: Error

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        throw error
    }
}

private struct StaticWeatherProvider: WeatherProvider {
    let snapshot: WeatherSnapshot

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        snapshot
    }
}

private final class CountingWeatherProvider: WeatherProvider {
    private(set) var requestCount = 0

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        requestCount += 1
        return validationWeatherSnapshot(locationName: "Counting")
    }
}

private final class CurrentLocationDeniedManualWeatherProvider: WeatherProvider {
    private(set) var requests: [WeatherRequestConfiguration] = []

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        requests.append(configuration)
        if configuration.usesCurrentLocation {
            throw WeatherProviderError.locationDenied
        }

        guard configuration.manualLocation?.nilIfBlank != nil else {
            throw WeatherProviderError.manualLocationMissing
        }

        return validationWeatherSnapshot(locationName: "Tokyo fallback")
    }
}

private final class EmptyCalendarProvider: CalendarProviding {
    var changeNotificationName: Notification.Name {
        Notification.Name("ValidationCalendarProviderChanged")
    }

    var changeNotificationObject: Any? {
        nil
    }

    let authorizationState: CalendarAuthorizationState = .granted

    func availableCalendars() async throws -> [CalendarSourceSummary] {
        []
    }

    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary] {
        []
    }
}

private final class DelayedCalendarProvider: CalendarProviding {
    var changeNotificationName: Notification.Name {
        Notification.Name("DelayedCalendarProviderChanged")
    }

    var changeNotificationObject: Any? {
        nil
    }

    let authorizationState: CalendarAuthorizationState = .granted

    func availableCalendars() async throws -> [CalendarSourceSummary] {
        []
    }

    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return [
            CalendarEventSummary(
                id: "delayed",
                title: "Delayed",
                calendarName: "Validation",
                startDate: Date(),
                endDate: Date().addingTimeInterval(1_800),
                location: nil
            )
        ]
    }
}

private final class CountingCalendarProvider: CalendarProviding {
    let changeNotificationName = Notification.Name("CountingCalendarProviderChanged")
    var changeNotificationObject: Any? {
        nil
    }
    let authorizationState: CalendarAuthorizationState
    private(set) var upcomingEventRequestCount = 0
    private(set) var availableCalendarRequestCount = 0

    init(authorizationState: CalendarAuthorizationState = .granted) {
        self.authorizationState = authorizationState
    }

    func availableCalendars() async throws -> [CalendarSourceSummary] {
        availableCalendarRequestCount += 1
        return []
    }

    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary] {
        upcomingEventRequestCount += 1
        return []
    }
}

private final class ThrowingCalendarProvider: CalendarProviding {
    let changeNotificationName = Notification.Name("ThrowingCalendarProviderChanged")
    var changeNotificationObject: Any? {
        nil
    }
    let authorizationState: CalendarAuthorizationState
    let error: CalendarProviderError
    private(set) var upcomingEventRequestCount = 0
    private(set) var availableCalendarRequestCount = 0

    init(authorizationState: CalendarAuthorizationState, error: CalendarProviderError) {
        self.authorizationState = authorizationState
        self.error = error
    }

    func availableCalendars() async throws -> [CalendarSourceSummary] {
        availableCalendarRequestCount += 1
        throw error
    }

    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary] {
        upcomingEventRequestCount += 1
        throw error
    }
}

private struct DelayedWeatherProvider: WeatherProvider {
    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        try await Task.sleep(nanoseconds: 500_000_000)
        return validationWeatherSnapshot(locationName: "Delayed")
    }
}

func validateRestoreSnapshot() throws {
    try expect(AppMetadata.version == "0.0.0", "app metadata should keep the explicit pre-release version")

    let suiteName = "docking.validation.restore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let snapshot = DockRestoreSnapshot(
        createdAt: Date(timeIntervalSince1970: 123),
        appVersion: AppMetadata.version,
        values: [
            "autohide": .bool(true),
            "tilesize": .double(42),
            "orientation": .string("bottom")
        ]
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(DockRestoreSnapshot.self, from: data)
    try expect(decoded == snapshot, "restore snapshot should preserve value types")
    try expect(decoded.appVersion == AppMetadata.version, "restore snapshot should carry the current app version")

    let snapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockRestoreValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: snapshotURL) }

    let snapshotService = DockSettingsSnapshotService(fileURL: snapshotURL, dockDefaults: defaults)
    defaults.set(false, forKey: "autohide")
    defaults.set(36.0, forKey: "tilesize")
    defaults.set("left", forKey: "orientation")
    defaults.set(0.4, forKey: "autohide-delay")

    let emptySnapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockRestoreEmptyValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: emptySnapshotURL) }

    let emptySnapshotService = DockSettingsSnapshotService(fileURL: emptySnapshotURL, dockDefaults: defaults)
    let emptyRestoreService = DockSettingsRestoreService(snapshotService: emptySnapshotService, dockDefaults: defaults)
    let emptyResult = try emptyRestoreService.restoreIfSnapshotExists()
    try expect(emptyResult.userMessage.contains("No Dock restore snapshot exists"), "restore without a snapshot should explain that nothing changed")
    try expect(emptyRestoreService.manualRestoreInstructions().text.contains("No saved Apple Dock snapshot exists"), "manual restore without snapshot should explain that there is nothing to replay")
    try expect(defaults.object(forKey: "autohide") as? Bool == false, "restore without a snapshot should not modify bool preferences")
    try expect(defaults.object(forKey: "tilesize") as? Double == 36.0, "restore without a snapshot should not modify numeric preferences")
    try expect(defaults.object(forKey: "orientation") as? String == "left", "restore without a snapshot should not modify string preferences")

    let primaryModeSnapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockPrimaryModeValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: primaryModeSnapshotURL) }
    let primaryModeSnapshotService = DockSettingsSnapshotService(fileURL: primaryModeSnapshotURL, dockDefaults: defaults)
    let primaryModeService = DockSettingsRestoreService(snapshotService: primaryModeSnapshotService, dockDefaults: defaults)
    try expect(!primaryModeService.restoreStatus().hasSnapshot, "primary mode status should start without a snapshot")
    _ = try primaryModeService.enableReplacementMode()
    let savedPrimaryModeSnapshot = try primaryModeSnapshotService.loadSnapshot()
    let enabledStatus = primaryModeService.restoreStatus()
    try expect(enabledStatus.snapshotCreatedAt == savedPrimaryModeSnapshot?.createdAt, "primary mode status should expose snapshot creation time")
    try expect(enabledStatus.savedPreferenceCount == savedPrimaryModeSnapshot?.values.count, "primary mode status should expose saved preference count")
    try expect(savedPrimaryModeSnapshot?.values["autohide"] == .bool(false), "primary mode should snapshot original autohide before changing it")
    try expect(defaults.object(forKey: "autohide") as? Bool == true, "primary mode should make Apple Dock auto-hide")
    try expect(defaults.object(forKey: "autohide-delay") as? Double == 1000.0, "primary mode should move Apple Dock out of the way with a long delay")
    _ = try primaryModeService.restoreIfSnapshotExists()
    try expect(defaults.object(forKey: "autohide") as? Bool == false, "primary mode restore should put original autohide back")
    try expect(defaults.object(forKey: "autohide-delay") as? Double == 0.4, "primary mode restore should put original autohide delay back")

    let current = snapshotService.currentDockSnapshot()
    try expect(current.values["autohide"] == .bool(false), "current Dock snapshot should read bool preferences")
    try expect(current.values["tilesize"] == .double(36.0), "current Dock snapshot should read numeric preferences")
    try expect(current.values["orientation"] == .string("left"), "current Dock snapshot should read string preferences")

    try snapshotService.saveSnapshot(snapshot)
    let manualInstructions = DockSettingsRestoreService(snapshotService: snapshotService, dockDefaults: defaults).manualRestoreInstructions().text
    try expect(manualInstructions.contains("defaults write com.apple.dock autohide -bool true"), "manual restore should include saved boolean Dock preferences")
    try expect(manualInstructions.contains("defaults write com.apple.dock tilesize -float 42.0"), "manual restore should include saved numeric Dock preferences")
    try expect(manualInstructions.contains("defaults write com.apple.dock orientation -string 'bottom'"), "manual restore should include saved string Dock preferences")
    try expect(manualInstructions.contains("killall Dock"), "manual restore should leave Apple Dock reload as an explicit user action")

    do {
        _ = try DockSettingsRestoreService(snapshotService: snapshotService, dockDefaults: nil).restoreIfSnapshotExists()
        throw ValidationFailure(description: "restore should not report success when the Dock defaults domain is unavailable")
    } catch DockSettingsRestoreError.dockDefaultsUnavailable {
        // Expected: a restore button that cannot reach Apple's Dock defaults is
        // materially different from a successful write. The UI can still show
        // manual commands, but the automatic path must not claim it worked.
    }

    defaults.set(false, forKey: "autohide")
    defaults.set(20.0, forKey: "tilesize")
    defaults.set("left", forKey: "orientation")

    let restoreService = DockSettingsRestoreService(snapshotService: snapshotService, dockDefaults: defaults)
    let result = try restoreService.restoreIfSnapshotExists()
    try expect(result.userMessage.contains("written back and verified"), "restore should report that a snapshot was written back and verified")
    try expect(defaults.object(forKey: "autohide") as? Bool == true, "restore should write bool preferences")
    try expect(defaults.object(forKey: "tilesize") as? Double == 42.0, "restore should write numeric preferences")
    try expect(defaults.object(forKey: "orientation") as? String == "bottom", "restore should write string preferences")
}

let validations: [(String, () throws -> Void)] = [
    ("formatters", validateFormatters),
    ("calendar grouping", validateCalendarGrouping),
    ("dock layout", validateDockLayout),
    ("dock icon renderer backing scale", validateDockIconRendererUsesFullBackingScale),
    ("detail panel anchoring", validateDetailPanelAnchoring),
    ("widget panel dismiss hit testing", validateWidgetPanelDismissHitTesting),
    ("specific display selection", validateSpecificDisplaySelection),
    ("dock position frames", validateDockPositionFrames),
    ("auto-hide trigger screens", validateAutoHideTriggerScreens),
    ("dock window collection behavior", validateDockingWindowCollectionBehavior),
    ("dock window level toggle", validateDockWindowLevelToggle),
    ("apple dock mirroring", validateAppleDockMirroring),
    ("app catalog item recognition", validateAppCatalogRecognizesApplicationsAndFolders),
    ("folder stack presentation", validateFolderStackPresentation),
    ("folder stack dismiss hit testing", validateFolderStackPanelDismissHitTesting),
    ("folder drop service", validateFolderDropService),
    ("running app matcher", validateRunningApplicationMatcher),
    ("settings store", validateSettingsStore),
    ("settings refresh keys", validateSettingsRefreshKeys),
    ("unpinned running app resolver", validateUnpinnedRunningAppResolver),
    ("default settings fit editable ranges", validateDefaultSettingsFitEditableRanges),
    ("dock widget metrics", validateDockWidgetMetrics),
    ("dock item termination menu policy", validateDockItemTerminationMenuPolicy),
    ("weather dock location display", validateWeatherDockLocationDisplay),
    ("calendar widget presentation", validateCalendarWidgetPresentation),
    ("weather widget presentation", validateWeatherWidgetPresentation),
    ("weather code mapping", validateWeatherCodeMapping),
    ("open-meteo air quality labels", validateOpenMeteoAirQualityLabels),
    ("weather data source labels", validateWeatherDataSourceLabels),
    ("accent color options", validateAccentColorOptionsCoverDefault),
    ("weather cache", validateWeatherCache),
    ("restore snapshot", validateRestoreSnapshot)
]

let asyncValidations: [(String, () async throws -> Void)] = [
    ("settings persistence debounce", { try await validateSettingsPersistenceIsDebounced() }),
    ("widget refresh cancellation", { try await validateWidgetRefreshCancellation() }),
    ("widget task lifecycle", { try await validateWidgetTaskLifecycle() }),
    ("explicit app reorder controls", { try await validateExplicitAppReorderControls() }),
    ("calendar launch does not request permission", { try await validateCalendarLaunchDoesNotRequestPermission() }),
    ("disabled calendar ignores store changes", { try await validateDisabledCalendarIgnoresStoreChanges() }),
    ("calendar denied permission state", { try await validateCalendarDeniedPublishesPermissionState() }),
    ("calendar restricted permission state", { try await validateCalendarRestrictedPublishesPermissionState() }),
    ("calendar write-only permission state", { try await validateCalendarWriteOnlyPublishesPermissionState() }),
    ("weather fresh cache avoids passive refresh", { try await validateWeatherFreshCacheDoesNotRefreshProvider() }),
    ("weather provider fallback", validateCompositeWeatherFallback),
    ("weather provider permission boundary", validateCompositeWeatherDoesNotHideLocationDenial),
    ("weather manual location missing stays local", { try await validateWeatherManualLocationMissingStaysLocal() }),
    ("weather manual location stale message", { try await validateWeatherManualLocationMissingExplainsCachedData() }),
    ("weather current location falls back to manual city", { try await validateWeatherCurrentLocationFallsBackToManualCity() }),
    ("weather location denied state", { try await validateWeatherLocationDeniedWithoutFallbackShowsDeniedState() }),
    ("weather location denied stale message", { try await validateWeatherLocationDeniedExplainsCachedData() })
]

do {
    for (name, validation) in validations {
        try validation()
        print("PASS \(name)")
    }
    for (name, validation) in asyncValidations {
        try await validation()
        print("PASS \(name)")
    }
    print("All Docking validation checks passed.")
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
