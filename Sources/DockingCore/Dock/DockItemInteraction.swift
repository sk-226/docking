import AppKit
import QuartzCore
import SwiftUI

struct DockItemInteraction: NSViewRepresentable {
    let item: DockItem
    let model: DockingAppModel
    let isTransient: Bool
    let iconSize: Double
    let launchProgress: Double
    @Environment(\.colorScheme) private var colorScheme
    let confirmForceQuit: () -> Void

    func makeNSView(context: Context) -> DockItemInteractionView {
        let view = DockItemInteractionView()
        view.buildMenu = makeMenu
        view.model = model
        view.item = item
        view.onFrameChange = { [weak model, itemID = item.id] frame in
            model?.updateDockItemFrame(itemID: itemID, frame: frame)
        }
        view.updateIcon(image: model.icon(for: item), size: iconSize, maximumSize: maximumIconSize,
                        position: model.settings.dockPosition, launchProgress: launchProgress,
                        isRunning: model.isRunning(item), isDragged: model.draggedDockItem?.id == item.id,
                        indicatorColor: colorScheme == .dark ? NSColor.white : NSColor.black)
        return view
    }

    func updateNSView(_ view: DockItemInteractionView, context: Context) {
        view.buildMenu = makeMenu
        view.model = model
        view.item = item
        view.onFrameChange = { [weak model, itemID = item.id] frame in
            model?.updateDockItemFrame(itemID: itemID, frame: frame)
        }
        view.updateIcon(image: model.icon(for: item), size: iconSize, maximumSize: maximumIconSize,
                        position: model.settings.dockPosition, launchProgress: launchProgress,
                        isRunning: model.isRunning(item), isDragged: model.draggedDockItem?.id == item.id,
                        indicatorColor: colorScheme == .dark ? NSColor.white : NSColor.black)
    }

    private var maximumIconSize: Double {
        max(model.settings.iconSize, model.settings.magnificationEnabled ? model.settings.magnificationSize : 0)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: DockContextMenuPolicy.menuTitle)
        menu.autoenablesItems = false
        let finder = item.bundleIdentifier == "com.apple.finder"
        if finder {
            menu.addItem(DockActionMenuItem("Open") { model.launch(item) })
        } else {
            let options = NSMenu()
            options.autoenablesItems = false
            options.addItem(DockActionMenuItem(isTransient ? "Keep in Docking" : "Remove from Docking") {
                if isTransient { model.pinRunningItem(item) }
                else { model.remove(item) }
            })
            options.addItem(DockActionMenuItem("Show in Finder") { model.showInFinder(item) })
            let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
            optionsItem.submenu = options
            menu.addItem(optionsItem)
        }
        if item.isFolder {
            menu.addItem(.separator())
            menu.addItem(submenu("Sort By", values: DockFolderSortMode.allCases, selected: item.folderSortMode,
                                 title: { $0.label }, action: { model.updateFolderSortMode($0, for: item) }))
            menu.addItem(submenu("Display as", values: DockFolderDisplayMode.allCases, selected: item.folderDisplayMode,
                                 title: { $0.label }, action: { model.updateFolderDisplayMode($0, for: item) }))
            menu.addItem(submenu("View content as", values: DockFolderViewMode.allCases, selected: item.folderViewMode,
                                 title: { $0.label }, action: { model.updateFolderViewMode($0, for: item) }))
        }
        menu.addItem(.separator())
        if model.isTerminationPending(item) {
            menu.addItem(DockActionMenuItem("Quitting...", enabled: false) {})
        } else if model.isRunning(item) {
            menu.addItem(DockActionMenuItem("Show All Windows") { model.showAllWindows(item) })
            let hidden = model.isHidden(item)
            menu.addItem(DockActionMenuItem(hidden ? "Show" : "Hide") {
                if hidden { model.launch(item) }
                else { model.hideApplication(item) }
            })
            if !finder {
                menu.addItem(DockActionMenuItem("Quit") { model.quit(item) })
                let forceQuit = DockActionMenuItem("Force Quit...", action: confirmForceQuit)
                forceQuit.isAlternate = true
                forceQuit.keyEquivalentModifierMask = [.option]
                menu.addItem(forceQuit)
            }
        } else {
            menu.addItem(DockActionMenuItem("Open") { model.launch(item) })
        }
        menu.addItem(.separator())
        let docking = NSMenu()
        docking.addItem(DockActionMenuItem("Open Control Center") { model.openControlCenterWindow() })
        let dockingItem = NSMenuItem(title: "Docking", action: nil, keyEquivalent: "")
        dockingItem.submenu = docking
        menu.addItem(dockingItem)
        return menu
    }

    private func submenu<Value: Equatable>(_ title: String, values: [Value], selected: Value,
                                            title itemTitle: (Value) -> String, action: @escaping (Value) -> Void) -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for value in values {
            let entry = DockActionMenuItem(itemTitle(value)) { action(value) }
            entry.state = value == selected ? .on : .off
            menu.addItem(entry)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

final class DockItemInteractionView: DockFrameReportingView, NSDraggingSource {
    var buildMenu: (() -> NSMenu)?
    weak var model: DockingAppModel?
    var item: DockItem?
    private let iconLayer = CALayer()
    private let indicatorLayer = CALayer()
    private var iconImage: NSImage?
    private var iconSize = 36.0
    private var maximumIconSize = 36.0
    private var rasterizedPixelSize = 0
    private var iconPosition = DockPosition.bottomCenter
    private var launchProgress = 0.0
    private var mouseDownEvent: NSEvent?
    private var mouseDownLocation = CGPoint.zero
    private var draggedItem: DockItem?
    private var dragFrame = CGRect.zero
    private var dragPosition = DockPosition.bottomCenter
    private var dragStartTime = 0.0
    private var dragCanceled = false
    private var cancellationMonitor: Any?
    private var removalTimer: Timer?
    private var removalReady = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.minificationFilter = .trilinear
        iconLayer.magnificationFilter = .linear
        indicatorLayer.cornerRadius = 1.5
        layer?.addSublayer(iconLayer)
        layer?.addSublayer(indicatorLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Dock interactions are created programmatically") }

    override var isFlipped: Bool { true }

    func updateIcon(image: NSImage, size: Double, maximumSize: Double? = nil, position: DockPosition, launchProgress: Double,
                    isRunning: Bool, isDragged: Bool, indicatorColor: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if iconImage !== image {
            iconImage = image
            rasterizedPixelSize = 0
            iconLayer.contents = nil
        }
        maximumIconSize = max(size, maximumSize ?? size)
        updateIconContents()
        iconLayer.isHidden = isDragged
        indicatorLayer.isHidden = !isRunning
        indicatorLayer.backgroundColor = indicatorColor.withAlphaComponent(0.65).cgColor
        iconSize = size
        iconPosition = position
        self.launchProgress = launchProgress
        layoutIcon()
        CATransaction.commit()
        scheduleFrameReport()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutIcon()
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateIconContents()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateIconContents()
    }

    private func updateIconContents() {
        guard let image = iconImage else { return }
        let backingScale = window?.backingScaleFactor ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        iconLayer.contentsScale = backingScale
        let pixels = Int(ceil(maximumIconSize * backingScale))
        let imageExtent = max(image.size.width, image.size.height)
        guard pixels > rasterizedPixelSize, imageExtent > 0 else { return }
        let scale = CGFloat(pixels) / imageExtent
        guard let context = CGContext(data: nil,
                                      width: Int(ceil(image.size.width * scale)),
                                      height: Int(ceil(image.size.height * scale)),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero, operation: .copy,
                   fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        guard let contents = context.makeImage() else { return }
        iconLayer.contents = contents
        rasterizedPixelSize = pixels
    }

    private func layoutIcon() {
        let size = iconPosition.isVertical ? bounds.height : bounds.width
        let thickness = iconPosition.isVertical ? bounds.width : bounds.height
        let inset = (thickness - size - 5) / 2
        var imageFrame: CGRect
        let indicatorFrame: CGRect
        switch iconPosition {
        case .left:
            imageFrame = CGRect(x: inset + 5, y: 0, width: size, height: size)
            indicatorFrame = CGRect(x: inset, y: (size - 3) / 2, width: 3, height: 3)
        case .right:
            imageFrame = CGRect(x: inset, y: 0, width: size, height: size)
            indicatorFrame = CGRect(x: inset + size + 2, y: (size - 3) / 2, width: 3, height: 3)
        default:
            imageFrame = CGRect(x: 0, y: inset, width: size, height: size)
            indicatorFrame = CGRect(x: (size - 3) / 2, y: inset + size + 2, width: 3, height: 3)
        }
        let offset = DockLaunchAnimation.offset(value: launchProgress, iconSize: iconSize, position: iconPosition)
        imageFrame = imageFrame.offsetBy(dx: offset.width, dy: offset.height)
        iconLayer.frame = imageFrame
        indicatorLayer.frame = indicatorFrame
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) { presentMenu(for: event) }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { presentMenu(for: event) }
        else {
            mouseDownEvent = event
            mouseDownLocation = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard mouseDownEvent != nil, draggedItem == nil, let item, let model, let window else { return }
        let location = window.convertPoint(toScreen: event.locationInWindow)
        if Self.shouldBeginDrag(from: mouseDownLocation, to: location) {
            guard model.beginDockItemDrag(item) != nil else { return }
            let reordered = model.updateDockItemDrag(at: location)
            model.endDockItemDrag(remove: false, canceled: !reordered)
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            model.performPrimaryClick(item, modifiers: event.modifierFlags)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard NSEvent.pressedMouseButtons & 1 != 0,
              let firstEvent = mouseDownEvent, draggedItem == nil, let model, let item,
              let window, Self.shouldBeginDrag(from: mouseDownLocation, to: window.convertPoint(toScreen: event.locationInWindow)),
              let frame = model.beginDockItemDrag(item) else { return }
        draggedItem = item
        dragFrame = frame
        dragPosition = model.settings.dockPosition
        dragStartTime = event.timestamp
        dragCanceled = false
        removalReady = false
        cancellationMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.dragCanceled = true } }
            return event
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.id.uuidString, forType: .dockingItem)
        let drag = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let size = min(bounds.width, bounds.height)
        drag.setDraggingFrame(CGRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size),
                              contents: model.icon(for: item))
        let session = beginDraggingSession(with: [drag], event: firstEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self, weak session] _ in
            MainActor.assumeIsolated {
                guard let self, let session, NSEvent.pressedMouseButtons != 0 else { return }
                self.updateDragFeedback(session, at: NSEvent.mouseLocation)
            }
        }
        removalTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        updateDragFeedback(session, at: NSEvent.mouseLocation)
    }

    private func updateDragFeedback(_ session: NSDraggingSession, at screenPoint: NSPoint) {
        if NSEvent.pressedMouseButtons != 0 { removalReady = canRemove(at: screenPoint) }
        let reordering = model?.updateDockItemDrag(at: screenPoint) == true
        session.animatesToStartingPositionsOnCancelOrFail = !reordering && !removalReady
        if removalReady { NSCursor.disappearingItem.set() }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        removalTimer?.invalidate()
        removalTimer = nil
        if let cancellationMonitor { NSEvent.removeMonitor(cancellationMonitor) }
        cancellationMonitor = nil
        let screenPoint = NSEvent.mouseLocation
        let canceled = dragCanceled || NSEvent.pressedMouseButtons != 0
        let reordered = !canceled && model?.updateDockItemDrag(at: screenPoint) == true
        let remove = !canceled && !reordered && removalReady && canRemove(at: screenPoint)
        session.animatesToStartingPositionsOnCancelOrFail = !reordered && !remove
        model?.endDockItemDrag(remove: remove, canceled: canceled || (!reordered && !remove))
        draggedItem = nil
        mouseDownEvent = nil
    }

    nonisolated static func shouldBeginDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        abs(current.x - start.x) > 5 || abs(current.y - start.y) > 5
    }

    private func canRemove(at point: NSPoint) -> Bool {
        guard let draggedItem else { return false }
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
        let menuBarFrame = screen.map { CGRect(x: $0.frame.minX, y: $0.visibleFrame.maxY,
                                               width: $0.frame.width, height: $0.frame.maxY - $0.visibleFrame.maxY) }
        return DockDragRemovalPolicy.canRemove(at: point, from: dragFrame, position: dragPosition,
                                               elapsed: ProcessInfo.processInfo.systemUptime - dragStartTime,
                                               isFixed: draggedItem.bundleIdentifier == "com.apple.finder", menuBarFrame: menuBarFrame)
    }

    private func presentMenu(for event: NSEvent) {
        mouseDownEvent = nil
        guard let menu = buildMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

private final class DockActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Dock actions are created programmatically") }

    @objc private func invoke() { handler() }
}
