import Foundation

/// Gathers everything the widget shows. Runs unsandboxed in the menu-bar app,
/// which is what lets it read Claude Code's keychain token and ~/.claude/projects.
enum UsageCollector {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"
    static let window: TimeInterval = 7 * 86400

    struct CollectorError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func collect() async -> UsageSnapshot {
        var snapshot = UsageSnapshot(fetchedAt: Date())
        do {
            let creds = try readCredentials()
            snapshot.plan = creds.plan
            let limits = try await fetchLimits(token: creds.token)
            snapshot.session = limits.first { $0.kind == "session" }
            snapshot.weekly = limits.filter { $0.kind.hasPrefix("weekly") }
        } catch {
            snapshot.apiError = error.localizedDescription
        }
        snapshot.models = scanTranscripts(since: Date().addingTimeInterval(-window))
        return snapshot
    }

    // MARK: - Limits (same endpoint Claude Code's /usage uses)

    /// Reads the OAuth token via the `security` CLI, which is already on the item's ACL
    /// (Claude Code wrote it that way), so no keychain prompt appears.
    static func readCredentials() throws -> (token: String, plan: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw CollectorError(message: "No Claude Code login found in keychain — run `claude` once.")
        }
        return (token, oauth["subscriptionType"] as? String)
    }

    static func fetchLimits(token: String) async throws -> [LimitInfo] {
        var request = URLRequest(url: usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw CollectorError(message: status == 401
                ? "Token expired — run `claude` to refresh it."
                : "Usage endpoint returned HTTP \(status).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = json["limits"] as? [[String: Any]] else {
            throw CollectorError(message: "Unexpected usage response.")
        }
        return limits.compactMap { limit in
            guard let kind = limit["kind"] as? String,
                  let percent = limit["percent"] as? Double else { return nil }
            return LimitInfo(kind: kind, percent: percent, resetsAt: parseDate(limit["resets_at"] as? String))
        }
    }

    /// resets_at looks like "2026-09-16T00:00:00.024379+00:00" — six fractional digits,
    /// which ISO8601DateFormatter won't take, so strip them first.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }

    // MARK: - Per-model tokens from local transcripts

    static func scanTranscripts(since cutoff: Date) -> [ModelUsage] {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }

        // Transcript timestamps are UTC ISO strings ("2026-09-15T21:13:36.802Z"); comparing
        // against a cutoff in the same shape avoids parsing a date on every line.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        let cutoffString = formatter.string(from: cutoff)

        var seen = Set<String>()       // streamed chunks repeat the same usage block
        var totals: [String: ModelUsage] = [:]

        for project in projects {
            guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                guard mtime >= cutoff, let data = try? Data(contentsOf: file) else { continue }
                let text = String(decoding: data, as: UTF8.self)
                for line in text.split(separator: "\n") where line.contains("\"type\":\"assistant\"") {
                    guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          entry["type"] as? String == "assistant" else { continue }
                    if let ts = entry["timestamp"] as? String, ts < cutoffString { continue }
                    guard let message = entry["message"] as? [String: Any],
                          let usage = message["usage"] as? [String: Any],
                          let model = message["model"] as? String, !model.hasPrefix("<") else { continue }
                    let key = "\(message["id"] as? String ?? "")|\(entry["requestId"] as? String ?? "")"
                    guard seen.insert(key).inserted else { continue }

                    var t = totals[model] ?? ModelUsage(model: model)
                    t.input += usage["input_tokens"] as? Int ?? 0
                    t.output += usage["output_tokens"] as? Int ?? 0
                    t.cacheCreation += usage["cache_creation_input_tokens"] as? Int ?? 0
                    t.cacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
                    t.messages += 1
                    totals[model] = t
                }
            }
        }
        return totals.values.sorted { $0.total > $1.total }
    }
}
