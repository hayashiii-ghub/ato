import Foundation
import Testing
import UsageCore
@testable import UsageRings

struct GrokBotUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func readsWeeklyRemainingAndFractionalReset() throws {
        let data = Data(#"{"config":{"creditUsagePercent":12.942227,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2027-02-01T04:03:33.761Z"}}}"#.utf8)
        let usage = try UsageResponseParser.grokBuild(data, now: now)
        #expect(usage.service == .grokBot)
        #expect(usage.headline?.period == .week)
        #expect(abs((usage.remainingPercent(at: now) ?? 0) - 87.057773) < 0.000001)
        let reset = try #require(usage.headline?.resetsAt)
        #expect(abs(reset.timeIntervalSince1970 - 1_801_454_613.761) < 0.001)
        #expect(usage.remainingPercent(at: reset) == nil)
    }

    @Test func zeroOmittedByGrokNeedsAnActiveCompleteSubscriptionPeriod() throws {
        let valid = Data(#"{"config":{"currentPeriod":{"type":"MONTHLY","start":"2027-01-01T00:00:00Z","end":"2027-02-01T04:03:33Z"}}}"#.utf8)
        let usage = try UsageResponseParser.grokBuild(valid, now: now)
        #expect(usage.remainingPercent(at: now) == 100)
        #expect(usage.headline?.title == "This month")
        let passed = try #require(usage.headline?.resetsAt)
        #expect(throws: UsageReadError.self) { try UsageResponseParser.grokBuild(valid, now: passed) }
        for payload in [
            #"{}"#,
            #"{"config":{"currentPeriod":{"type":"MONTHLY","end":"2027-02-01T04:03:33Z"}}}"#,
            #"{"config":{"currentPeriod":{"type":"MONTHLY","start":"2027-01-01T00:00:00Z","end":"2027-02-30T00:00:00Z"}}}"#,
            #"{"config":{"creditUsagePercent":-1}}"#,
            #"{"usagePercent":12,"nextResetTimestampUtc":"2027-02-01T04:03:33Z","hasNonZeroIncludedLimit":true}"#
        ] {
            #expect(throws: UsageReadError.self) { try UsageResponseParser.grokBuild(Data(payload.utf8), now: now) }
        }
    }

    @Test func hostFetchOnlySendsGrokBuildCredentialsToItsBillingEndpoint() async {
        let result = await UsageClient.fetch(.grokBot, grokToken: { "fixture-grok" }, read: { request in
            #expect(request.url?.absoluteString == "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-grok")
            return Data(#"{"config":{"creditUsagePercent":100,"currentPeriod":{"type":"WEEKLY"}}}"#.utf8)
        })
        #expect(result.state == .ready)
        #expect(result.headline?.remainingPercent == 0)
    }

    @Test func nativeSessionSelectsOnlyTheStockProviderAndRejectsCustomAuth() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = folder.appendingPathComponent(".grok")
        let system = folder.appendingPathComponent("etc")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let credentials = Data(#"{"https://accounts.x.ai/sign-in":{"key":"fixture-grok","auth_mode":"oauth"},"other":{"key":"other"}}"#.utf8)
        try credentials.write(to: profile.appendingPathComponent("auth.json"))
        #expect(try GrokBuildUsageClient.token(home: folder, systemConfiguration: system, environment: [:]) == "fixture-grok")
        #expect(throws: UsageReadError.self) {
            try GrokBuildUsageClient.token(home: folder, systemConfiguration: system, environment: ["XAI_API_KEY": "fixture"])
        }
        try Data("[auth.custom]\nauth_mode = \"oidc\"".utf8).write(to: profile.appendingPathComponent("config.toml"))
        #expect(throws: UsageReadError.self) {
            try GrokBuildUsageClient.token(home: folder, systemConfiguration: system, environment: [:])
        }
    }

    @Test func grokSnapshotRoundTripsThroughWidgetBridge() throws {
        let usage = ServiceUsage(service: .grokBot, state: .ready,
                                 windows: [UsageWindow(id: "subscription", title: "Week", usedPercent: 13, resetsAt: nil)], updatedAt: now)
        let snapshot = UsageSnapshot(services: [usage])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: data) == snapshot)
    }
}
