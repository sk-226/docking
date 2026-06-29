import AppKit
import SwiftUI

struct DockItemFrameReporter: NSViewRepresentable {
    @EnvironmentObject private var model: DockingAppModel
    let itemID: UUID

    func makeNSView(context: Context) -> ReportingView {
        ReportingView { frame in
            Task { @MainActor in
                model.updateDockItemFrame(itemID: itemID, frame: frame)
            }
        }
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onFrameChange = { frame in
            Task { @MainActor in
                model.updateDockItemFrame(itemID: itemID, frame: frame)
            }
        }
        nsView.scheduleReport()
    }

    final class ReportingView: NSView {
        var onFrameChange: (NSRect) -> Void
        private var lastReportedFrame: NSRect = .zero

        init(onFrameChange: @escaping (NSRect) -> Void) {
            self.onFrameChange = onFrameChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleReport()
        }

        override func layout() {
            super.layout()
            scheduleReport()
        }

        func scheduleReport() {
            // Folder stack panels should anchor to the actual icon the user
            // clicked, not the dock center. Deferring by one run-loop lets
            // SwiftUI finish hover scaling and layout before AppKit converts
            // the zero-sized representable into screen coordinates.
            DispatchQueue.main.async { [weak self] in
                self?.reportIfChanged()
            }
        }

        private func reportIfChanged() {
            guard let window else {
                return
            }

            let frameInWindow = convert(bounds, to: nil)
            let frameOnScreen = window.convertToScreen(frameInWindow)
            guard frameOnScreen.width > 0, frameOnScreen.height > 0 else {
                return
            }

            if !Self.nearlyEqual(frameOnScreen, lastReportedFrame) {
                lastReportedFrame = frameOnScreen
                onFrameChange(frameOnScreen)
            }
        }

        private static func nearlyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
            abs(lhs.minX - rhs.minX) < 0.5 &&
                abs(lhs.minY - rhs.minY) < 0.5 &&
                abs(lhs.width - rhs.width) < 0.5 &&
                abs(lhs.height - rhs.height) < 0.5
        }
    }
}
