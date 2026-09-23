import AppKit
import XCTest
@testable import DockingCore

final class DockItemOrderingTests: XCTestCase {
    func testMissingFinderIsInsertedOnceAndFixedBeforeApplications() {
        let app = application("notes")
        let folder = other("Downloads", kind: .folder)
        let doc = other("Plan.txt", kind: .document)
        let result = DockItemOrdering.normalized([doc, app, folder])
        XCTAssertEqual(result.map(\.title), ["Finder", "notes", "Plan.txt", "Downloads"])
        XCTAssertEqual(DockItemOrdering.normalized(result), result)
        XCTAssertEqual(DockItemOrdering.normalized([app, result[0], result[0]]).map(\.title), ["Finder", "notes"])
    }

    func testRunningAppsPrecedeDocumentsWithoutDuplicatingPinnedOrFinder() {
        let pinned = application("notes")
        var live = pinned
        live.id = UUID()
        live.runningProcessIdentifier = 7
        live.isPinned = false
        var terminal = application("terminal")
        terminal.isPinned = false
        var finder = DockItemOrdering.finder
        finder.runningProcessIdentifier = 11
        finder.isPinned = false
        let document = other("Plan.txt", kind: .document)
        let result = DockItemOrdering.visibleItems(pinned: [document, pinned], running: [live, terminal, finder], visibility: .separated)
        XCTAssertEqual(result.map(\.title), ["Finder", "notes", "terminal", "Plan.txt"])
        XCTAssertEqual(result[0].runningProcessIdentifier, 11)
        XCTAssertEqual(result[1].runningProcessIdentifier, 7)
        XCTAssertEqual(DockItemOrdering.documentStart(in: result), 3)
        let hidden = DockItemOrdering.visibleItems(pinned: [document, pinned], running: [live, terminal, finder], visibility: .hidden)
        XCTAssertEqual(hidden.map(\.title), ["Finder", "notes", "Plan.txt"])
    }

    func testReorderingCannotCrossFinderOrApplicationDocumentBoundary() {
        let finder = DockItemOrdering.finder
        let app = application("notes")
        let folder = other("Downloads", kind: .folder)
        let document = other("Plan.txt", kind: .document)
        let items = [finder, app, folder, document]
        let frames = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, CGRect(x: $0.offset * 50, y: 0, width: 40, height: 40)) })
        let beforeFinder = DockDragReordering.items(items, moving: app, to: CGPoint(x: -100, y: 10), frames: frames, position: .bottomCenter)
        XCTAssertEqual(beforeFinder, items)
        let afterDocuments = DockDragReordering.items(items, moving: app, to: CGPoint(x: 500, y: 10), frames: frames, position: .bottomCenter)
        XCTAssertEqual(afterDocuments, items)
        let documentAtStart = DockDragReordering.items(items, moving: document, to: CGPoint(x: -100, y: 10), frames: frames, position: .bottomCenter)
        XCTAssertEqual(documentAtStart, [finder, app, document, folder])
    }

    func testDocumentIsNotMistakenForFolderOrApplicationAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Example.txt")
        try Data("Dock document fixture".utf8).write(to: url)
        let document = try XCTUnwrap(AppCatalogService.dockItemIfSupported(for: url))
        XCTAssertEqual(document.kind, .document)
        XCTAssertFalse(document.isFolder)
        XCTAssertFalse(document.isApplication)
        XCTAssertEqual(try JSONDecoder().decode(DockItem.self, from: JSONEncoder().encode(document)), document)
        XCTAssertNil(AppCatalogService.dockItemIfSupported(for: directory.appendingPathComponent("missing.txt")))
        XCTAssertNil(AppCatalogService.dockItemIfSupported(for: URL(string: "https://example.com/a.txt")!))
    }

    func testImportsDocumentAndFolderFromNativeOtherSection() throws {
        let name = "app.docking.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Example.txt")
        try Data("Dock import fixture".utf8).write(to: url)
        defaults.set([
            ["tile-type": "file-tile", "tile-data": ["file-data": ["_CFURLString": url.absoluteString], "file-label": "Document"]],
            ["tile-type": "directory-tile", "tile-data": ["file-data": ["_CFURLString": directory.absoluteString], "file-label": "Folder"]]
        ], forKey: "persistent-others")
        let items = AppleDockPreferences.persistentDockItems(from: defaults)
        XCTAssertEqual(items.map(\.kind), [.document, .folder])
        XCTAssertEqual(items.map(\.title), ["Document", "Folder"])
    }

    func testRecentAndDocumentSectionsBothReserveDividerSpace() {
        var settings = DockingSettings.default
        settings.calendarEnabled = false
        settings.weatherEnabled = false
        let base = DockLayout.metrics(itemCount: 6, settings: settings)
        let sections = DockLayout.metrics(itemCount: 6, settings: settings, documentStart: 5, runningSectionStart: 3)
        XCTAssertEqual(sections.iconCenters[2], base.iconCenters[2])
        XCTAssertEqual(sections.iconCenters[3] - base.iconCenters[3], 1 + settings.spacing, accuracy: 0.000001)
        XCTAssertEqual(sections.iconCenters[5] - base.iconCenters[5], 2 * (1 + settings.spacing), accuracy: 0.000001)
        XCTAssertEqual(sections.panelSize.width - base.panelSize.width, 2 * (1 + settings.spacing), accuracy: 0.000001)
    }

    private func application(_ title: String) -> DockItem {
        DockItem(title: title, bundleIdentifier: "test.\(title)", url: nil, iconCacheKey: title)
    }

    private func other(_ title: String, kind: DockItemKind) -> DockItem {
        DockItem(kind: kind, title: title, bundleIdentifier: nil, url: URL(fileURLWithPath: "/tmp/\(title)"), iconCacheKey: title)
    }
}
