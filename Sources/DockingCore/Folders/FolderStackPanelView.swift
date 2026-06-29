import AppKit
import SwiftUI

struct FolderStackPanelView: View {
    @EnvironmentObject private var model: DockingAppModel
    let item: DockItem
    let entries: [FolderStackEntry]
    @State private var visibleLimit: Int
    @State private var downloadsVisibleRange: ClosedRange<Int>?

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
                .contextMenu {
                    stackEntryContextMenu(entry)
                }
                .onDrag {
                    stackEntryDragProvider(entry)
                }
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
                        .contextMenu {
                            stackEntryContextMenu(entry)
                        }
                        .onDrag {
                            stackEntryDragProvider(entry)
                        }
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
            updateDownloadsScrollPosition(scrollState: newValue)
            revealMoreDownloadsIfNeeded(scrollState: newValue)
        }
        .onScrollPhaseChange { _, newPhase, context in
            // Keep this handler even though page loading no longer depends on
            // ScrollPhase. SwiftUI can coalesce geometry updates during trackpad
            // inertia, and this hook gives the header one more update at the
            // boundary between active scrolling and rest. We intentionally do
            // not gate loading on `newPhase.isScrolling`: Docking's stack panel
            // is a non-activating NSPanel, and tying correctness to phase
            // delivery made Downloads feel broken when geometry changed but
            // phase did not.
            let scrollState = DownloadsScrollState(
                contentOffsetY: context.geometry.contentOffset.y,
                visibleMaxY: context.geometry.visibleRect.maxY,
                contentHeight: context.geometry.contentSize.height
            )
            updateDownloadsScrollPosition(scrollState: scrollState)
            if !newPhase.isScrolling {
                revealMoreDownloadsIfNeeded(scrollState: scrollState)
            }
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
                    .contextMenu {
                        stackEntryContextMenu(entry)
                    }
                    .onDrag {
                        stackEntryDragProvider(entry)
                    }
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

    @ViewBuilder
    private func stackEntryContextMenu(_ entry: FolderStackEntry) -> some View {
        Button("Open") {
            model.openFolderStackEntry(entry)
        }
        Button("Show in Finder") {
            model.showFolderStackEntryInFinder(entry)
        }
    }

    private func stackEntryDragProvider(_ entry: FolderStackEntry) -> NSItemProvider {
        // Finder and most Mac apps understand `public.file-url`. Passing the
        // actual file URL preserves native drag behavior for Downloads items:
        // the receiving app decides whether it opens, imports, copies, or moves
        // the file. Docking should not pre-copy stack entries or synthesize
        // temporary files, because that would break the user's expectation that
        // a Dock stack represents the real folder contents.
        NSItemProvider(object: entry.url as NSURL)
    }

    private var entryCountLabel: String {
        guard isDownloadsStack else {
            return "\(entries.count) items"
        }

        guard entries.count > FolderStackService.downloadsInitialVisibleCount else {
            return "\(entries.count) items"
        }

        let visibleRange = downloadsVisibleRange ?? 1...min(visibleLimit, entries.count)
        return "\(visibleRange.lowerBound)-\(visibleRange.upperBound) of \(entries.count) items"
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

    private func revealMoreDownloadsIfNeeded(scrollState: DownloadsScrollState) {
        guard Self.shouldRevealMoreDownloads(
            isDownloadsStack: isDownloadsStack,
            visibleCount: visibleLimit,
            totalCount: entries.count,
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
        let newVisibleLimit = min(entries.count, visibleLimit + FolderStackService.downloadsInitialVisibleCount)
        visibleLimit = newVisibleLimit
        downloadsVisibleRange = Self.downloadsVisibleRange(
            visibleCount: newVisibleLimit,
            totalCount: entries.count,
            contentOffsetY: scrollState.contentOffsetY,
            visibleMaxY: scrollState.visibleMaxY,
            contentHeight: scrollState.contentHeight
        )
    }

    private func updateDownloadsScrollPosition(scrollState: DownloadsScrollState) {
        guard isDownloadsStack else {
            return
        }

        downloadsVisibleRange = Self.downloadsVisibleRange(
            visibleCount: visibleLimit,
            totalCount: entries.count,
            contentOffsetY: scrollState.contentOffsetY,
            visibleMaxY: scrollState.visibleMaxY,
            contentHeight: scrollState.contentHeight
        )
    }

    nonisolated static func downloadsVisibleRange(
        visibleCount: Int,
        totalCount: Int,
        contentOffsetY: CGFloat,
        visibleMaxY: CGFloat,
        contentHeight: CGFloat
    ) -> ClosedRange<Int> {
        guard totalCount > 0, visibleCount > 0 else {
            return 0...0
        }

        let clampedVisibleCount = min(visibleCount, totalCount)
        guard contentHeight > 0, visibleMaxY > 0 else {
            return 1...clampedVisibleCount
        }

        // The Downloads stack can contain thousands of files, so the header
        // should explain the user's current position without forcing every file
        // cell to report geometry. A loaded-count label like "48 of 1500" stays
        // stuck after more pages are revealed and makes scrolling back to the
        // top feel broken. Estimating the visible range from the ScrollView
        // geometry keeps the UI honest enough for orientation while avoiding
        // per-cell observers, which would add avoidable work to the heaviest
        // stack users are likely to have.
        let lowerRatio = min(max(contentOffsetY / contentHeight, 0), 1)
        let upperRatio = min(max(visibleMaxY / contentHeight, 0), 1)
        let lowerBound = Int(floor(Double(clampedVisibleCount) * Double(lowerRatio))) + 1
        let upperBound = Int(ceil(Double(clampedVisibleCount) * Double(upperRatio)))
        let clampedLowerBound = min(max(lowerBound, 1), clampedVisibleCount)
        let clampedUpperBound = min(max(upperBound, clampedLowerBound), clampedVisibleCount)
        return clampedLowerBound...clampedUpperBound
    }

    nonisolated static func shouldRevealMoreDownloads(
        isDownloadsStack: Bool,
        visibleCount: Int,
        totalCount: Int,
        contentOffsetY: CGFloat,
        visibleMaxY: CGFloat,
        contentHeight: CGFloat
    ) -> Bool {
        let distanceToBottom = contentHeight - visibleMaxY
        guard isDownloadsStack,
              visibleCount < totalCount,
              contentOffsetY > 4,
              distanceToBottom <= 80 else {
            return false
        }
        // We deliberately treat "positive offset and near the end" as the
        // source of truth instead of requiring ScrollPhase to say the user is
        // actively scrolling. ScrollPhase is useful for polish, but for this
        // stack it is not a correctness signal: a non-activating panel can
        // receive geometry changes from wheel/trackpad inertia after the phase
        // has already settled. The offset guard still prevents the initial
        // layout pass from eagerly reading thousands of Downloads entries.
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
