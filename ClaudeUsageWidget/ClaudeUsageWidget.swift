import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

/// The widget only renders what the menu-bar app wrote to the App Group; the app
/// calls reloadAllTimelines() whenever the numbers change.
struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: SnapshotStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: SnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Code Usage")
        .description("Session and weekly limits, plus tokens per model for the last 7 days.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        WidgetContent(family: family, snapshot: entry.snapshot)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// Family is a parameter (not read from the environment) so tools/render-screenshots
/// can draw every size outside a widget host.
struct WidgetContent: View {
    let family: WidgetFamily
    let snapshot: UsageSnapshot?

    var body: some View {
        Group {
            if let snapshot {
                switch family {
                case .systemSmall: SmallLayout(snapshot: snapshot)
                case .systemMedium: MediumLayout(snapshot: snapshot)
                default: LargeLayout(snapshot: snapshot)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle").font(.title2)
                    Text("Open the Claude Usage app to start collecting.")
                        .font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SmallLayout: View {
    let snapshot: UsageSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(snapshot: snapshot)
            if let session = snapshot.session { LimitBar(limit: session, compact: true) }
            if let week = snapshot.weekly.first { LimitBar(limit: week, compact: true) }
            Spacer(minLength: 0)
            if let top = snapshot.models.first {
                HStack {
                    Text(top.displayName).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTokens(top.total) + " / 7d").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MediumLayout: View {
    let snapshot: UsageSnapshot
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Header(snapshot: snapshot)
                if let session = snapshot.session { LimitBar(limit: session, compact: false) }
                ForEach(snapshot.weekly, id: \.kind) { LimitBar(limit: $0, compact: false) }
                if let error = snapshot.apiError { ErrorText(error) }
                Spacer(minLength: 0)
            }
            Divider()
            ModelList(models: snapshot.models, limit: 3, detailed: false)
        }
    }
}

private struct LargeLayout: View {
    let snapshot: UsageSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header(snapshot: snapshot)
            if let session = snapshot.session { LimitBar(limit: session, compact: false) }
            ForEach(snapshot.weekly, id: \.kind) { LimitBar(limit: $0, compact: false) }
            if let error = snapshot.apiError { ErrorText(error) }
            Divider()
            ModelList(models: snapshot.models, limit: 6, detailed: true)
            Spacer(minLength: 0)
            Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct Header: View {
    let snapshot: UsageSnapshot
    var body: some View {
        HStack {
            Text("Claude Code").font(.headline)
            Spacer()
            if let plan = snapshot.plan {
                Text(plan.capitalized).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LimitBar: View {
    let limit: LimitInfo
    let compact: Bool

    private var percent: Int { Int(min(100, max(0, limit.percent)).rounded()) }
    private var tint: Color {
        switch percent {
        case 80...: return .red
        case 50...: return .yellow
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.label).font(compact ? .caption : .subheadline)
                Spacer()
                Text("\(percent)%")
                    .font((compact ? Font.subheadline : .title3).weight(.semibold).monospacedDigit())
            }
            Bar(fraction: Double(percent) / 100, color: tint, height: compact ? 5 : 6)
            if let reset = limit.resetsAt {
                // .relative keeps counting down between timeline refreshes.
                (Text("resets in ") + Text(reset, style: .relative))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ModelList: View {
    let models: [ModelUsage]
    let limit: Int
    let detailed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Models · 7 days").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("tokens").font(.caption2).foregroundStyle(.tertiary)
            }
            if models.isEmpty {
                Text("No activity").font(.caption).foregroundStyle(.secondary)
            }
            let maxTotal = max(1, models.first?.total ?? 1)
            ForEach(models.prefix(limit), id: \.model) { m in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(m.displayName).font(.caption.weight(.medium))
                        Spacer()
                        Text(formatTokens(m.total)).font(.caption.monospacedDigit())
                    }
                    Bar(fraction: Double(m.total) / Double(maxTotal), color: .secondary, height: 4)
                    if detailed {
                        Text("\(m.messages) msgs · \(formatTokens(m.output)) out · \(formatTokens(m.cacheRead)) cache read")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Bar: View {
    let fraction: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

private struct ErrorText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption2).foregroundStyle(.orange).lineLimit(2)
    }
}

#Preview(as: .systemMedium) {
    ClaudeUsageWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder)
}
