import Combine
import Foundation

@MainActor
final class AgentToolsController: ObservableObject {
    @Published private(set) var reports: [AgentToolClient: AgentToolsReport] = [:]
    @Published private(set) var isWorking = false
    @Published private(set) var workingClient: AgentToolClient?
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?

    private let installer: AgentToolsInstaller

    init(installer: AgentToolsInstaller = AgentToolsInstaller(
        appURL: Bundle.main.bundleURL,
        homeURL: FileManager.default.homeDirectoryForCurrentUser
    )) {
        self.installer = installer
    }

    func refresh() async {
        guard !isWorking else { return }
        message = nil
        errorMessage = nil
        isWorking = true
        let installer = installer
        reports = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: AgentToolClient.allCases.map { ($0, installer.check(client: $0)) })
        }.value
        isWorking = false
    }

    func setUp(_ client: AgentToolClient) async {
        await perform(client, removing: false)
    }

    func remove(_ client: AgentToolClient) async {
        await perform(client, removing: true)
    }

    private func perform(_ client: AgentToolClient, removing: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        workingClient = client
        message = nil
        errorMessage = nil
        let installer = installer
        let failure = await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                if removing {
                    _ = try installer.remove(client: client)
                } else {
                    _ = try installer.install(client: client)
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        reports = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: AgentToolClient.allCases.map { ($0, installer.check(client: $0)) })
        }.value
        errorMessage = failure
        if failure == nil {
            message = removing
                ? "Disconnected \(client.displayName)."
                : "Configured \(client.displayName). Start a new session in your assistant."
        }
        workingClient = nil
        isWorking = false
    }
}
