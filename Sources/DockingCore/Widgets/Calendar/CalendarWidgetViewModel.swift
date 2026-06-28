import Foundation

enum CalendarWidgetState: Equatable {
    case idle
    case loading
    case permissionNotDetermined
    case permissionDenied
    case permissionRestricted
    case permissionWriteOnly
    case empty
    case loaded
    case error(String)
}

enum CalendarSourceState: Equatable {
    case idle
    case loading
    case loaded
    case permissionDenied
    case permissionRestricted
    case permissionWriteOnly
    case error(String)
}

@MainActor
final class CalendarWidgetViewModel: ObservableObject {
    @Published private(set) var state: CalendarWidgetState = .idle
    @Published private(set) var sourceState: CalendarSourceState = .idle
    @Published private(set) var events: [CalendarEventSummary] = []
    @Published private(set) var availableCalendars: [CalendarSourceSummary] = []
    @Published private(set) var lastRefresh: Date?

    private let provider: CalendarProviding
    private var refreshTask: Task<Void, Never>?
    private var sourceTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var sourceGeneration = 0
    private var eventStoreChangeToken: NSObjectProtocol?
    private var currentSettings: DockingSettings = .default

    init(provider: CalendarProviding) {
        self.provider = provider

        eventStoreChangeToken = NotificationCenter.default.addObserver(
            forName: provider.changeNotificationName,
            object: provider.changeNotificationObject,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshCurrentSettings(reason: "event-store-change")
            }
        }
    }

    deinit {
        if let eventStoreChangeToken {
            NotificationCenter.default.removeObserver(eventStoreChangeToken)
        }
    }

    var compactText: (primary: String, secondary: String) {
        guard let event = events.first else {
            switch state {
            case .permissionNotDetermined:
                return ("Access", "Calendar")
            case .permissionDenied, .permissionRestricted, .permissionWriteOnly:
                return ("Off", "Calendar")
            case .loading:
                return ("...", "Events")
            default:
                return ("Today", "No events")
            }
        }
        return (
            DockingFormatters.timeFormatter.string(from: event.startDate),
            event.title
        )
    }

    var nextEventLine: String {
        guard let event = events.first else {
            switch state {
            case .permissionNotDetermined:
                return "Calendar access has not been granted yet"
            case .permissionDenied:
                return "Calendar access is off"
            case .permissionRestricted:
                return "Calendar access is restricted"
            case .permissionWriteOnly:
                return "Calendar access is write-only"
            case .empty:
                return "No upcoming events"
            case .loading:
                return "Loading upcoming events"
            case .error:
                return "Calendar could not load"
            case .idle, .loaded:
                return "No upcoming event loaded"
            }
        }
        return "Next: \(DockingFormatters.timeFormatter.string(from: event.startDate))  \(event.title)"
    }

    var isRefreshing: Bool {
        refreshTask != nil
    }

    var isLoadingSources: Bool {
        sourceTask != nil
    }

    func refreshIfNeeded(settings: DockingSettings) async {
        currentSettings = settings
        guard settings.calendarEnabled else {
            return
        }

        guard refreshTask == nil else {
            return
        }

        guard provider.authorizationState == .granted else {
            publishAuthorizationState(provider.authorizationState)
            return
        }

        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 5 * 60 {
            return
        }

        await refresh(settings: settings, reason: "stale-or-launch")
    }

    func refresh(settings: DockingSettings, reason: String) async {
        currentSettings = settings
        guard settings.calendarEnabled else {
            // Calendar access can trigger a system permission prompt. The
            // ViewModel enforces the disabled-widget boundary itself so callers
            // do not have to remember which entry points are safe while the
            // widget is off.
            cancelRefresh()
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        let task = Task { [provider] in
            do {
                let loaded = try await provider.upcomingEvents(
                    lookaheadDays: settings.calendarLookaheadDays,
                    maxEvents: settings.calendarMaxEventCount,
                    selectedCalendarIDs: settings.calendarSelectedCalendarIDs
                )
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self.events = loaded
                    self.lastRefresh = Date()
                    self.state = loaded.isEmpty ? .empty : .loaded
                }
            } catch CalendarProviderError.notDetermined {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.state = .permissionNotDetermined }
            } catch CalendarProviderError.denied {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.state = .permissionDenied }
            } catch CalendarProviderError.restricted {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.state = .permissionRestricted }
            } catch CalendarProviderError.writeOnly {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.state = .permissionWriteOnly }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.state = .error(error.localizedDescription) }
            }
        }

        refreshTask = task
        state = .loading
        _ = await task.result
        clearRefreshTask(generation: generation)
    }

    func cancelRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        if state == .loading {
            state = events.isEmpty ? .idle : .loaded
        }
    }

    func disable(settings: DockingSettings) {
        currentSettings = settings
        cancelRefresh()
    }

    func refreshAvailableCalendars(settings: DockingSettings) async {
        currentSettings = settings
        guard settings.calendarEnabled else {
            // Calendar source enumeration can request EventKit access. Keeping
            // the settings value on this entry point makes "disabled means no
            // Calendar access" true even when a caller bypasses Control Center.
            sourceGeneration += 1
            sourceTask?.cancel()
            sourceTask = nil
            if sourceState == .loading {
                sourceState = .idle
            }
            return
        }

        sourceGeneration += 1
        let generation = sourceGeneration
        sourceTask?.cancel()
        let task = Task { [provider] in
            do {
                let calendars = try await provider.availableCalendars()
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self.availableCalendars = calendars
                    self.sourceState = .loaded
                }
            } catch CalendarProviderError.denied {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.sourceState = .permissionDenied }
            } catch CalendarProviderError.restricted {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.sourceState = .permissionRestricted }
            } catch CalendarProviderError.writeOnly {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.sourceState = .permissionWriteOnly }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.sourceState = .error(error.localizedDescription) }
            }
        }

        sourceTask = task
        sourceState = .loading
        _ = await task.result
        clearSourceTask(generation: generation)
    }

    private func refreshCurrentSettings(reason: String) async {
        guard currentSettings.calendarEnabled else {
            return
        }

        guard provider.authorizationState == .granted else {
            publishAuthorizationState(provider.authorizationState)
            return
        }

        // EventKit may post store-change notifications during account sync or
        // app startup. Those notifications should update already-authorized
        // event data, but the calendar-source selector stays opt-in: loading
        // account names just because the user opened the app made the Widgets
        // settings feel too eager. Once the user has explicitly loaded sources,
        // keeping that visible list fresh is useful and no longer surprising.
        if sourceState != .idle {
            await refreshAvailableCalendars(settings: currentSettings)
        }
        await refresh(settings: currentSettings, reason: reason)
    }

    private func publishAuthorizationState(_ authorizationState: CalendarAuthorizationState) {
        switch authorizationState {
        case .notDetermined:
            state = .permissionNotDetermined
            sourceState = .idle
        case .denied:
            state = .permissionDenied
            sourceState = .permissionDenied
        case .restricted:
            // Restricted/write-only are permission outcomes, not provider
            // failures. Treating them as `.error` made the widget look broken
            // even though the user or system policy simply has not granted
            // readable Calendar access. Dedicated states let every surface show
            // actionable permission copy without retrying aggressively.
            state = .permissionRestricted
            sourceState = .permissionRestricted
        case .writeOnly:
            state = .permissionWriteOnly
            sourceState = .permissionWriteOnly
        case .granted:
            break
        }
    }

    private func clearRefreshTask(generation: Int) {
        // Refresh calls can overlap: a manual refresh may cancel a stale launch
        // refresh while that older async function is still suspended. The
        // generation check prevents the older completion path from clearing the
        // newer task reference, which would make cancellation and "already
        // refreshing" checks lie.
        guard refreshGeneration == generation else {
            return
        }
        refreshTask = nil
    }

    private func clearSourceTask(generation: Int) {
        // Calendar-source loading is intentionally opt-in because it can expose
        // account names and request EventKit access. It still needs the same
        // lifecycle guard as event refreshes so a completed source load does not
        // make Control Center think another load is perpetually active.
        guard sourceGeneration == generation else {
            return
        }
        sourceTask = nil
    }
}
