import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DockPresentation: ObservableObject {
    @Published var layout = DockPresentationLayout()

    var metrics: DockLayoutMetrics { layout.metrics }
}

struct DockPresentationLayout: Equatable {
    var metrics = DockLayout.metrics(itemCount: 0, settings: .default)
    var origin = CGPoint.zero
    var canvasSize = CGSize.zero
    var launchProgress: [UUID: Double] = [:]
}

struct DockView: View {
    @EnvironmentObject private var model: DockingAppModel
    @ObservedObject var presentation: DockPresentation

    var body: some View {
        let settings = model.settings
        let metrics = presentation.metrics
        let items = model.visibleDockItems
        let documentStart = DockItemOrdering.documentStart(in: items)
        let runningSectionStart = items.firstIndex { !$0.isPinned }
        let surfaceFrame = DockSurfaceGeometry.frame(
            in: CGRect(origin: presentation.layout.origin, size: metrics.scaledPanelSize),
            size: CGSize(width: metrics.surfaceSize.width * metrics.scale, height: metrics.surfaceSize.height * metrics.scale),
            position: settings.dockPosition
        )
        let vertical = settings.dockPosition.isVertical
        let alignment: Alignment = vertical ? (settings.dockPosition == .left ? .leading : .trailing) : .bottom
        let layout = vertical
            ? AnyLayout(VStackLayout(alignment: settings.dockPosition == .left ? .leading : .trailing, spacing: settings.spacing))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: settings.spacing))

        return layout {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index == documentStart || index == runningSectionStart { dockDivider }
                dockItem(item, index: index, transient: !item.isPinned)
                    .onDrop(of: [.fileURL], delegate: DockItemDropDelegate(target: item, model: model))
            }
            if model.enabledWidgetCount > 0 && !items.isEmpty { dockDivider }
            if settings.calendarEnabled {
                CalendarWidgetView().padding(edge, widgetInset)
            }
            if settings.weatherEnabled {
                WeatherWidgetView().padding(edge, widgetInset)
            }
            Button { model.addDockItem() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: DockLayout.addButtonSize, height: DockLayout.addButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(edge, (settings.effectiveDockThickness - DockLayout.addButtonSize) / 2)
            .dockTooltip("Add app, file or folder")
            .accessibilityLabel("Add app, file or folder")
        }
        .padding(vertical ? .vertical : .horizontal, metrics.padding)
        .frame(width: metrics.surfaceSize.width, height: metrics.surfaceSize.height, alignment: alignment)
        // Apply glass to the content, not to a separate Color.clear background:
        // semantic widget text must participate in Liquid Glass foreground
        // adaptation. The shape keeps the glass compact as icons magnify.
        .dockingSurface(settings: settings, in: DockSurfaceShape(
            surfaceSize: metrics.surfaceSize,
            position: settings.dockPosition,
            cornerRadius: settings.cornerRadius
        ))
        .scaleEffect(metrics.scale, anchor: .topLeading)
        .frame(width: surfaceFrame.width, height: surfaceFrame.height, alignment: .topLeading)
        .offset(x: surfaceFrame.minX, y: surfaceFrame.minY)
        .frame(width: presentation.layout.canvasSize.width, height: presentation.layout.canvasSize.height, alignment: .topLeading)
        .preferredColorScheme(settings.theme.colorScheme)
        .tint(settings.accentColor)
        .onDrop(of: [.fileURL], delegate: DockExternalAppDropDelegate(model: model))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Docking Dock")
    }

    private var edge: Edge.Set {
        switch model.settings.dockPosition {
        case .left: return .leading
        case .right: return .trailing
        default: return .bottom
        }
    }

    private var widgetInset: Double {
        (model.settings.effectiveDockThickness - model.settings.widgetTileHeight) / 2
    }

    private func dockItem(_ item: DockItem, index: Int, transient: Bool = false) -> some View {
        let sizes = presentation.metrics.iconSizes
        return DockItemView(item: item, iconSize: sizes.indices.contains(index) ? sizes[index] : model.settings.iconSize, isTransientRunningItem: transient, launchProgress: presentation.layout.launchProgress[item.id] ?? 0)
            .padding(edge, 3)
            .padding(model.settings.dockPosition.isVertical ? .top : .leading,
                     presentation.metrics.iconLeadingInsets.indices.contains(index) ? presentation.metrics.iconLeadingInsets[index] : 0)
    }

    private var dockDivider: some View {
        let vertical = model.settings.dockPosition.isVertical
        let extent = model.settings.iconSize * 0.65
        return Rectangle()
            .fill(.primary.opacity(0.16))
            .frame(width: vertical ? extent : 1, height: vertical ? 1 : extent)
            .padding(edge, (model.settings.effectiveDockThickness - extent) / 2)
    }
}

private struct DockSurfaceShape: Shape {
    let surfaceSize: CGSize
    let position: DockPosition
    let cornerRadius: Double

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: DockSurfaceGeometry.frame(in: rect, size: surfaceSize, position: position))
    }
}

private struct DockItemDropDelegate: DropDelegate {
    let target: DockItem
    let model: DockingAppModel

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.fileURL]).first else {
            return true
        }

        loadFileURL(from: provider) { url in
            Task { @MainActor in
                model.dropFile(url, onto: target)
            }
        }
        return true
    }

}

private struct DockExternalAppDropDelegate: DropDelegate {
    let model: DockingAppModel

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.fileURL]).first else {
            return false
        }

        loadFileURL(from: provider) { url in
            Task { @MainActor in
                model.addDockItem(fromDroppedURL: url)
            }
        }
        return true
    }
}

private func loadFileURL(from provider: NSItemProvider, completion: @escaping (URL) -> Void) {
    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        let url: URL?
        if let itemURL = item as? URL {
            url = itemURL
        } else if let data = item as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else if let string = item as? String {
            url = URL(string: string)
        } else {
            url = nil
        }

        guard let url else {
            return
        }
        completion(url)
    }
}
