import UserNotifications

@MainActor
protocol UsageNotificationClient: AnyObject {
    var onOpen: (() -> Void)? { get set }
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePending()
}

@MainActor
final class SystemUsageNotificationClient: NSObject, UsageNotificationClient, UNUserNotificationCenterDelegate {
    static let identifierPrefix = "ato-usage-"
    var onOpen: (() -> Void)?
    private let center: UNUserNotificationCenter

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePending() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let requests = await center.pendingNotificationRequests()
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix("ato-usage-") }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           response.notification.request.identifier.hasPrefix("ato-usage-") {
            Task { @MainActor [weak self] in self?.onOpen?() }
        }
        completionHandler()
    }
}
