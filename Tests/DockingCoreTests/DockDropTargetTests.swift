import AppKit
import SwiftUI
import XCTest
@testable import DockingCore

final class DockDropTargetTests: XCTestCase {
    private let apps = (0..<4).map { DockItem(title: "App \($0)", bundleIdentifier: "test.\($0)", url: nil, iconCacheKey: "\($0)") }
    private let folders = (0..<3).map { DockItem(kind: .folder, title: "Folder \($0)", bundleIdentifier: nil,
                                               url: URL(fileURLWithPath: "/tmp/folder-\($0)"), iconCacheKey: "folder-\($0)") }

    func testCentersOpenOrDropWhileEdgesAndGapsRegisterAtTheirPosition() throws {
        let items = [DockItemOrdering.finder] + apps + folders
        for position in DockPosition.allCases {
            var settings = DockingSettings.default
            settings.dockPosition = position
            settings.magnificationEnabled = false
            let metrics = DockLayout.metrics(itemCount: items.count, settings: settings, documentStart: 5)
            let frames = DockDragGeometry.frames(items: items, metrics: metrics,
                                                 contentFrame: CGRect(origin: CGPoint(x: -900, y: 40), size: metrics.scaledPanelSize), settings: settings)
            func resolve(_ point: CGPoint, app: Bool = false) -> DockDropTarget {
                DockDropTarget.resolve(at: point, insertingApplication: app, items: items, frames: frames, position: position)
            }
            let app = try XCTUnwrap(frames[apps[1].id])
            XCTAssertEqual(resolve(CGPoint(x: app.midX, y: app.midY)), .openApplication(apps[1].id))
            XCTAssertEqual(resolve(CGPoint(x: app.midX, y: app.midY), app: true), .openApplication(apps[1].id))
            let appEdge = position.isVertical ? CGPoint(x: app.midX, y: app.maxY - 1) : CGPoint(x: app.minX + 1, y: app.midY)
            XCTAssertEqual(resolve(appEdge, app: true), .insert(before: apps[1].id))
            let folder = try XCTUnwrap(frames[folders[1].id])
            XCTAssertEqual(resolve(CGPoint(x: folder.midX, y: folder.midY)), .folder(folders[1].id))
            let folderEdge = position.isVertical ? CGPoint(x: folder.midX, y: folder.maxY - 1) : CGPoint(x: folder.minX + 1, y: folder.midY)
            XCTAssertEqual(resolve(folderEdge), .insert(before: folders[1].id))
            let gap = position.isVertical ? CGPoint(x: folder.midX, y: folder.maxY + 1) : CGPoint(x: folder.minX - 1, y: folder.midY)
            XCTAssertEqual(resolve(gap), .insert(before: folders[1].id))
            let end = try XCTUnwrap(frames[folders.last!.id])
            let beyond = position.isVertical ? CGPoint(x: end.midX, y: end.minY - 1) : CGPoint(x: end.maxX + 1, y: end.midY)
            XCTAssertEqual(resolve(beyond), .insert(before: nil))
            XCTAssertEqual(resolve(beyond, app: true), .insert(before: folders[0].id))
            XCTAssertEqual(resolve(appEdge), .insert(before: folders[0].id))
        }
    }

    func testCrowdedDragTraversesTheWholeDockAndRemainsStableWhenPointerStops() throws {
        let apps = (0..<70).map { DockItem(title: "App \($0)", bundleIdentifier: "test.\($0)", url: nil, iconCacheKey: "\($0)") }
        let initial = [DockItemOrdering.finder] + apps + folders
        for position in DockPosition.allCases {
            var settings = DockingSettings.default
            settings.dockPosition = position
            settings.magnificationEnabled = true
            settings.iconSize = 36
            settings.magnificationSize = 96
            let resting = DockLayout.metrics(itemCount: initial.count, settings: settings, documentStart: 71, maximumLength: 1200)
            let base = CGRect(origin: CGPoint(x: 80, y: 30), size: resting.scaledPanelSize)
            var current = initial
            func move(_ item: DockItem, to index: Int) throws {
                let restFrames = DockDragGeometry.frames(items: current, metrics: resting, contentFrame: base, settings: settings)
                let destination = try XCTUnwrap(restFrames[current[index].id])
                let point = CGPoint(x: destination.midX, y: destination.midY)
                let offset = position.isVertical ? base.maxY - point.y : point.x - base.minX
                let metrics = DockLayout.metrics(itemCount: current.count, settings: settings, documentStart: 71,
                                                  maximumLength: 1200, pointerOffset: offset / resting.scale)
                let frame = CGRect(x: position.isVertical ? base.minX : base.minX - metrics.originShift * metrics.scale,
                                   y: position.isVertical ? base.maxY + metrics.originShift * metrics.scale - metrics.scaledPanelSize.height : base.minY,
                                   width: metrics.scaledPanelSize.width, height: metrics.scaledPanelSize.height)
                let frames = DockDragGeometry.frames(items: current, metrics: metrics, contentFrame: frame, settings: settings)
                current = DockDragReordering.items(current, moving: item, to: point, frames: frames, position: position)
                let settled = current
                for _ in 0..<30 {
                    let frames = DockDragGeometry.frames(items: current, metrics: metrics, contentFrame: frame, settings: settings)
                    current = DockDragReordering.items(current, moving: item, to: point, frames: frames, position: position)
                    XCTAssertEqual(current, settled, "Stationary drag must not oscillate: \(position)")
                }
            }
            try move(apps[0], to: 65)
            XCTAssertGreaterThan(try XCTUnwrap(current.firstIndex(where: { $0.id == apps[0].id })), 55)
            try move(apps[0], to: 2)
            XCTAssertLessThan(try XCTUnwrap(current.firstIndex(where: { $0.id == apps[0].id })), 8)
            try move(folders[0], to: 73)
            XCTAssertNotEqual(Array(current.suffix(3)), folders)
            XCTAssertEqual(Set(current.map(\.id)), Set(initial.map(\.id)))
            XCTAssertEqual(current.first, DockItemOrdering.finder)
            XCTAssertTrue(current.suffix(3).allSatisfy { !$0.isApplication })
        }
    }

    @MainActor
    func testDragGeometryMatchesRenderedIconsAfterMagnificationMovesAcrossCrowdedDock() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppListStore(fileURL: directory.appendingPathComponent("items.json"))
        let apps = (0..<33).map { DockItem(title: "App \($0)", bundleIdentifier: "test.\($0)", url: nil, iconCacheKey: "\($0)") }
        store.save([DockItemOrdering.finder] + apps + folders)
        let suite = "DockGeometryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DockingAppModel(settingsStore: SettingsStore(defaults: defaults, appleDockDefaults: nil), appListStore: store)
        model.settings.magnificationEnabled = true
        model.settings.magnificationSize = 96
        model.settings.dockVisibility = .alwaysVisible
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.close() }
        func descendants(_ view: NSView) -> [DockItemInteractionView] {
            (view as? DockItemInteractionView).map { [$0] } ?? view.subviews.flatMap(descendants)
        }
        for position in [DockPosition.bottomCenter, .left, .right] {
            model.settings.dockPosition = position
            for pointer in [80.0, 600, 1100] {
                let metrics = DockLayout.metrics(itemCount: model.visibleDockItems.count, settings: model.settings,
                                                  documentStart: model.documentStart, maximumLength: 1200, pointerOffset: pointer)
                XCTAssertGreaterThan(metrics.iconSizes.max()!, model.settings.iconSize)
                window.setFrame(CGRect(origin: CGPoint(x: 100, y: 100), size: metrics.scaledPanelSize), display: false)
                let presentation = DockPresentation()
                presentation.layout = DockPresentationLayout(metrics: metrics, origin: .zero, canvasSize: metrics.scaledPanelSize)
                let root = DockHostingView(rootView: DockView(presentation: presentation).environmentObject(model), model: model)
                root.sizingOptions = []
                window.contentView = root
                root.layoutSubtreeIfNeeded()
                XCTAssertTrue(root.registeredDraggedTypes.contains(.dockingItem))
                XCTAssertTrue(root.registeredDraggedTypes.contains(.fileURL))
                let rendered = descendants(root)
                XCTAssertEqual(rendered.count, model.visibleDockItems.count)
                let expected = DockDragGeometry.frames(items: model.visibleDockItems, metrics: metrics,
                                                       contentFrame: window.frame, settings: model.settings)
                for view in rendered {
                    let id = try XCTUnwrap(view.item?.id)
                    let actual = window.convertToScreen(view.convert(view.bounds, to: nil))
                    let computed = try XCTUnwrap(expected[id])
                    XCTAssertEqual(actual.minX, computed.minX, accuracy: 1, "\(position), \(view.item!.title)")
                    XCTAssertEqual(actual.minY, computed.minY, accuracy: 1, "\(position), \(view.item!.title)")
                    XCTAssertEqual(actual.width, computed.width, accuracy: 1)
                    XCTAssertEqual(actual.height, computed.height, accuracy: 1)
                }
            }
        }
    }

    @MainActor
    func testHostingDestinationInsertsAtTheGapAndDropsIntoFolderAtItsCenter() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = (0..<3).map { directory.appendingPathComponent("Folder-\($0)", isDirectory: true) }
        for url in urls { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        let first = try XCTUnwrap(AppCatalogService.dockItemIfSupported(for: urls[0]))
        let last = try XCTUnwrap(AppCatalogService.dockItemIfSupported(for: urls[2]))
        let store = AppListStore(fileURL: directory.appendingPathComponent("items.json"))
        store.save([DockItemOrdering.finder, first, last])
        let suite = "DockDestinationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DockingAppModel(settingsStore: SettingsStore(defaults: defaults, appleDockDefaults: nil), appListStore: store)
        model.settings.magnificationEnabled = false
        model.settings.calendarEnabled = false
        model.settings.weatherEnabled = false
        model.settings.dockPosition = .bottomCenter
        model.settings.dockVisibility = .alwaysVisible
        model.showDock()
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Docking Dock" && $0.isVisible })
        defer { model.hideDock(); window.close() }
        let root = try XCTUnwrap(window.contentView)
        root.layoutSubtreeIfNeeded()
        let frame = try XCTUnwrap(model.externalDockDropFeedback(.folder(last.id)))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([urls[1] as NSURL])
        let info = DockTestDraggingInfo(window: window, pasteboard: pasteboard,
                                       point: window.convertPoint(fromScreen: CGPoint(x: frame.minX - 1, y: frame.midY)))
        XCTAssertEqual(root.draggingEntered(info), .copy)
        XCTAssertTrue(root.prepareForDragOperation(info))
        XCTAssertTrue(root.performDragOperation(info))
        XCTAssertEqual(model.dockItems.filter(\.isFolder).compactMap(\.url), urls)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[1].path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: urls[2].path).isEmpty)

        let document = directory.appendingPathComponent("Drop.txt")
        try "Drop test".write(to: document, atomically: true, encoding: .utf8)
        pasteboard.clearContents()
        pasteboard.writeObjects([document as NSURL])
        let updated = try XCTUnwrap(model.externalDockDropFeedback(.folder(last.id)))
        info.draggingLocation = window.convertPoint(fromScreen: CGPoint(x: updated.midX, y: updated.midY))
        XCTAssertFalse(root.draggingEntered(info).isEmpty)
        XCTAssertTrue(root.performDragOperation(info))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[2].appendingPathComponent("Drop.txt").path))
        XCTAssertFalse(model.dockItems.contains { $0.kind == .document })
        XCTAssertEqual(store.load(), model.dockItems)

        let savedBeforeDrag = store.load()
        pasteboard.clearContents()
        pasteboard.setString(first.id.uuidString, forType: .dockingItem)
        XCTAssertNotNil(model.beginDockItemDrag(first))
        info.draggingLocation = window.convertPoint(fromScreen: CGPoint(x: updated.maxX + 2, y: updated.midY))
        XCTAssertEqual(root.draggingEntered(info), .move)
        XCTAssertTrue(root.performDragOperation(info))
        XCTAssertEqual(model.dockItems.last?.id, first.id)
        XCTAssertEqual(store.load(), savedBeforeDrag)
        model.endDockItemDrag(remove: false, canceled: false)
        XCTAssertEqual(store.load(), model.dockItems)

        let committed = model.dockItems
        XCTAssertNotNil(model.beginDockItemDrag(first))
        let leading = try XCTUnwrap(model.externalDockDropFeedback(.folder(committed[1].id)))
        info.draggingLocation = window.convertPoint(fromScreen: CGPoint(x: leading.minX - 1, y: leading.midY))
        XCTAssertEqual(root.draggingEntered(info), .move)
        XCTAssertNotEqual(model.dockItems, committed)
        root.draggingExited(info)
        model.endDockItemDrag(remove: false, canceled: true)
        XCTAssertEqual(model.dockItems, committed)
        XCTAssertEqual(store.load(), committed)
    }

    @MainActor
    func testFolderRegistrationAtMiddlePreservesFilesystemAndBatchOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = (0..<4).map { directory.appendingPathComponent("Folder-\($0)", isDirectory: true) }
        for url in urls { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        let store = AppListStore(fileURL: directory.appendingPathComponent("items.json"))
        let existing = try [DockItemOrdering.finder] + [urls[0], urls[3]].map { try XCTUnwrap(AppCatalogService.dockItemIfSupported(for: $0)) }
        store.save(existing)
        let suite = "DockDropTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DockingAppModel(settingsStore: SettingsStore(defaults: defaults, appleDockDefaults: nil), appListStore: store)
        model.performExternalDockDrop([urls[1], urls[2]], target: .insert(before: existing.last!.id))
        XCTAssertEqual(model.dockItems.filter(\.isFolder).compactMap(\.url), urls)
        XCTAssertEqual(store.load(), model.dockItems)
        for url in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: urls[3].path).isEmpty)
        model.performExternalDockDrop([urls[1]], target: .insert(before: existing.last!.id))
        XCTAssertEqual(model.dockItems.count, 5)
    }
}

@MainActor
private final class DockTestDraggingInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingPasteboard: NSPasteboard
    var draggingLocation: NSPoint
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(window: NSWindow, pasteboard: NSPasteboard, point: NSPoint) {
        draggingDestinationWindow = window
        draggingPasteboard = pasteboard
        draggingLocation = point
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
