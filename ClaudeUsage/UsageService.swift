import Foundation
import WidgetKit

/// Polls usage on a timer, persists it for the widget, and asks WidgetKit to redraw
/// only when something actually changed (widget reloads are budgeted by the system).
@MainActor
final class UsageService: ObservableObject {
    static let interval: TimeInterval = 120

    @Published private(set) var snapshot: UsageSnapshot? = SnapshotStore.load()
    @Published private(set) var refreshing = false
    private var timer: Timer?

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let fresh = await UsageCollector.collect()
        let changed = fresh.session != snapshot?.session
            || fresh.weekly != snapshot?.weekly
            || fresh.models != snapshot?.models
            || fresh.apiError != snapshot?.apiError
        snapshot = fresh
        try? SnapshotStore.save(fresh)
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    var menuTitle: String {
        guard let session = snapshot?.session else { return "–" }
        return "\(Int(session.percent.rounded()))%"
    }
}
