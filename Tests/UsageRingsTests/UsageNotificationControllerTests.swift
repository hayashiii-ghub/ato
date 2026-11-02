import Foundation
import Testing
import UsageCore
import UserNotifications
@testable import UsageRings

@MainActor
struct UsageNotificationControllerTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func notificationsAreOptInAndOnlyTheEnableActionRequestsPermission() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller(now: instant)
        await controller.refreshAuthorization()
        await controller.update(snapshot(remaining: 8))?.value
        #expect(!controller.isEnabled && !controller.soundEnabled)
        #expect(fixture.client.permissionRequests == 0)
        #expect(fixture.client.requests.isEmpty)

        await controller.setEnabled(true)
        #expect(controller.isEnabled && controller.isAuthorized)
        #expect(fixture.client.permissionRequests == 1)
        #expect(fixture.client.requests.count == 1)
        #expect(fixture.client.requests[0].content.title.contains("10%"))
        #expect(fixture.client.requests[0].content.body.contains("8% remaining"))
        #expect(fixture.client.requests[0].content.body.contains("Resets in"))
        #expect(fixture.client.requests[0].content.sound == nil)
    }

    @Test func denialDoesNotEnableNotificationsOrChangeMonitoringConsent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.client.grantsPermission = false
        let controller = fixture.controller(now: instant)
        await controller.setEnabled(true)
        #expect(!controller.isEnabled)
        #expect(controller.authorizationStatus == .denied)
        #expect(fixture.defaults.object(forKey: "usageMonitoringEnabled") == nil)
        #expect(fixture.defaults.object(forKey: "usageMonitoringConsentVersion") == nil)
        await controller.setEnabled(true)
        #expect(fixture.client.permissionRequests == 1)
        #expect(fixture.client.requests.isEmpty)
    }

    @Test func deliveryHistorySurvivesRelaunchAndFailedDeliveryCanRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.client.status = .authorized
        let controller = fixture.controller(now: instant)
        await controller.setEnabled(true)
        fixture.client.failingRequests = 1
        await controller.update(snapshot(remaining: 20))?.value
        #expect(controller.errorMessage != nil)
        #expect(fixture.client.requests.isEmpty)
        await controller.update(snapshot(remaining: 20))?.value
        #expect(fixture.client.requests.count == 1)
        #expect(controller.errorMessage == nil)

        let reopened = fixture.controller(now: instant)
        await reopened.update(snapshot(remaining: 20))?.value
        #expect(fixture.client.requests.count == 1)
        await reopened.update(snapshot(remaining: 10, observedAt: instant.addingTimeInterval(1)))?.value
        #expect(fixture.client.requests.count == 2)
        await reopened.update(snapshot(remaining: 4, observedAt: instant.addingTimeInterval(2)))?.value
        #expect(fixture.client.requests.count == 2)
    }

    @Test func soundPreferenceIsSavedAndDisabledAlertsStayQuiet() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.client.status = .authorized
        let controller = fixture.controller(now: instant)
        await controller.setEnabled(true)
        controller.setSoundEnabled(true)
        await controller.update(snapshot(remaining: 8))?.value
        #expect(fixture.client.requests.count == 1)
        #expect(fixture.client.requests[0].content.sound != nil)
        await controller.setEnabled(false)
        await controller.update(snapshot(remaining: 4, observedAt: instant.addingTimeInterval(1)))?.value
        #expect(fixture.client.requests.count == 1)
        #expect(fixture.client.pendingRemovals == 1)
        #expect(!fixture.controller(now: instant).isEnabled)
        #expect(fixture.controller(now: instant).soundEnabled)
    }

    @Test func turningOffWhilePermissionIsPendingKeepsNotificationsOff() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.client.holdsPermission = true
        let controller = fixture.controller(now: instant)
        let enable = Task { await controller.setEnabled(true) }
        await fixture.client.waitForPermissionRequest()
        await controller.setEnabled(false)
        fixture.client.completePermissionRequest()
        await enable.value
        #expect(!controller.isEnabled)
        #expect(fixture.client.requests.isEmpty)
        #expect(!fixture.defaults.bool(forKey: "usageNotificationsEnabled"))
    }

    @Test func aNewSnapshotDuringAuthorizationCheckSupersedesTheQueuedLowReading() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.client.status = .authorized
        let controller = fixture.controller(now: instant)
        await controller.setEnabled(true)
        fixture.client.holdsStatus = true
        let low = controller.update(snapshot(remaining: 8))
        await fixture.client.waitForStatusCheck()
        let disabled = controller.update(.empty)
        fixture.client.completeStatusCheck()
        await low?.value
        await disabled?.value
        #expect(fixture.client.requests.isEmpty)
    }

    @Test func aPartialFailureRetriesOnlyTheFailedAllowanceAndKeepsTheErrorVisible() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.client.status = .authorized
        let controller = fixture.controller(now: instant)
        await controller.setEnabled(true)
        fixture.client.failingRequests = 1
        let codex = snapshot(remaining: 8).services[0]
        let grok = ServiceUsage(service: .grokBot, state: .ready, windows: codex.windows, updatedAt: instant)
        let reading = UsageSnapshot(services: [codex, grok])
        await controller.update(reading)?.value
        #expect(fixture.client.requests.count == 1)
        #expect(controller.errorMessage != nil)
        await controller.update(reading)?.value
        #expect(fixture.client.requests.count == 2)
        #expect(controller.errorMessage == nil)
    }

    private func snapshot(remaining: Double, observedAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(services: [ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 100 - remaining,
                        resetsAt: instant.addingTimeInterval(3_600))
        ], updatedAt: observedAt ?? instant)])
    }

    @MainActor
    private final class Fixture {
        let name = "UsageNotificationControllerTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let client = Client()

        init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
        func cleanUp() { defaults.removePersistentDomain(forName: name) }
        func controller(now: Date) -> UsageNotificationController {
            UsageNotificationController(defaults: defaults, client: client, now: { now })
        }
    }

    @MainActor
    private final class Client: UsageNotificationClient {
        var onOpen: (() -> Void)?
        var status: UNAuthorizationStatus = .notDetermined
        var grantsPermission = true
        var permissionRequests = 0
        var requests: [UNNotificationRequest] = []
        var failingRequests = 0
        var pendingRemovals = 0
        var holdsPermission = false
        var permissionContinuation: CheckedContinuation<Void, Never>?
        var permissionWaiter: CheckedContinuation<Void, Never>?
        var holdsStatus = false
        var statusContinuation: CheckedContinuation<Void, Never>?
        var statusWaiter: CheckedContinuation<Void, Never>?

        func authorizationStatus() async -> UNAuthorizationStatus {
            if holdsStatus {
                await withCheckedContinuation { continuation in
                    statusContinuation = continuation
                    statusWaiter?.resume()
                    statusWaiter = nil
                }
            }
            return status
        }
        func requestAuthorization() async throws -> Bool {
            permissionRequests += 1
            if holdsPermission {
                await withCheckedContinuation { continuation in
                    permissionContinuation = continuation
                    permissionWaiter?.resume()
                    permissionWaiter = nil
                }
            }
            status = grantsPermission ? .authorized : .denied
            return grantsPermission
        }
        func add(_ request: UNNotificationRequest) async throws {
            if failingRequests > 0 {
                failingRequests -= 1
                throw CocoaError(.fileWriteUnknown)
            }
            requests.append(request)
        }
        func removePending() { pendingRemovals += 1 }
        func waitForPermissionRequest() async {
            if permissionContinuation == nil {
                await withCheckedContinuation { permissionWaiter = $0 }
            }
        }
        func completePermissionRequest() {
            permissionContinuation?.resume()
            permissionContinuation = nil
        }
        func waitForStatusCheck() async {
            if statusContinuation == nil { await withCheckedContinuation { statusWaiter = $0 } }
        }
        func completeStatusCheck() {
            holdsStatus = false
            statusContinuation?.resume()
            statusContinuation = nil
        }
    }
}
