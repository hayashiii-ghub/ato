import AppKit
import UsageCore
import SwiftUI
import WidgetKit

@MainActor
final class UsageStore: ObservableObject {
    private static let preferenceKey = "usageMonitoringEnabled"
    private static let consentKey = "usageMonitoringConsentVersion"
    private static let consentVersion = 1
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var sharingError = false
    @Published private(set) var isEnabled: Bool
    @Published private(set) var needsConsent: Bool
    private let defaults: UserDefaults
    private let fetch: @Sendable (UsageService) async -> ServiceUsage
    private let onPublish: @MainActor () -> Void
    private var pollingTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var generation = 0
    private let bridge = UsageSnapshotServer()

    init(defaults: UserDefaults = .standard,
         fetch: @escaping @Sendable (UsageService) async -> ServiceUsage = { await UsageClient.fetch($0) },
         onPublish: @escaping @MainActor () -> Void = {
             WidgetCenter.shared.reloadTimelines(ofKind: UsageSnapshot.widgetKind)
         }) {
        self.defaults = defaults
        self.fetch = fetch
        self.onPublish = onPublish
        // The pre-consent preference is preserved, but cannot authorize this connection method.
        let hasConsent = defaults.integer(forKey: Self.consentKey) == Self.consentVersion
        needsConsent = !hasConsent
        isEnabled = hasConsent && defaults.bool(forKey: Self.preferenceKey)
    }

    /// Called only by the explicit enable action beside the connection explanation.
    func enableAfterConsent() {
        defaults.set(Self.consentVersion, forKey: Self.consentKey)
        needsConsent = false
        setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) {
        guard !enabled || !needsConsent, isEnabled != enabled else { return }
        generation += 1
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
        if enabled { start() } else { stop() }
    }

    func startIfEnabled() {
        bridge.start(snapshot: { [weak self] in self?.snapshot ?? .empty }, onStateChange: { [weak self] ready in
            self?.sharingError = !ready
        })
        if isEnabled { start() } else { publish() }
    }

    func refresh() async {
        guard !needsConsent, isEnabled, !isRefreshing else { return }
        isRefreshing = true
        let requestGeneration = generation
        defer {
            if generation == requestGeneration { isRefreshing = false }
        }
        async let codex = fetch(.codex)
        async let cursor = fetch(.cursor)
        async let claude = fetch(.claude)
        async let grokBot = fetch(.grokBot)
        let readings = await [codex, cursor, claude, grokBot]
        guard isEnabled, generation == requestGeneration, !Task.isCancelled else { return }
        snapshot = UsageSnapshot(services: readings.map { reading in
            guard reading.state == .unavailable else { return reading }
            var previous = snapshot.usage(for: reading.service)
            previous.state = .unavailable
            return previous
        })
        publish()
    }

    private func start() {
        guard pollingTask == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(5 * 60)) } catch { return }
            }
        }
    }

    private func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isRefreshing = false
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        snapshot = .empty
        publish()
    }

    private func publish() {
        onPublish()
    }
}
