import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    static let dockingItem = NSPasteboard.PasteboardType("app.docking.item")
}

final class DockHostingView<Content: View>: NSHostingView<Content> {
    private weak var model: DockingAppModel?
    private var incomingURLs: [URL] = []
    private var insertingApplication = false
    private let feedbackLayer = CALayer()

    init(rootView: Content, model: DockingAppModel) {
        self.model = model
        super.init(rootView: rootView)
        registerForDraggedTypes([.dockingItem, .fileURL])
        wantsLayer = true
        feedbackLayer.borderWidth = 2
        feedbackLayer.cornerRadius = 4
        feedbackLayer.isHidden = true
        layer?.addSublayer(feedbackLayer)
    }

    @available(*, unavailable)
    required init(rootView: Content) { fatalError("Dock hosting requires its model") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Dock hosting is created programmatically") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        incomingURLs = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                          options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        insertingApplication = incomingURLs.first.flatMap { AppCatalogService.dockItemIfSupported(for: $0) }?.isApplication == true
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let model, let window else { return [] }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        if isInternalDrag(sender) {
            return model.updateDockItemDrag(at: point) ? .move : []
        }
        guard !incomingURLs.isEmpty,
              let target = model.externalDockDragTarget(at: point, insertingApplication: insertingApplication) else {
            feedbackLayer.isHidden = true
            return []
        }
        showFeedback(target)
        switch target {
        case .insert: return .copy
        case .openApplication: return sender.draggingSourceOperationMask.contains(.generic) ? .generic : .copy
        case let .folder(id):
            guard let url = model.visibleDockItems.first(where: { $0.id == id })?.url,
                  let source = incomingURLs.first else { return [] }
            return FolderDropService.operation(sourceURL: source, targetFolderURL: url) == .move ? .move : .copy
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !draggingUpdated(sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { finishDrag() }
        guard let model, let window else { return false }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        if isInternalDrag(sender) { return model.updateDockItemDrag(at: point) }
        guard !incomingURLs.isEmpty,
              let target = model.externalDockDragTarget(at: point, insertingApplication: insertingApplication) else { return false }
        model.performExternalDockDrop(incomingURLs, target: target)
        return true
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { finishDrag() }
    override func draggingEnded(_ sender: NSDraggingInfo) { finishDrag() }

    private func isInternalDrag(_ sender: NSDraggingInfo) -> Bool {
        guard let text = sender.draggingPasteboard.string(forType: .dockingItem),
              let id = UUID(uuidString: text) else { return false }
        return model?.draggedDockItem?.id == id
    }

    private func finishDrag() {
        feedbackLayer.isHidden = true
        incomingURLs = []
        model?.endExternalDockDrag()
    }

    private func showFeedback(_ target: DockDropTarget) {
        guard let model, let window, let frame = model.externalDockDropFeedback(target) else {
            feedbackLayer.isHidden = true
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        feedbackLayer.frame = convert(window.convertFromScreen(frame), from: nil)
        feedbackLayer.borderColor = NSColor.controlAccentColor.cgColor
        feedbackLayer.isHidden = false
        CATransaction.commit()
    }
}
