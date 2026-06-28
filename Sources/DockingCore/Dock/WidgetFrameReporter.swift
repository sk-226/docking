import AppKit
import SwiftUI

struct WidgetFrameReporter: NSViewRepresentable {
    @EnvironmentObject private var model: DockingAppModel
    let kind: DockWidgetKind

    func makeNSView(context: Context) -> ReportingView {
        ReportingView { frame in
            Task { @MainActor in
                model.updateWidgetFrame(kind: kind, frame: frame)
            }
        }
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onFrameChange = { frame in
            Task { @MainActor in
                model.updateWidgetFrame(kind: kind, frame: frame)
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
            // SwiftUI may update layout during a view transaction. Deferring the
            // coordinate conversion one run-loop turn avoids reporting stale
            // zero-sized frames from the representable's construction phase.
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
