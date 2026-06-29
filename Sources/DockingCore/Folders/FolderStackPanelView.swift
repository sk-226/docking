import AppKit
import SwiftUI

struct FolderStackPanelView: View {
    @EnvironmentObject private var model: DockingAppModel
    let item: DockItem
    let entries: [FolderStackEntry]
    @State private var visibleLimit: Int
    @State private var isDownloadsScrollActive = false

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
                scrollMoreAffordance
            }
            .padding(.vertical, 2)
        }
        .onScrollGeometryChange(for: DownloadsScrollState.self) { geometry in
            DownloadsScrollState(
                contentOffsetY: geometry.contentOffset.y,
                visibleMaxY: geometry.visibleRect.maxY,
                contentHeight: geometry.contentSize.height
            )
        } action: { _, newValue in
            revealMoreDownloadsIfNeeded(scrollState: newValue, isUserScroll: isDownloadsScrollActive)
        }
        .onScrollPhaseChange { _, newPhase, context in
            isDownloadsScrollActive = newPhase.isScrolling
            revealMoreDownloadsIfNeeded(
                scrollState: DownloadsScrollState(
                    contentOffsetY: context.geometry.contentOffset.y,
                    visibleMaxY: context.geometry.visibleRect.maxY,
                    contentHeight: context.geometry.contentSize.height
                ),
                isUserScroll: newPhase.isScrolling
            )
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

    private var visibleEntries: [FolderStackEntry] {
        guard isDownloadsStack else {
            return entries
        }
        return Array(entries.prefix(visibleLimit))
    }

    @ViewBuilder
    private var scrollMoreAffordance: some View {
        if isDownloadsStack, visibleLimit < entries.count {
            // This small footer is not a button because the user asked for
            // scrolling to reveal more. It creates enough scrollable content for
            // a 12-item page that already fits in the panel, while the actual
            // page expansion is driven by ScrollGeometry below instead of this
            // view's lifetime.
            Text("Scroll for more")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
        }
    }

    private func revealMoreDownloadsIfNeeded(scrollState: DownloadsScrollState, isUserScroll: Bool) {
        guard Self.shouldRevealMoreDownloads(
            isDownloadsStack: isDownloadsStack,
            visibleCount: visibleLimit,
            totalCount: entries.count,
            isUserScroll: isUserScroll,
            contentOffsetY: scrollState.contentOffsetY,
            visibleMaxY: scrollState.visibleMaxY,
            contentHeight: scrollState.contentHeight
        ) else {
            return
        }

        // The previous sentinel-view approach could fire once and then remain in
        // the hierarchy, leaving later scrolls with no new `onAppear` event.
        // Geometry is tied to the actual scroll position, so every new page gets
        // another chance to load when the user reaches its end. Icons still
        // decode lazily as newly visible cells appear.
        visibleLimit = min(entries.count, visibleLimit + FolderStackService.downloadsInitialVisibleCount)
    }

    nonisolated static func shouldRevealMoreDownloads(
        isDownloadsStack: Bool,
        visibleCount: Int,
        totalCount: Int,
        isUserScroll: Bool,
        contentOffsetY: CGFloat,
        visibleMaxY: CGFloat,
        contentHeight: CGFloat
    ) -> Bool {
        let distanceToBottom = contentHeight - visibleMaxY
        guard isDownloadsStack,
              visibleCount < totalCount,
              isUserScroll,
              contentOffsetY > 4,
              distanceToBottom <= 80 else {
            return false
        }
        return true
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

private struct DownloadsScrollState: Equatable {
    var contentOffsetY: CGFloat = 0
    var visibleMaxY: CGFloat = 0
    var contentHeight: CGFloat = 0
}
