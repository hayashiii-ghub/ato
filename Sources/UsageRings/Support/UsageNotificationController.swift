import SwiftUI
import UsageCore
import UserNotifications

@MainActor
final class UsageNotificationController: ObservableObject {
    private static let enabledKey = "usageNotificationsEnabled"
    private static let soundKey = "usageNotificationSoundEnabled"
    private static let trackerKey = "usageNotificationHistory"
    @Published private(set) var isEnabled: Bool
    @Published private(set) var soundEnabled: Bool
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let client: any UsageNotificationClient
    private let now: () -> Date
    private var tracker: UsageNotificationTracker
    private var latestSnapshot: UsageSnapshot = .empty
    private var pendingSnapshot: UsageSnapshot?
    private var processingTask: Task<Void, Never>?
    private var generation = 0

    init(defaults: UserDefaults = .standard, client: (any UsageNotificationClient)? = nil,
         now: @escaping () -> Date = Date.init, onOpen: (() -> Void)? = nil) {
        self.defaults = defaults
        self.client = client ?? SystemUsageNotificationClient()
        self.now = now
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        soundEnabled = defaults.bool(forKey: Self.soundKey)
        tracker = defaults.data(forKey: Self.trackerKey).flatMap {
            guard $0.count <= 128 * 1_024 else { return nil }
            return try? JSONDecoder().decode(UsageNotificationTracker.self, from: $0)
        } ?? UsageNotificationTracker()
        self.client.onOpen = onOpen
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    func refreshAuthorization() async {
        authorizationStatus = await client.authorizationStatus()
        if isEnabled && isAuthorized { await update(latestSnapshot)?.value }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !enabled || !isRequestingAuthorization else { return }
        generation += 1
        let requestGeneration = generation
        errorMessage = nil
        if !enabled {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            pendingSnapshot = nil
            client.removePending()
            return
        }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        var status = await client.authorizationStatus()
        guard requestGeneration == generation else { return }
        if status == .notDetermined {
            do {
                _ = try await client.requestAuthorization()
                status = await client.authorizationStatus()
            } catch {
                guard requestGeneration == generation else { return }
                errorMessage = "Could not request notification permission. Try again."
                return
            }
        }
        guard requestGeneration == generation else { return }
        authorizationStatus = status
        isEnabled = isAuthorized
        defaults.set(isEnabled, forKey: Self.enabledKey)
        if isEnabled { await update(latestSnapshot)?.value }
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        defaults.set(enabled, forKey: Self.soundKey)
    }

    @discardableResult
    func update(_ snapshot: UsageSnapshot) -> Task<Void, Never>? {
        latestSnapshot = snapshot
        guard isEnabled else { return nil }
        pendingSnapshot = snapshot
        if processingTask == nil {
            processingTask = Task { [weak self] in
                await self?.processPending()
            }
        }
        return processingTask
    }

    private func processPending() async {
        defer { processingTask = nil }
        while let queuedSnapshot = pendingSnapshot {
            pendingSnapshot = nil
            let requestGeneration = generation
            guard isEnabled else { continue }
            authorizationStatus = await client.authorizationStatus()
            guard isEnabled, isAuthorized, requestGeneration == generation else { continue }
            let snapshot = pendingSnapshot ?? queuedSnapshot
            pendingSnapshot = nil
            let report = UsageStatusReport(snapshot: snapshot, now: now())
            let notices = tracker.notices(for: report)
            saveHistory()
            errorMessage = nil
            for notice in notices {
                guard isEnabled, requestGeneration == generation, pendingSnapshot == nil else { break }
                do {
                    try await client.add(request(for: notice))
                    tracker.markDelivered(notice)
                    saveHistory()
                    if !isEnabled { client.removePending() }
                } catch {
                    errorMessage = "Could not send a usage notification. It will retry after the next update."
                }
            }
        }
    }

    private func request(for notice: UsageNotificationTracker.Notice) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(notice.service.name): \(notice.thresholdPercent)% or less remaining"
        let remaining = notice.remainingPercent.formatted(.number.precision(.fractionLength(0...1)))
        let reset: String
        if let resetsAt = notice.resetsAt,
           let countdown = UsageDisplayText.countdown(until: resetsAt, from: now()) {
            reset = "Resets in \(countdown)."
        } else {
            reset = "Reset time unavailable."
        }
        content.body = "\(notice.title): \(remaining)% remaining. \(reset)"
        content.threadIdentifier = "ato-usage-\(notice.service.rawValue)"
        if soundEnabled { content.sound = .default }
        return UNNotificationRequest(identifier: SystemUsageNotificationClient.identifierPrefix + UUID().uuidString,
                                     content: content, trigger: nil)
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(tracker) else { return }
        defaults.set(data, forKey: Self.trackerKey)
    }
}
