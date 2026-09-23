import AppKit

class DockFrameReportingView: NSView {
    var onFrameChange: ((NSRect) -> Void)?
    private var frameReportScheduled = false
    private var lastReportedFrame = CGRect.zero

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: window)
        }
        super.viewWillMove(toWindow: newWindow)
        if let newWindow {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove(_:)),
                                                   name: NSWindow.didMoveNotification, object: newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleFrameReport()
    }

    override func layout() {
        super.layout()
        scheduleFrameReport()
    }

    @objc private func windowDidMove(_ notification: Notification) {
        scheduleFrameReport()
    }

    func scheduleFrameReport() {
        guard !frameReportScheduled else { return }
        frameReportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameReportScheduled = false
            guard let window = self.window else { return }
            let frame = window.convertToScreen(self.convert(self.bounds, to: nil))
            guard frame.width > 0, frame.height > 0, frame != self.lastReportedFrame else { return }
            self.lastReportedFrame = frame
            self.onFrameChange?(frame)
        }
    }
}
