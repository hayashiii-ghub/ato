import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdateController: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    private(set) var controller: SPUStandardUpdaterController!
    @Published private(set) var canCheckForUpdates = false
    let configurationMessage: String?
    private var availabilityObserver: AnyCancellable?

    override init() {
        let feedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)
            .flatMap(URL.init(string:))
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isConfigured = feedURL?.scheme == "https" && feedURL?.host != nil && publicKey?.isEmpty == false
        configurationMessage = isConfigured ? nil : "Updates aren’t configured for this build."
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        availabilityObserver = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    func start() {
        guard configurationMessage == nil else { return }
        controller.startUpdater()
    }

    func standardUserDriverWillShowModalAlert() {
        activateUpdateUI()
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        activateUpdateUI()
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func activateUpdateUI() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
