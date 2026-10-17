import Foundation
import Testing
import UsageCore
@testable import UsageRingsCLI

@Suite(.serialized)
struct UsageCLITests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func argumentsSupportProviderAliasesAndRejectUnsupportedActions() throws {
        #expect(try UsageCLICommand(arguments: []) == .help)
        #expect(try UsageCLICommand(arguments: ["--help"]) == .help)
        #expect(try UsageCLICommand(arguments: ["status", "--help"]) == .help)
        #expect(try UsageCLICommand(arguments: ["status"]) == .status(json: false, provider: nil))
        #expect(try UsageCLICommand(arguments: ["status", "--json", "--provider", "grok"])
                == .status(json: true, provider: .grokBot))
        #expect(try UsageCLICommand(arguments: ["status", "--provider", "grokBot", "--json"])
                == .status(json: true, provider: .grokBot))
        for invalid in [
            ["refresh"], ["status", "--provider"], ["status", "--provider", "unknown"],
            ["status", "--json", "--json"], ["status", "--provider", "codex", "--provider", "claude"],
            ["status", "--endpoint", "https://example.invalid"], ["--help", "status"]
        ] {
            #expect(throws: UsageCLIError.invalidArguments) { try UsageCLICommand(arguments: invalid) }
        }
    }

    @Test func helpAndUsageErrorsDoNotContactTheApp() async throws {
        let help = await UsageCLI.run(arguments: ["--help"], fetch: { throw UsageCLIError.appUnavailable })
        #expect(help.exitCode == 0)
        #expect(help.output.contains("usage-rings status"))
        let invalid = await UsageCLI.run(arguments: ["refresh", "--json"], fetch: { throw UsageCLIError.appUnavailable })
        #expect(invalid.exitCode == 2)
        #expect(try object(invalid.output)["error"] as? String == "invalidArguments")
        let badThreshold = await UsageCLI.run(arguments: ["status", "--json", "--threshold", "nan"],
                                               fetch: { throw UsageCLIError.appUnavailable })
        #expect(badThreshold.exitCode == 2)
        #expect(try object(badThreshold.output)["error"] as? String == "invalidArguments")
    }

    @Test func thresholdArgumentsDefaultToTwentyAndRejectMissingRepeatedOrInvalidValues() throws {
        #expect(try UsageCLICommand(arguments: ["status"]) == .status(json: false, provider: nil, thresholdPercent: 20))
        #expect(try UsageCLICommand(arguments: ["status", "--threshold", "12.5", "--json"])
                == .status(json: true, provider: nil, thresholdPercent: 12.5))
        #expect(try UsageCLICommand(arguments: ["status", "--threshold", "100"])
                == .status(json: false, provider: nil, thresholdPercent: 100))
        for invalid in [
            ["status", "--threshold"], ["status", "--threshold", "20", "--threshold", "30"]
        ] + ["0", "-1", "100.1", "nan", "inf", "-inf", "hello"].map({ ["status", "--threshold", $0] }) {
            #expect(throws: UsageCLIError.invalidArguments) { try UsageCLICommand(arguments: invalid) }
        }
    }

    @Test func customThresholdReachesJSONAlertsAndPlainResetTimeWithoutChangingTheSnapshot() async throws {
        let snapshot = UsageSnapshot(services: [ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 75,
                        resetsAt: now.addingTimeInterval(7_200), period: .fiveHours),
            UsageWindow(id: "secondary", title: "Week", usedPercent: 65, resetsAt: nil, period: .week)
        ], updatedAt: now)])
        let defaultResult = await UsageCLI.run(arguments: ["status", "--json"], now: now, fetch: { snapshot })
        #expect(defaultResult.exitCode == 0)
        let defaultReport = try object(defaultResult.output)
        #expect(defaultReport["thresholdPercent"] as? Double == 20)
        #expect((defaultReport["alerts"] as? [[String: Any]])?.isEmpty == true)
        let custom = await UsageCLI.run(arguments: ["status", "--json", "--threshold", "30"], now: now, fetch: { snapshot })
        #expect(custom.exitCode == 0)
        let customReport = try object(custom.output)
        #expect(customReport["thresholdPercent"] as? Double == 30)
        let alerts = try #require(customReport["alerts"] as? [[String: Any]])
        #expect(alerts.count == 1)
        #expect(alerts[0]["remainingPercent"] as? Double == 25)
        #expect(alerts[0]["secondsUntilReset"] as? Double == 7_200)
        let plain = await UsageCLI.run(arguments: ["status", "--threshold", "40"], now: now, fetch: { snapshot })
        #expect(plain.exitCode == 0)
        #expect(plain.output.contains("attention: codex 5 hours 25.0% left; reset in 2.0h"))
        #expect(plain.output.contains("attention: codex Week 35.0% left; reset in unknown"))
    }

    @Test func disabledStatusIsSuccessfulAndJSONUsesTheStableReportSchema() async throws {
        let result = await UsageCLI.run(arguments: ["status", "--provider", "claude", "--json"], now: now,
                                        fetch: { .empty })
        #expect(result.exitCode == 0)
        let report = try object(result.output)
        #expect(report["schemaVersion"] as? Int == 1)
        #expect(report["generatedAt"] as? String == "2027-01-15T08:00:00Z")
        #expect(report["pollIntervalSeconds"] as? Int == 300)
        #expect(report["maxAgeSeconds"] as? Int == 1_200)
        let services = try #require(report["services"] as? [[String: Any]])
        #expect(services.count == 1)
        #expect(services[0]["provider"] as? String == "claude")
        #expect(services[0]["state"] as? String == "disabled")
        #expect(services[0]["limitingRemainingPercent"] is NSNull)
        #expect(services[0]["observedAt"] is NSNull)
    }

    @Test func plainStatusShowsThePeriodAndAgeWithoutPresentingStaleQuotaAsCurrent() async {
        let snapshot = UsageSnapshot(services: [ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 20,
                        resetsAt: now.addingTimeInterval(600), period: .fiveHours)
        ], updatedAt: now.addingTimeInterval(-1_201))])
        let result = await UsageCLI.run(arguments: ["status", "--provider", "codex"], now: now, fetch: { snapshot })
        #expect(result.exitCode == 0)
        #expect(result.output.contains("stale"))
        #expect(result.output.contains("1201s old"))
        #expect(result.output.contains("5 hours: —"))
        #expect(!result.output.contains("80.0%"))
    }

    @Test func failureOutputContainsOnlyFixedCodesWithoutRawErrorsOrPaths() async throws {
        let result = await UsageCLI.run(arguments: ["status", "--json"], fetch: {
            throw NSError(domain: "synthetic-private-domain", code: 42,
                          userInfo: [NSLocalizedDescriptionKey: "/synthetic/private/profile"])
        })
        #expect(result.exitCode == 1)
        let failure = try object(result.output)
        #expect(Set(failure.keys) == ["schemaVersion", "error"])
        #expect(failure["error"] as? String == "appUnavailable")
        #expect(!result.output.contains("synthetic"))
        let invalid = await UsageCLI.run(arguments: ["status", "--json"], fetch: { throw UsageCLIError.invalidResponse })
        #expect(invalid.exitCode == 1)
        #expect(try object(invalid.output)["error"] as? String == "invalidResponse")
    }

    @Test func bridgeReadsOnlyItsFixedGETEndpointWithoutSessionHeaders() async throws {
        let data = try JSONEncoder().encode(UsageSnapshot.empty)
        FixtureProtocol.state.install(.response(status: 200, data: data, headers: [:]))
        let configuration = fixtureConfiguration()
        configuration.httpAdditionalHeaders = ["Authorization": "synthetic-private", "Cookie": "synthetic-private"]
        #expect(try await UsageBridgeClient.load(configuration: configuration) == .empty)
        let requests = FixtureProtocol.state.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url == UsageSnapshot.bridgeURL)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "X-Usage-Rings-Widget") == "1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Origin") == nil)
        #expect(!request.httpShouldHandleCookies)
    }

    @Test func sharedBridgeAcceptsExactlySixtyFourKiBWithWidgetTimeoutsAndNoSessionState() async throws {
        var data = try JSONEncoder().encode(UsageSnapshot.empty)
        data.append(Data(repeating: 32, count: 65_536 - data.count))
        FixtureProtocol.state.install(.response(status: 200, data: data, headers: [:]))
        let configuration = fixtureConfiguration()
        configuration.httpAdditionalHeaders = ["Authorization": "synthetic-private", "Cookie": "synthetic-private"]
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 9]
        configuration.urlCache = URLCache(memoryCapacity: 1_024, diskCapacity: 0, diskPath: nil)
        #expect(try await UsageSnapshotBridge.load(configuration: configuration, requestTimeout: 3, resourceTimeout: 4) == .empty)
        #expect(configuration.timeoutIntervalForRequest == 3)
        #expect(configuration.timeoutIntervalForResource == 4)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpAdditionalHeaders == nil)
        #expect(configuration.connectionProxyDictionary?.isEmpty == true)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        let request = try #require(FixtureProtocol.state.requests.first)
        #expect(request.timeoutInterval == 3)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func sharedProviderSessionKeepsExplicitCredentialsAndProxyWithProviderTimeouts() async throws {
        FixtureProtocol.state.install(.response(status: 200, data: Data(), headers: [:]))
        let configuration = fixtureConfiguration()
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 9]
        let session = UsageHTTPSession.make(configuration: configuration, requestTimeout: 20, resourceTimeout: 30)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://example.invalid/usage")!)
        request.setValue("synthetic-provider-cookie", forHTTPHeaderField: "Cookie")
        request.setValue("Bearer synthetic-provider-token", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: request)
        let sent = try #require(FixtureProtocol.state.requests.first)
        #expect(sent.value(forHTTPHeaderField: "Cookie") == "synthetic-provider-cookie")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-provider-token")
        #expect(session.configuration.timeoutIntervalForRequest == 20)
        #expect(session.configuration.timeoutIntervalForResource == 30)
        #expect(session.configuration.connectionProxyDictionary?["HTTPEnable"] as? Int == 1)
        #expect(session.configuration.connectionProxyDictionary?["HTTPProxy"] as? String == "127.0.0.1")
    }

    @Test func bridgeRejectsBadStatusMalformedJSONAndOversizedResponses() async {
        for response in [
            FixtureProtocol.Response.response(status: 403, data: Data(), headers: [:]),
            .nonHTTP,
            .response(status: 200, data: Data("synthetic-invalid-json".utf8), headers: [:]),
            .response(status: 200, data: Data(repeating: 32, count: 65_537), headers: [:]),
            .response(status: 200, data: Data(), headers: ["Content-Length": "65537"])
        ] {
            FixtureProtocol.state.install(response)
            await #expect(throws: UsageCLIError.invalidResponse) {
                try await UsageBridgeClient.load(configuration: fixtureConfiguration())
            }
        }
    }

    @Test func bridgeNeverFollowsRedirectsAwayFromTheApp() async {
        FixtureProtocol.state.install(.redirect)
        await #expect(throws: (any Error).self) {
            try await UsageBridgeClient.load(configuration: fixtureConfiguration())
        }
        #expect(FixtureProtocol.state.requests.count == 1)
        #expect(FixtureProtocol.state.requests.first?.url == UsageSnapshot.bridgeURL)
    }

    @Test func connectionFailuresTimeoutsAndCancellationAreReportedAsAppUnavailable() async {
        for code in [URLError.Code.cannotConnectToHost, .timedOut, .cancelled] {
            FixtureProtocol.state.install(.failure(code))
            await #expect(throws: UsageSnapshotBridge.Failure.unavailable) {
                try await UsageSnapshotBridge.load(configuration: fixtureConfiguration())
            }
            await #expect(throws: UsageCLIError.appUnavailable) {
                try await UsageBridgeClient.load(configuration: fixtureConfiguration())
            }
        }
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func fixtureConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return configuration
    }

    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        enum Response {
            case response(status: Int, data: Data, headers: [String: String])
            case redirect, nonHTTP, failure(URLError.Code)
        }

        final class State: @unchecked Sendable {
            private let lock = NSLock()
            private var response = Response.failure(.cannotConnectToHost)
            private var recorded: [URLRequest] = []

            func install(_ response: Response) {
                lock.lock()
                defer { lock.unlock() }
                self.response = response
                recorded = []
            }

            var requests: [URLRequest] {
                lock.lock()
                defer { lock.unlock() }
                return recorded
            }

            func capture(_ request: URLRequest) -> Response {
                lock.lock()
                defer { lock.unlock() }
                recorded.append(request)
                return response
            }
        }

        static let state = State()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            switch Self.state.capture(request) {
            case .response(let status, let data, let headers): respond(status: status, data: data, headers: headers)
            case .failure(let code):
                client?.urlProtocol(self, didFailWithError: URLError(code))
            case .nonHTTP:
                let response = URLResponse(url: request.url!, mimeType: "application/json", expectedContentLength: 0,
                                           textEncodingName: nil)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            case .redirect:
                if request.url == UsageSnapshot.bridgeURL {
                    let destination = URL(string: "https://example.invalid/usage")!
                    let response = HTTPURLResponse(url: UsageSnapshot.bridgeURL, statusCode: 302,
                                                   httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
                    client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: response)
                    client?.urlProtocolDidFinishLoading(self)
                } else {
                    respond(status: 200, data: Data("{}".utf8), headers: [:])
                }
            }
        }

        private func respond(status: Int, data: Data, headers: [String: String]) {
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for offset in stride(from: 0, to: data.count, by: 8_192) {
                client?.urlProtocol(self, didLoad: data.subdata(in: offset..<min(offset + 8_192, data.count)))
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
