import SwiftUI
import ServiceManagement

@main
struct ClaudeUsageApp: App {
    @StateObject private var service = UsageService()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(service: service)
        } label: {
            Label(service.menuTitle, systemImage: "gauge.with.needle")
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var service: UsageService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if let s = service.snapshot {
            if let session = s.session { limitRow(session) }
            ForEach(s.weekly, id: \.kind) { limitRow($0) }
            if let error = s.apiError { Text("Limits unavailable: \(error)") }

            Divider()
            Text("Models · last 7 days")
            ForEach(s.models, id: \.model) { m in
                Text("\(m.displayName)   \(formatTokens(m.total)) tokens · \(m.messages) msgs")
            }
            if s.models.isEmpty { Text("No activity") }

            Divider()
            Text("Updated \(s.fetchedAt.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("Loading…")
        }

        Divider()
        Button(service.refreshing ? "Refreshing…" : "Refresh Now") {
            Task { await service.refresh() }
        }
        .disabled(service.refreshing)
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        Divider()
        Button("Quit Claude Usage") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func limitRow(_ limit: LimitInfo) -> some View {
        var text = "\(limit.label): \(Int(limit.percent.rounded()))%"
        if let reset = limit.resetsAt {
            text += "  ·  resets \(reset.formatted(.relative(presentation: .named)))"
        }
        return Text(text)
    }
}
