import Foundation
import Security
import Testing
import UsageCore
@testable import UsageRings

struct AntigravityQuotaClientTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func summaryMergesHostsAndOnlyTheStandardGeminiQuotaDrivesTheRingAndAlerts() async throws {
        let server = QuotaServer(responses: [
            "daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary": #"""
            {"groups":[{"displayName":"Gemini","buckets":[
                {"bucketId":"gemini-5h","window":"5h","remainingFraction":1,"resetTime":"2027-01-15T13:00:00Z"},
                {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.75,"resetTime":"2027-01-20T00:00:00Z"},
                {"bucketId":"gemini-disabled","disabled":true,"remainingFraction":0}
            ]}]}
            """#,
            "cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary": #"""
            {"buckets":[{"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0},
                        {"bucketId":"gemini-argon-weekly","window":"weekly","remainingFraction":0.1},
                        {"bucketId":"3p-weekly","window":"weekly","remainingFraction":0}]}
            """#
        ])
        var usage = try await AntigravityUsageClient.fetch(token: { "fixture-google" }, read: { try await server.read($0) }, now: now)
        #expect(usage.windows.map(\.id) == ["gemini-5h", "gemini-weekly", "gemini-argon-weekly", "3p-weekly"])
        #expect(usage.windows.first?.resetsAt == nil)
        #expect(usage.remainingPercent(at: now) == 75)
        usage.preferredPeriod = .week
        #expect(usage.remainingPercent(at: now) == 75)
        let report = UsageStatusReport(snapshot: UsageSnapshot(services: [usage]), provider: .gemini, now: now)
        #expect(report.services[0].windows.map(\.isMain) == [true, true, false, false])
        #expect(report.alerts.isEmpty)
        #expect(await server.requests.count == 2)
    }

    @Test func fallsBackToModelQuotaAndKeepsProperPeriodsAndWorstFamilyReading() async throws {
        let server = QuotaServer(responses: [
            "cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary": #"{"buckets":[]}"#,
            "daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels": #"""
            {"models":{
                "gemini-a":{"quotaInfo":{"remainingFraction":0.8}},
                "gemini-b":{"quotaInfo":{"remainingFraction":0.25}},
                "gpt-a":{"weeklyQuotaInfo":{"remainingFraction":0.2}},
                "gemini-bad":{"quotaInfo":{"remainingFraction":1.1}}
            }}
            """#
        ])
        let usage = try await AntigravityUsageClient.fetch(token: { "fixture-google" }, read: { try await server.read($0) }, now: now)
        #expect(usage.windows.map(\.id) == ["gemini-quota", "gpt-weekly"])
        #expect(usage.headline?.period == nil)
        #expect(usage.remainingPercent(at: now) == 25)
        #expect(await server.requests.count == 4)
    }

    @Test func hostMapsMissingExpiredAndLockedCredentialsBeforeAnyNetworkRequest() async {
        for (error, state) in [(UsageReadError.missingSession, UsageState.signInRequired),
                               (.expiredSession, .signInRequired), (.keychainAccessRequired, .setupRequired)] {
            let usage = await UsageClient.fetch(.gemini, antigravityToken: { throw error }, read: { _ in
                Issue.record("No network reads should occur without a valid Antigravity session")
                throw UsageReadError.requestFailed
            })
            #expect(usage.state == state)
            #expect(usage.windows.isEmpty)
        }
    }

    @Test func cliCredentialReadsOnlyTheAccessTokenAndChecksItsExpiry() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = home.appendingPathComponent(".gemini/antigravity-cli")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let credential = folder.appendingPathComponent("antigravity-oauth-token")
        let data = Data(#"{"token":{"access_token":"fixture-google","refresh_token":"unused-fixture","expiry":"2027-01-15T10:00:00.125Z"}}"#.utf8)
        for value in [data, Data("go-keyring-base64:\(data.base64EncodedString())".utf8)] {
            try value.write(to: credential)
            #expect(try AntigravityUsageClient.token(home: home, environment: [:], now: now) == "fixture-google")
        }
        #expect(throws: UsageReadError.self) {
            try AntigravityUsageClient.token(home: home, environment: [:], now: now.addingTimeInterval(7200))
        }
        #expect(throws: UsageReadError.self) {
            try AntigravityUsageClient.token(home: home, environment: ["GEMINI_HOME": home.appendingPathComponent("isolated").path], now: now)
        }
        let query = AntigravityUsageClient.keychainQuery(allowingInteraction: false)
        #expect(query[kSecAttrService as String] as? String == "gemini")
        #expect(query[kSecAttrAccount as String] as? String == "antigravity")
        #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String)
    }
}

private actor QuotaServer {
    let responses: [String: String]
    private(set) var requests: [String] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func read(_ request: URLRequest) throws -> Data {
        let url = try #require(request.url)
        #expect(url.scheme == "https")
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == Data("{}".utf8))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-google")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("antigravity/") == true)
        let key = "\(url.host ?? "")\(url.path)"
        requests.append(key)
        guard let body = responses[key] else { throw UsageReadError.requestFailed }
        return Data(body.utf8)
    }
}
