import SwiftUI

@MainActor
struct AgentToolsView: View {
    @ObservedObject var controller: AgentToolsController
    @State private var removingClient: AgentToolClient?
    private static let codexApprovalHint = "If not yet approved, open /hooks in Codex CLI and trust ato?. Check in a new session."

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("AI Tools").font(SettingsStyle.heading).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await controller.refresh() } } label: {
                    if controller.isWorking {
                        ProgressView().controlSize(.mini)
                            .frame(width: 28, height: 28)
                    } else {
                        SettingsIcon(name: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(controller.isWorking)
                .accessibilityLabel("Check AI Tools")
                .help("Check AI tools")
            }
            .frame(minHeight: 28)
            ForEach(AgentToolClient.allCases) { client in
                clientRow(client)
            }
            if let error = controller.errorMessage {
                Text(error).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let message = controller.message {
                Text(message).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await controller.refresh() }
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
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(client.displayName)
                if report?.isInstalled == true {
                    Image(systemName: "checkmark")
                        .font(SettingsStyle.statusSymbol)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Tools installed")
                }
                if report?.requiresTrustReview == true && report?.isInstalled == true {
                    Link(destination: URL(string: "https://github.com/hayashiii-ghub/ato#cli-and-ai-skill")!) {
                        SettingsIcon(name: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Codex hook approval")
                    .accessibilityHint(Self.codexApprovalHint)
                    .help(Self.codexApprovalHint)
                }
                Spacer(minLength: 8)
                if report?.canRemove == true {
                    Button("Disconnect…") { removingClient = client }
                        .buttonSizing(.flexible)
                        .controlSize(.large)
                        .frame(width: 104, height: 28)
                        .disabled(controller.isWorking)
                }
                if report?.isInstalled != true {
                    Button(report?.needsUpdate == true ? "Update" : "Set Up") {
                        Task { await controller.setUp(client) }
                    }
                    .buttonSizing(.flexible)
                    .controlSize(.large)
                    .frame(width: 104, height: 28)
                    .disabled(controller.isWorking || report == nil || report?.hasConflict == true)
                }
            }
            .frame(minHeight: 32)
            if let report, report.hasConflict {
                Text([report.cli, report.skill, report.hook]
                    .first(where: { $0.state == .conflict })?.message ?? "Existing files need review.")
                    .font(SettingsStyle.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(details(report))
        .accessibilityElement(children: .contain)
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
