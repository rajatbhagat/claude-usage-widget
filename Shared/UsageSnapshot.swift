import Foundation

/// One rate-limit window as reported by Claude's usage endpoint (the same data `/usage` shows).
struct LimitInfo: Codable, Equatable {
    var kind: String        // "session", "weekly_all", "weekly_opus", ...
    var percent: Double
    var resetsAt: Date?

    var label: String {
        switch kind {
        case "session": return "Session (5h)"
        case "weekly_all": return "Week · all models"
        default:
            let name = kind.replacingOccurrences(of: "weekly_", with: "").replacingOccurrences(of: "_", with: " ")
            return "Week · " + name.capitalized
        }
    }
}

/// Tokens for one model, summed from local transcripts over the last 7 days.
struct ModelUsage: Codable, Equatable {
    var model: String
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0
    var messages = 0

    var total: Int { input + output + cacheCreation + cacheRead }

    /// claude-opus-5 -> "Opus 5", claude-haiku-4-5-20251001 -> "Haiku 4.5"
    var displayName: String {
        var parts = model.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        parts.removeAll { $0.count == 8 && Int($0) != nil }   // trailing date stamp
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().filter { Int($0) != nil }.joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var plan: String?
    var session: LimitInfo?
    var weekly: [LimitInfo] = []
    var models: [ModelUsage] = []
    var apiError: String?

    /// Shown in the widget gallery and while the app hasn't written real data yet.
    static let placeholder = UsageSnapshot(
        fetchedAt: Date(),
        plan: "pro",
        session: LimitInfo(kind: "session", percent: 42, resetsAt: Date().addingTimeInterval(2.7 * 3600)),
        weekly: [LimitInfo(kind: "weekly_all", percent: 7, resetsAt: Date().addingTimeInterval(6.5 * 86400))],
        models: [
            ModelUsage(model: "claude-opus-5", input: 1_400, output: 497_000, cacheCreation: 3_000_000, cacheRead: 262_000_000, messages: 698),
            ModelUsage(model: "claude-sonnet-5", input: 750, output: 346_000, cacheCreation: 1_500_000, cacheRead: 70_400_000, messages: 378),
            ModelUsage(model: "claude-haiku-4-5-20251001", input: 44, output: 860, cacheCreation: 36_000, cacheRead: 143_000, messages: 5),
        ]
    )
}

/// JSON file the app writes and the widget reads. An App Group would be the usual
/// bridge, but that needs a provisioning profile; instead the sandboxed widget reads
/// its own container's Application Support folder and the unsandboxed app writes
/// straight into that container path.
enum SnapshotStore {
    static let widgetBundleID = "com.rajatbhagat.claudeusage.widget"

    static var url: URL {
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let support = isSandboxed
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support")
        return support.appendingPathComponent("ClaudeUsage/usage.json")
    }

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}

func formatTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000_000...: return String(format: "%.2fB", Double(n) / 1e9)
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6)
    case 1_000...: return String(format: "%.0fk", Double(n) / 1e3)
    default: return String(n)
    }
}
