import SwiftUI
import UniformTypeIdentifiers

struct DockView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        let isVertical = model.settings.dockPosition.isVertical
        let dockThickness = model.settings.effectiveDockThickness
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: model.settings.spacing))
            : AnyLayout(HStackLayout(spacing: model.settings.spacing))

        layout {
            ForEach(model.dockItems) { item in
                DockItemView(item: item)
                    .onDrag {
                        NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text, .fileURL],
                        delegate: DockItemDropDelegate(target: item, model: model)
                    )
            }

            if !model.unpinnedRunningItems.isEmpty {
                // Match the Apple Dock mental model: apps the user keeps in
                // Docking stay in the primary group, while merely-running apps
                // sit behind a divider so they can be discovered without
                // silently becoming permanent dock items.
                dockDivider(isVertical: isVertical)

                ForEach(model.unpinnedRunningItems) { item in
                    DockItemView(item: item, isTransientRunningItem: true)
                }
            }

            if model.enabledWidgetCount > 0 && model.visibleAppItemCount > 0 {
                dockDivider(isVertical: isVertical)
            }

            if model.settings.calendarEnabled {
                CalendarWidgetView()
            }

            if model.settings.weatherEnabled {
                WeatherWidgetView()
            }

            Button {
                model.addDockItem()
            } label: {
                Image(systemName: "plus")
                    .frame(width: model.settings.iconSize, height: model.settings.iconSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dockTooltip("Add app or folder")
            .accessibilityLabel("Add app or folder")
            .accessibilityHint("Choose an application bundle or folder to add to Docking")
        }
        .padding(.horizontal, isVertical ? 0 : dockThickness * 0.16)
        .padding(.vertical, isVertical ? dockThickness * 0.16 : 0)
        .frame(
            width: isVertical ? dockThickness : nil,
            height: isVertical ? nil : dockThickness
        )
        .dockingSurface(settings: model.settings)
        // AppKit's rectangular panel shadow is disabled, so this is the only
        // depth treatment for the dock. Keeping it soft and tied to the rounded
        // SwiftUI surface avoids the black rectangular rim that made the dock
        // feel unlike native macOS chrome.
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 5)
        .preferredColorScheme(model.settings.theme.colorScheme)
        .tint(model.settings.accentColor)
        .onHover { inside in
            if inside {
                model.pointerEnteredDock()
            } else {
                model.pointerExitedDock()
            }
        }
        .onDrop(of: [.fileURL], delegate: DockExternalAppDropDelegate(model: model))
        // The dock container should be discoverable as a group without
        // replacing the names of every child button. `.contain` preserves
        // child controls, while the explicit label gives VoiceOver a sensible
        // group name when entering the dock.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Docking Dock")
    }

    private func dockDivider(isVertical: Bool) -> some View {
        Divider()
            .frame(
                width: isVertical ? model.settings.iconSize * 0.62 : nil,
                height: isVertical ? nil : model.settings.iconSize * 0.62
            )
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
                model.addDockItem(fromDroppedURL: url, before: target)
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return
        }

        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, _ in
            let rawValue: String?
            if let data = item as? Data {
                rawValue = String(data: data, encoding: .utf8)
            } else {
                rawValue = item as? String
            }

            guard let rawValue,
                  let id = UUID(uuidString: rawValue) else {
                return
            }

            Task { @MainActor in
                guard let source = model.dockItems.first(where: { $0.id == id }) else {
                    return
                }
                model.moveDockItem(source, before: target)
            }
        }
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
