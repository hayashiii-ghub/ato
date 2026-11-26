// Mirrored by hand in ato? and cc: (Sources/*/Shared). Keep both copies identical.
import AppKit
import Combine
import Sparkle

/// Drives Sparkle without its own windows; `SettingsFooter` renders `status` inside the settings panel.
@MainActor
final class AppUpdateController: NSObject, ObservableObject, SPUUserDriver {
    enum Status: Equatable {
        case idle
        case message(String, isError: Bool)
        case askingPermission
        case checking
        case available(version: String, info: URL?, informationOnly: Bool)
        case downloading(fraction: Double?)
        case preparing(fraction: Double)
        case readyToInstall
        case installing
    }

    @Published private(set) var status = Status.idle
    @Published private(set) var canCheckForUpdates = false
    /// False for builds without a feed and signing key, which never start the updater.
    @Published private(set) var isConfigured = false
    /// A scheduled check found something the user has to decide; the host shows the settings panel.
    var onNeedsAttention: () -> Void = {}
    private(set) var updater: SPUUpdater!

    private var availabilityObserver: AnyCancellable?
    private var permissionReply: ((SUUpdatePermissionResponse) -> Void)?
    private var choiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var cancellation: (() -> Void)?
    private var resultExpiry: Task<Void, Never>?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    override init() {
        super.init()
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        availabilityObserver = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    func start() {
        let feedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard feedURL?.scheme == "https", feedURL?.host != nil, publicKey?.isEmpty == false else {
            status = .message("Updates aren’t configured for this build.", isError: false)
            return
        }
        do {
            try updater.start()
            isConfigured = true
        } catch {
            status = .message(error.localizedDescription, isError: true)
        }
    }

    // MARK: Preferences

    var checksAutomatically: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    var installsAutomatically: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    // MARK: User actions

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func allowAutomaticChecks(_ allow: Bool) {
        let reply = permissionReply
        permissionReply = nil
        status = .idle
        reply?(SUUpdatePermissionResponse(automaticUpdateChecks: allow, sendSystemProfile: false))
    }

    func install() {
        guard case let .available(_, info, informationOnly) = status, informationOnly else {
            return reply(.install)
        }
        // Information-only items cannot be installed in place; their page explains the manual steps.
        if let info { NSWorkspace.shared.open(info) }
        reply(.dismiss)
    }

    func later() {
        reply(.dismiss)
    }

    func cancel() {
        let cancellation = cancellation
        self.cancellation = nil
        cancellation?()
    }

    /// Forgets a finished check's result once the panel closes. The unconfigured notice stays,
    /// since nothing else explains the disabled button.
    func clearResult() {
        if case .message = status, canCheckForUpdates { status = .idle }
    }

    /// A result is news for a moment, not a state: it leaves the footer by itself.
    private func showResult(_ text: String, isError: Bool) {
        status = .message(text, isError: isError)
        resultExpiry?.cancel()
        resultExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 10 : 4))
            guard !Task.isCancelled else { return }
            self?.clearResult()
        }
    }

    private func reply(_ choice: SPUUserUpdateChoice) {
        let reply = choiceReply
        choiceReply = nil
        reply?(choice)
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        permissionReply = reply
        status = .askingPermission
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        status = .checking
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        cancellation = nil
        choiceReply = reply
        status = .available(
            version: appcastItem.displayVersionString,
            info: appcastItem.infoURL,
            informationOnly: appcastItem.isInformationOnlyUpdate
        )
        if !state.userInitiated { onNeedsAttention() }
    }

    // The appcasts carry a link instead of release notes.
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        showResult(error.localizedDescription, isError: false)
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        showResult(error.localizedDescription, isError: true)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        expectedLength = 0
        receivedLength = 0
        status = .downloading(fraction: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        status = .downloading(
            fraction: expectedLength > 0 ? min(1, Double(receivedLength) / Double(expectedLength)) : nil
        )
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        status = .preparing(fraction: 0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        status = .preparing(fraction: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        choiceReply = reply
        status = .readyToInstall
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        status = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        onNeedsAttention()
    }

    func dismissUpdateInstallation() {
        choiceReply = nil
        cancellation = nil
        // Sparkle ends the session right after an acknowledged result; keep that result readable.
        if case .message = status { return }
        status = .idle
    }
}
