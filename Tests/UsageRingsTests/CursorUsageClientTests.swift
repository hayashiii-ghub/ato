import Foundation
import Testing
import UsageCore
@testable import UsageRings

struct CursorUsageClientTests {
    @Test func cursorUsesItsOwnPlanAndQuotaWithOneSessionRead() async {
        let token = TokenProbe()
        let server = DashboardProbe()
        let result = await UsageClient.fetch(.cursor, cursorToken: { token.read() },
                                             read: { try await server.read($0) })
        #expect(result.service == .cursor)
        #expect(result.state == .ready)
        #expect(result.windows.map(\.id) == ["total"])
        #expect(result.headline?.period == .week)
        #expect(token.count == 1)
        let requests = await server.requests
        #expect(Set(requests.compactMap { $0.url?.lastPathComponent }) == ["GetPlanInfo", "GetCurrentPeriodUsage"])
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "api2.cursor.sh")
            #expect(request.httpMethod == "POST")
            #expect(request.httpBody == Data("{}".utf8))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-session-1")
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        }
    }

    @Test func grokDoesNotReadCursorPlanOrMonthlyQuota() async {
        let token = TokenProbe()
        let server = DashboardProbe()
        let result = await UsageClient.fetch(.grokBot, cursorToken: { token.read() },
                                             read: { try await server.read($0) })
        #expect(result.service == .grokBot)
        #expect(result.state == .ready)
        #expect(token.count == 1)
        #expect(await server.requests.map { $0.url?.lastPathComponent } == ["GetSandUsageStatus"])
    }

    @Test func incompleteWeeklyMetadataCannotFallBackToMonthlyOrGrokQuota() async {
        let token = TokenProbe()
        let server = DashboardProbe(plan: Data(#"{"planInfo":{"includedUsagePeriod":"INCLUDED_USAGE_PERIOD_WEEKLY","billingCycleEnd":"1801454613000"}}"#.utf8))
        let result = await UsageClient.fetch(.cursor, cursorToken: { token.read() },
                                             read: { try await server.read($0) })
        #expect(result.service == .cursor)
        #expect(result.state == .unavailable)
        #expect(result.windows.isEmpty)
        #expect(token.count == 1)
        #expect(await server.requests.count == 2)
    }

    @Test func missingPermissionDoesNotSendAnyProviderRequest() async {
        let server = DashboardProbe()
        for service in [UsageService.cursor, .grokBot] {
            let result = await UsageClient.fetch(service, cursorToken: {
                throw CursorSafeStorage.Failure.permissionRequired
            }, read: { try await server.read($0) })
            #expect(result.service == service)
            #expect(result.state == .setupRequired)
        }
        #expect(await server.requests.isEmpty)
    }
}

private final class TokenProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    func read() -> String {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        return "fixture-session-\(reads)"
    }
}

private actor DashboardProbe {
    private let plan: Data
    private(set) var requests: [URLRequest] = []

    init(plan: Data = Data(#"{"planInfo":{"includedUsagePeriod":"INCLUDED_USAGE_PERIOD_WEEKLY","includedUsageResetsAt":"1801454613000"}}"#.utf8)) {
        self.plan = plan
    }

    func read(_ request: URLRequest) throws -> Data {
        requests.append(request)
        switch request.url?.lastPathComponent {
        case "GetPlanInfo": return plan
        case "GetCurrentPeriodUsage":
            return Data(#"{"enabled":true,"billingCycleEnd":"1804133013000","planUsage":{"totalPercentUsed":25,"autoPercentUsed":20,"apiPercentUsed":30}}"#.utf8)
        case "GetSandUsageStatus":
            return Data(#"{"usagePercent":70,"nextResetTimestampUtc":"2027-02-01T04:03:33Z","hasNonZeroIncludedLimit":true}"#.utf8)
        default: throw UsageReadError.requestFailed
        }
    }
}
