import AppKit

final class DockContextMenuTracker {
    private var beginTrackingObserver: NSObjectProtocol?
    private var endTrackingObserver: NSObjectProtocol?
    private var trackedMenuIDs: Set<ObjectIdentifier> = []
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?

    func start(onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onClose = onClose

        guard beginTrackingObserver == nil, endTrackingObserver == nil else {
            return
        }

        beginTrackingObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let menu = notification.object as? NSMenu else {
                return
            }
            self?.menuDidBeginTracking(menu)
        }

        endTrackingObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let menu = notification.object as? NSMenu else {
                return
            }
            self?.menuDidEndTracking(menu)
        }
    }

    deinit {
        stop()
    }

    private func stop() {
        if let beginTrackingObserver {
            NotificationCenter.default.removeObserver(beginTrackingObserver)
        }
        if let endTrackingObserver {
            NotificationCenter.default.removeObserver(endTrackingObserver)
        }
        beginTrackingObserver = nil
        endTrackingObserver = nil
        trackedMenuIDs = []
    }

    private func menuDidBeginTracking(_ menu: NSMenu) {
        guard DockContextMenuPolicy.isDockItemContextMenu(menu) else {
            return
        }

        let inserted = trackedMenuIDs.insert(ObjectIdentifier(menu)).inserted
        if inserted && trackedMenuIDs.count == 1 {
            onOpen?()
        }
    }

    private func menuDidEndTracking(_ menu: NSMenu) {
        guard trackedMenuIDs.remove(ObjectIdentifier(menu)) != nil else {
            return
        }

        if trackedMenuIDs.isEmpty {
            onClose?()
        }
    }
}
