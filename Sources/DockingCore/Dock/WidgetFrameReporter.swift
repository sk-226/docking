import AppKit
import SwiftUI

struct WidgetFrameReporter: NSViewRepresentable {
    @EnvironmentObject private var model: DockingAppModel
    let kind: DockWidgetKind

    func makeNSView(context: Context) -> DockFrameReportingView {
        let view = DockFrameReportingView()
        view.onFrameChange = { [weak model, kind] frame in
            model?.updateWidgetFrame(kind: kind, frame: frame)
        }
        return view
    }

    func updateNSView(_ view: DockFrameReportingView, context: Context) {
        view.onFrameChange = { [weak model, kind] frame in
            model?.updateWidgetFrame(kind: kind, frame: frame)
        }
        view.scheduleFrameReport()
    }
}
