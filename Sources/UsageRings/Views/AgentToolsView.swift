import AppKit
import SwiftUI

@MainActor
struct AgentToolsView: View {
    @StateObject private var controller: AgentToolsController
    @State private var removingClient: AgentToolClient?
    let onBack: () -> Void

    init(onBack: @escaping () -> Void, controller: AgentToolsController? = nil) {
        self.onBack = onBack
        _controller = StateObject(wrappedValue: controller ?? AgentToolsController())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Tools").font(.title2.weight(.semibold))
                Spacer()
                Button("Back") { onBack() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(controller.isWorking)
            }

            Text("Set up the CLI, skill and budget hook together for the assistant you use on this Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AgentToolClient.allCases) { client in
                        clientRow(client)
                        if client != AgentToolClient.allCases.last {
                            Divider().padding(.vertical, 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }

            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let message = controller.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Budget hooks share fresh allowance notices with your assistant. Set Up adds files and hook settings; usage monitoring and status-line helpers are managed separately.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Check Again") { Task { await controller.refresh() } }
                    .disabled(controller.isWorking)
                if controller.isWorking {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Checking or setting up AI tools")
                }
                Spacer()
                Link("Setup Help", destination: URL(string: "https://github.com/hayashiii-ghub/ato#cli-and-ai-skill")!)
                Button("Quit ato?") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
                    .disabled(controller.isWorking)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.displayName).font(.headline)
                    Text(summary(report))
                        .font(.caption)
                        .foregroundStyle(report?.hasConflict == true ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if report?.canRemove == true {
                    Button("Disconnect…") { removingClient = client }
                        .disabled(controller.isWorking)
                }
                if report?.isInstalled != true {
                    Button(report?.needsUpdate == true ? "Update" : "Set Up") {
                        Task { await controller.setUp(client) }
                    }
                        .disabled(controller.isWorking || report == nil || report?.hasConflict == true)
                }
            }
            if let report {
                HStack(spacing: 16) {
                    component("CLI", report.cli)
                    component("Skill", report.skill)
                    component("Hook", report.hook)
                }
                .font(.caption)
                if report.requiresTrustReview && report.isInstalled {
                    Text("If not yet approved, open /hooks in Codex CLI and trust the ato? command. Check it in a new session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func summary(_ report: AgentToolsReport?) -> String {
        guard let report else { return "Checking…" }
        if report.hasConflict {
            return [report.cli, report.skill, report.hook]
                .first(where: { $0.state == .conflict })?.message ?? "Existing files need review."
        }
        if report.needsUpdate { return "Update the tools bundled with this app." }
        return report.isInstalled ? "Configured" : "Set up all three together."
    }

    private func component(_ title: String, _ report: AgentToolsComponentReport) -> some View {
        Label(title, systemImage: report.state == .installed ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(report.state == .installed ? .secondary : .tertiary)
            .help(report.message)
            .accessibilityLabel("\(title): \(report.message)")
    }
}
