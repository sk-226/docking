import AppKit
import SwiftUI

struct FolderStackPanelView: View {
    @EnvironmentObject private var model: DockingAppModel
    let item: DockItem
    let entries: [FolderStackEntry]
    @State private var visibleLimit: Int

    init(item: DockItem, entries: [FolderStackEntry]) {
        self.item = item
        self.entries = entries
        let initialLimit = item.url.map { FolderStackService.isDownloadsFolder($0) } == true
            ? min(entries.count, FolderStackService.downloadsInitialVisibleCount)
            : entries.count
        _visibleLimit = State(initialValue: initialLimit)
    }

    var body: some View {
        let viewMode = FolderStackPresentation.resolvedViewMode(for: item, entryCount: entries.count)

        VStack(alignment: .leading, spacing: 12) {
            header

            if entries.isEmpty {
                emptyState
            } else {
                switch viewMode {
                case .automatic:
                    EmptyView()
                case .fan:
                    fanView
                case .grid:
                    gridView
                case .list:
                    listView
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dockingSurface(settings: model.settings, cornerRadius: 18)
        .preferredColorScheme(model.settings.theme.colorScheme)
        .tint(model.settings.accentColor)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.icon(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(entryCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.openFolderInFinderFromStack(item)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .dockTooltip("Open in Finder")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Empty Folder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fanView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entries.prefix(10).enumerated()), id: \.element.id) { index, entry in
                Button {
                    model.openFolderStackEntry(entry)
                } label: {
                    HStack(spacing: 9) {
                        entryIcon(entry, size: 28)
                        Text(entry.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    }
                    .padding(.leading, CGFloat(index) * 3)
                }
                .buttonStyle(.plain)
            }
            overflowText(limit: 10)
        }
    }

    private var gridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], alignment: .leading, spacing: 12) {
                    ForEach(visibleEntries) { entry in
                        Button {
                            model.openFolderStackEntry(entry)
                        } label: {
                            VStack(spacing: 6) {
                                entryIcon(entry, size: 38)
                                Text(entry.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(height: 32, alignment: .top)
                            }
                            .frame(width: 76, height: 82)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .dockTooltip(entry.title)
                    }
                }
                loadMoreTrigger
            }
            .padding(.vertical, 2)
        }
    }

    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(entries) { entry in
                    Button {
                        model.openFolderStackEntry(entry)
                    } label: {
                        HStack(spacing: 8) {
                            entryIcon(entry, size: 22)
                            Text(entry.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 10)
                            Text(entry.kindDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func entryIcon(_ entry: FolderStackEntry, size: CGFloat) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var entryCountLabel: String {
        guard isDownloadsStack else {
            return "\(entries.count) items"
        }

        return visibleLimit >= entries.count
            ? "\(entries.count) items"
            : "\(visibleLimit) of \(entries.count) items"
    }

    private var isDownloadsStack: Bool {
        item.url.map { FolderStackService.isDownloadsFolder($0) } ?? false
    }

    @ViewBuilder
    private var loadMoreTrigger: some View {
        if isDownloadsStack, visibleLimit < entries.count {
            HStack {
                Spacer()
                Text("Scroll for more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 18)
            .onAppear {
                revealMoreDownloads()
            }
        }
    }

    private var visibleEntries: [FolderStackEntry] {
        guard isDownloadsStack else {
            return entries
        }
        return Array(entries.prefix(visibleLimit))
    }

    private func revealMoreDownloads() {
        guard isDownloadsStack, visibleLimit < entries.count else {
            return
        }

        // Do not decode every Downloads icon at panel-open time. The entries
        // are already sorted by direct-child metadata; this only expands the
        // number of SwiftUI cells allowed to create icons as the user scrolls.
        visibleLimit = min(entries.count, visibleLimit + FolderStackService.downloadsInitialVisibleCount)
    }

    @ViewBuilder
    private func overflowText(limit: Int) -> some View {
        if entries.count > limit {
            Text("+ \(entries.count - limit) more")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
    }
}
