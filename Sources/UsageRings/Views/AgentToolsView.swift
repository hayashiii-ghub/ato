import AppKit
import SwiftUI

@MainActor
struct AgentToolsView: View {
    @ObservedObject var controller: AgentToolsController
    @State private var removingClient: AgentToolClient?
    private static let codexApprovalHint = "If not yet approved, open /hooks in Codex CLI and trust ato?. Check in a new session."

    var body: some View {
        SettingsSection("AI Tools") {
            ForEach(AgentToolClient.allCases) { client in
                if client != .cursor || controller.reports[client]?.canRemove == true {
                    clientRow(client)
                }
            }
            if let error = controller.errorMessage {
                SettingsNote(error, isWarning: true)
            } else if let message = controller.message {
                SettingsNote(message)
            }
        }
        .task { await controller.refresh() }
        // Coming back from fixing a file elsewhere should not need a button press.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh() }
        }
        .confirmationDialog("Disconnect \(removingClient?.displayName ?? "assistant")?",
                            isPresented: Binding(
                                get: { removingClient != nil },
                                set: { if !$0 { removingClient = nil } }
                            ), titleVisibility: .visible) {
            if let client = removingClient {
                Button("Disconnect", role: .destructive) {
                    removingClient = nil
                    Task { await controller.remove(client) }
                }
            }
            Button("Cancel", role: .cancel) { removingClient = nil }
        } message: {
            Text("Remove the skill and budget hook installed by ato?. Other assistant settings are preserved. The shared CLI stays while another assistant uses it.")
        }
    }

    private func clientRow(_ client: AgentToolClient) -> some View {
        let report = controller.reports[client]
        let blocker = report.flatMap(blocker)
        return SettingsRow(client.displayName, detail: detail(report), isWarning: blocker != nil) {
            // One thing on the right says where this assistant stands: the action it needs, or that it is connected.
            if let path = blocker?.path, !path.isEmpty {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            } else if let report, blocker == nil {
                if report.isInstalled {
                    Text("Connected")
                        .font(SettingsStyle.caption)
                        .foregroundStyle(.secondary)
                } else if client != .cursor {
                    Button(report.needsUpdate ? "Update" : "Set Up") {
                        Task { await controller.setUp(client) }
                    }
                    .disabled(controller.isWorking)
                }
            }
            // A fixed slot keeps the right edge in one column on rows that have nothing to disconnect.
            Group {
                if report?.canRemove == true {
                    Menu {
                        Button("Disconnect…", role: .destructive) { removingClient = client }
                    } label: {
                        SettingsIcon(name: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .disabled(controller.isWorking)
                    .accessibilityLabel("More for \(client.displayName)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 28, height: 24)
        }
        .help(details(report))
        .accessibilityElement(children: .contain)
    }

    /// A second line only when there is something to act on.
    private func detail(_ report: AgentToolsReport?) -> String? {
        guard let report else { return nil }
        if let blocker = blocker(report) {
            return blocker.path.isEmpty
                ? blocker.message
                : blocker.message + "\n" + (blocker.path as NSString).abbreviatingWithTildeInPath
        }
        return report.isInstalled && report.requiresTrustReview ? "If Codex asks, trust ato? under /hooks." : nil
    }

    private func blocker(_ report: AgentToolsReport) -> AgentToolsComponentReport? {
        [report.cli, report.skill, report.hook].first { $0.state == .conflict }
    }

    private func details(_ report: AgentToolsReport?) -> String {
        guard let report else { return "Checking…" }
        var text = "CLI: \(report.cli.message)\nSkill: \(report.skill.message)\nHook: \(report.hook.message)"
        if report.requiresTrustReview && report.isInstalled {
            text += "\n" + Self.codexApprovalHint
        }
        return text
    }
}
