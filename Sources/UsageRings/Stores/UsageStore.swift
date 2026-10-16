import AppKit
import UsageCore
import SwiftUI
import WidgetKit

@MainActor
final class UsageStore: ObservableObject {
    private static let preferenceKey = "usageMonitoringEnabled"
    private static let consentKey = "usageMonitoringConsentVersion"
    private static let consentVersion = 1
    private static let ringOrderKey = "usageRingOrder"
    private static let preferredPeriodsKey = "usagePreferredPeriods"
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var sharingError = false
    @Published private(set) var isEnabled: Bool
    @Published private(set) var needsConsent: Bool
    @Published private(set) var ringOrder: [UsageService]
    @Published private(set) var preferredPeriods: [UsageService: UsagePeriod]
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
        let resumesMonitoring = hasConsent && defaults.bool(forKey: Self.preferenceKey)
        needsConsent = !resumesMonitoring
        isEnabled = resumesMonitoring
        let savedOrder = defaults.stringArray(forKey: Self.ringOrderKey)?.compactMap(UsageService.init(rawValue:))
        ringOrder = UsageSnapshot.normalizedRingOrder(savedOrder ?? UsageSnapshot.defaultRingOrder)
        preferredPeriods = (defaults.dictionary(forKey: Self.preferredPeriodsKey) ?? [:]).reduce(into: [:]) { result, entry in
            guard let service = UsageService(rawValue: entry.key), let rawPeriod = entry.value as? String,
                  let period = UsagePeriod(rawValue: rawPeriod) else { return }
            result[service] = period
        }
        snapshot = UsageSnapshot(services: applyingPreferredPeriods(to: UsageSnapshot.empty.services), ringOrder: ringOrder)
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

    func selectRing(_ service: UsageService, at index: Int) {
        guard ringOrder.indices.contains(index) else { return }
        var order = ringOrder
        if let previousIndex = order.firstIndex(of: service) {
            order.swapAt(index, previousIndex)
        } else {
            order[index] = service
        }
        setRingOrder(order)
    }

    func moveRing(from index: Int, to destination: Int) {
        guard ringOrder.indices.contains(index), ringOrder.indices.contains(destination) else { return }
        var order = ringOrder
        let service = order.remove(at: index)
        order.insert(service, at: destination)
        setRingOrder(order)
    }

    func setPreferredPeriod(_ period: UsagePeriod?, for service: UsageService) {
        guard preferredPeriods[service] != period else { return }
        preferredPeriods[service] = period
        let saved = Dictionary(uniqueKeysWithValues: preferredPeriods.map { ($0.key.rawValue, $0.value.rawValue) })
        defaults.set(saved, forKey: Self.preferredPeriodsKey)
        snapshot = UsageSnapshot(services: applyingPreferredPeriods(to: snapshot.services), ringOrder: ringOrder)
        publish()
    }

    private func setRingOrder(_ order: [UsageService]) {
        let order = UsageSnapshot.normalizedRingOrder(order)
        guard order != ringOrder else { return }
        let selectionChanged = Set(order) != Set(ringOrder)
        if selectionChanged {
            generation += 1
            stopPolling()
        }
        ringOrder = order
        defaults.set(order.map(\.rawValue), forKey: Self.ringOrderKey)
        let readings = UsageService.allCases.map { service in
            order.contains(service) ? snapshot.usage(for: service) : ServiceUsage(service: service, state: .disabled)
        }
        snapshot = UsageSnapshot(services: applyingPreferredPeriods(to: readings), ringOrder: order)
        publish()
        if selectionChanged && isEnabled { start() }
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
        let selectedServices = ringOrder
        async let first = fetch(selectedServices[0])
        async let second = fetch(selectedServices[1])
        async let third = fetch(selectedServices[2])
        async let fourth = fetch(selectedServices[3])
        let readings = await [first, second, third, fourth]
        guard isEnabled, generation == requestGeneration, !Task.isCancelled else { return }
        snapshot = UsageSnapshot(services: applyingPreferredPeriods(to: readings.map { reading in
            guard reading.state == .unavailable else { return reading }
            var previous = snapshot.usage(for: reading.service)
            previous.state = .unavailable
            return previous
        }), ringOrder: ringOrder)
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

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isRefreshing = false
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func stop() {
        stopPolling()
        snapshot = UsageSnapshot(services: applyingPreferredPeriods(to: UsageSnapshot.empty.services), ringOrder: ringOrder)
        publish()
    }

    private func applyingPreferredPeriods(to readings: [ServiceUsage]) -> [ServiceUsage] {
        readings.map { reading in
            var reading = reading
            reading.preferredPeriod = preferredPeriods[reading.service]
            return reading
        }
    }

    private func publish() {
        onPublish()
    }
}
