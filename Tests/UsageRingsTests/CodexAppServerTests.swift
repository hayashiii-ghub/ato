import Darwin
import Foundation
import Testing
import UsageCore
@testable import UsageRings

struct CodexAppServerTests {
    @Test func fixedCLILocationsDoNotSearchShellPATHOrAppBundles() {
        let home = URL(fileURLWithPath: "/synthetic/home")
        var checked: [String] = []
        let executable = CodexAppServerClient.executable(home: home) { path in
            checked.append(path)
            return path == "/synthetic/home/.local/bin/codex"
        }
        #expect(executable?.path == "/synthetic/home/.local/bin/codex")
        #expect(checked == ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/synthetic/home/.local/bin/codex"])
        #expect(CodexAppServerClient.executable(home: home, isExecutable: { _ in false }) == nil)
    }

    @Test func stableCLIVersionIsCheckedBeforeAccountServerLaunch() {
        for version in ["codex-cli 0.160.1\n", "codex-cli 0.161.0", "codex-cli 1.0.0"] {
            #expect(CodexAppServerClient.supportedVersion(Data(version.utf8)))
        }
        for version in ["codex-cli 0.159.0", "codex-cli 0.160.0", "codex-cli 0.160.1-alpha", "codex-cli 0.160.1\nprivate", "python 3.13", "codex-cli 0.99999999999999999999999999999999.0"] {
            #expect(!CodexAppServerClient.supportedVersion(Data(version.utf8)))
        }
    }

    @Test func childLaunchDisablesUnneededPluginAndRolloutWork() {
        let args = CodexAppServerClient.launchArguments
        for value in ["plugins", "apps", "local_thread_store_compression", "background_paginated_rollout_migration"] {
            let index = args.firstIndex(of: value)
            #expect(index != nil && index! > 0 && args[index! - 1] == "--disable")
        }
        #expect(args.contains("analytics.enabled=false"))
        #expect(args.contains("feedback.enabled=false"))
        #expect(args.contains("stdio://"))
    }

    @Test func generated01601SchemaParsesCodexBucketAndDropsAccountMetadata() throws {
        // Matches generate-json-schema from codex-cli 0.160.1: GetAccountRateLimitsResponse,
        // RateLimitSnapshot and RateLimitWindow. Unknown official metadata stays outside snapshots.
        let data = Data(#"{"accountId":"synthetic-private-account","rateLimits":{"limitId":"other","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":37,"windowDurationMins":300,"resetsAt":2100000000},"secondary":{"usedPercent":82,"windowDurationMins":10080,"resetsAt":2100000600},"credits":{"balance":"synthetic-private-credit","hasCredits":true,"unlimited":false}}}}"#.utf8)
        let usage = try UsageResponseParser.codex(data)
        #expect(usage.windows.count == 2)
        #expect(usage.headline?.title == "Week")
        #expect(usage.headline?.remainingPercent == 18)
        #expect(usage.windows.first?.resetsAt == Date(timeIntervalSince1970: 2_100_000_000))
        let sanitized = try String(decoding: JSONEncoder().encode(usage), as: UTF8.self)
        #expect(!sanitized.contains("synthetic-private"))
        #expect(!sanitized.contains("accountId"))
    }

    @Test func historicalDirectEndpointPayloadIsNoLongerAccepted() {
        #expect(throws: (any Error).self) {
            try UsageResponseParser.codex(Data(#"{"rate_limit":{"primary_window":{"used_percent":25}}}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try UsageResponseParser.codex(Data(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":25}}}"#.utf8))
        }
    }

    @Test func officialHandshakeHandlesFragmentedJSONAndDiscardsLargeStderr() async throws {
        let fixture = try Fixture("fragmented")
        defer { fixture.remove() }
        let usage = try await fixture.read()
        #expect(usage.state == .ready)
        #expect(usage.windows.first?.usedPercent == 37)
        #expect(try fixture.methods() == ["initialize", "initialized", "account/gatewayOAuth/read", "account/read", "account/rateLimits/read"])
        #expect(try fixture.processIsGone())
        #expect(try fixture.temporaryCWDIsGone())
    }

    @Test func sparseRateLimitNotificationTriggersAtMostOneFullRefetch() async throws {
        let fixture = try Fixture("notification")
        defer { fixture.remove() }
        let usage = try await fixture.read()
        #expect(usage.windows.first?.usedPercent == 61)
        #expect(try fixture.methods().filter { $0 == "account/rateLimits/read" }.count == 2)
    }

    @Test func monthlyCreditOnlyWorkspaceReadsThroughTheAppServerWithoutStoringAmounts() async throws {
        let fixture = try Fixture("monthlyCredit")
        defer { fixture.remove() }
        let usage = try await fixture.read()
        #expect(usage.state == .ready)
        #expect(usage.windows.map(\.id) == ["individual"])
        #expect(usage.remainingPercent(at: try #require(usage.updatedAt)) == 72)
        #expect(usage.headline?.resetsAt == Date(timeIntervalSince1970: 2_100_000_000))
        let sanitized = try String(decoding: JSONEncoder().encode(usage), as: UTF8.self)
        #expect(!sanitized.contains("synthetic-private"))
        #expect(try fixture.methods().filter { $0 == "account/rateLimits/read" }.count == 1)
    }

    @Test func missingChatGPTLoginDoesNotStartLoginOrRequestRateLimits() async throws {
        let fixture = try Fixture("signedOut")
        defer { fixture.remove() }
        await #expect(throws: CodexAppServerError.signInRequired) { try await fixture.read() }
        #expect(try !fixture.methods().contains("account/rateLimits/read"))
        #expect(try fixture.processIsGone())
    }

    @Test func lostSessionDuringRateReadRequiresSignInWithoutRawDiagnostic() async throws {
        let fixture = try Fixture("lostSession")
        defer { fixture.remove() }
        await #expect(throws: CodexAppServerError.signInRequired) { try await fixture.read() }
        #expect(try fixture.processIsGone())
    }

    @Test func expiredWorkspaceSessionRequiresSignInWithoutRawDiagnostic() async throws {
        let fixture = try Fixture("expiredSession")
        defer { fixture.remove() }
        await #expect(throws: CodexAppServerError.signInRequired) { try await fixture.read() }
        #expect(try !fixture.methods().contains("account/rateLimits/read"))
    }

    @Test func unsupportedVersionDoesNotStartAccountServer() async throws {
        let fixture = try Fixture("normal", version: "codex-cli 0.159.0")
        defer { fixture.remove() }
        await #expect(throws: CodexAppServerError.unsupportedCLI) { try await fixture.read() }
        #expect(!FileManager.default.fileExists(atPath: fixture.record.path))
    }

    @Test func gatewayCapabilityProbeBlocksOldOrMalformedServers() async throws {
        for scenario in ["unsupported", "gatewayNotReady"] {
            let fixture = try Fixture(scenario)
            defer { fixture.remove() }
            let error = scenario == "unsupported" ? CodexAppServerError.unsupportedCLI : .signInRequired
            await #expect(throws: error) { try await fixture.read() }
            #expect(try !fixture.methods().contains("account/read"))
        }
    }

    @Test func unsolicitedToolOrTokenRequestIsNeverExecuted() async throws {
        let fixture = try Fixture("serverRequest")
        defer { fixture.remove() }
        await #expect(throws: CodexAppServerError.requestFailed) { try await fixture.read() }
        #expect(try fixture.methods() == ["initialize"])
    }

    @Test func malformedWrongIDAndOversizedOutputFailWithoutLeakingRawErrors() async throws {
        for scenario in ["malformed", "wrongID", "booleanID", "nonStringMethod", "numericRequired", "numericRequiresAuth", "errorAndResult", "malformedError", "methodAndResult", "oversized", "manyNotifications"] {
            let fixture = try Fixture(scenario)
            defer { fixture.remove() }
            await #expect(throws: CodexAppServerError.invalidResponse) { try await fixture.read() }
            #expect(try fixture.processIsGone())
        }
        let fixture = try Fixture("error")
        defer { fixture.remove() }
        await #expect(throws: CodexAppServerError.requestFailed) { try await fixture.read() }
        #expect(CodexAppServerError.requestFailed.state == .unavailable)
        #expect(CodexAppServerError.cliUnavailable.state == .setupRequired)
    }

    @Test func timedOutStubbornChildAndDescendantAreKilled() async throws {
        let fixture = try Fixture("hangWithChild")
        defer { fixture.remove() }
        await #expect(throws: CodexAppServerError.timedOut) { try await fixture.read(timeout: 0.3) }
        #expect(try fixture.processIsGone())
        #expect(try fixture.temporaryCWDIsGone())
        // The orphan is reaped by the OS after its process group is killed.
        let child = try #require(try fixture.childPID())
        for _ in 0..<100 where kill(child, 0) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(kill(child, 0) == -1 && errno == ESRCH)
    }

    @Test func cancellationStopsAndReapsServerBeforeReturning() async throws {
        let fixture = try Fixture("hang")
        defer { fixture.remove() }
        let task = Task { try await fixture.read() }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: fixture.record.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: fixture.record.path))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.processIsGone())
        #expect(try fixture.temporaryCWDIsGone())
    }

    @Test func alreadyCancelledTaskNeverSpawnsChild() async throws {
        let fixture = try Fixture("normal")
        defer { fixture.remove() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.read()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: fixture.record.path))
    }

    private struct Fixture {
        let folder: URL
        let script: URL
        let record: URL
        let scenario: String
        let version: String

        init(_ scenario: String, version: String = "codex-cli 0.160.1") throws {
            self.scenario = scenario
            self.version = version
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("usage-rings-fake-\(UUID().uuidString)")
            script = folder.appendingPathComponent("server.py")
            record = folder.appendingPathComponent("record.json")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try Self.program.write(to: script, atomically: true, encoding: .utf8)
        }

        func read(timeout: TimeInterval = 3) async throws -> ServiceUsage {
            try await CodexAppServerClient.read(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                                                arguments: [script.path, scenario, record.path],
                                                versionArguments: [script.path, "version", version], timeout: timeout)
        }

        func remove() { try? FileManager.default.removeItem(at: folder) }
        func recorded() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as! [String: Any] }
        func methods() throws -> [String] { try recorded()["methods"] as! [String] }
        func processIsGone() throws -> Bool {
            let pid = try (recorded()["pid"] as! NSNumber).int32Value
            return kill(pid, 0) == -1 && errno == ESRCH
        }
        func temporaryCWDIsGone() throws -> Bool { try !FileManager.default.fileExists(atPath: recorded()["cwd"] as! String) }
        func childPID() throws -> pid_t? { try (recorded()["child"] as? NSNumber)?.int32Value }

        static let program = #"""
import json, os, signal, subprocess, sys, time
scenario = sys.argv[1]
if scenario == 'version':
    print(sys.argv[2], flush=True)
    sys.exit(0)
path = sys.argv[2]
record = {'pid': os.getpid(), 'cwd': os.getcwd(), 'methods': []}
assert os.environ.get('CODEX_INTERNAL_APP_SERVER_REMOTE_CONTROL_DISABLED') == '1'
assert 'OPENAI_API_KEY' not in os.environ and 'CODEX_API_KEY' not in os.environ
def save():
    with open(path, 'w') as f: json.dump(record, f)
save()
signal.signal(signal.SIGTERM, signal.SIG_IGN)
if scenario == 'hangWithChild':
    child = subprocess.Popen(['/usr/bin/python3', '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])
    record['child'] = child.pid
    save()
def send(value):
    text = json.dumps(value) + '\n'
    if scenario == 'fragmented':
        for i in range(0, len(text), 7):
            sys.stdout.write(text[i:i+7]); sys.stdout.flush()
    else:
        print(text, end='', flush=True)
reads = 0
initialize_result = {'userAgent': 'codex-cli/0.160.1', 'codexHome': 'synthetic-private-home', 'platformFamily': 'unix', 'platformOs': 'macos'}
for line in sys.stdin:
    msg = json.loads(line)
    method = msg['method']
    record['methods'].append(method)
    save()
    assert 'jsonrpc' not in msg
    if method == 'initialize':
        assert msg['params']['capabilities']['explicitGatewayOauth'] is True
        assert msg['params']['capabilities']['experimentalApi'] is False
        if scenario == 'hang' or scenario == 'hangWithChild': time.sleep(60)
        if scenario == 'malformed': print('private invalid data', flush=True); continue
        if scenario == 'oversized': print('x' * 70000, flush=True); continue
        if scenario == 'manyNotifications':
            for i in range(1000): send({'method': 'ignored', 'params': {'text': 'x' * 1000}})
            continue
        if scenario == 'serverRequest': send({'id': 'server-secret-id', 'method': 'item/tool/call', 'params': {}}); continue
        if scenario == 'error': send({'id': msg['id'], 'error': {'code': -32603, 'message': 'synthetic-private-token'}}); continue
        if scenario == 'wrongID': send({'id': 777, 'result': {}}); continue
        if scenario == 'booleanID': send({'id': True, 'result': initialize_result}); continue
        if scenario == 'nonStringMethod': send({'id': msg['id'], 'method': False, 'result': initialize_result}); continue
        if scenario == 'errorAndResult': send({'id': msg['id'], 'error': {'code': -32603}, 'result': {}}); continue
        if scenario == 'malformedError': send({'id': msg['id'], 'error': 'synthetic-private-error', 'result': {}}); continue
        if scenario == 'methodAndResult': send({'method': 'account/rateLimits/updated', 'result': {}}); continue
        sys.stderr.write('synthetic-private-stderr' * 50000); sys.stderr.flush()
        send({'id': msg['id'], 'result': initialize_result})
    elif method == 'initialized':
        assert record['methods'] == ['initialize', 'initialized']
    elif method == 'account/gatewayOAuth/read':
        if scenario == 'unsupported': send({'id': msg['id'], 'error': {'code': -32601, 'message': 'unknown method'}})
        else: send({'id': msg['id'], 'result': {'required': 0 if scenario == 'numericRequired' else scenario == 'gatewayNotReady', 'status': 'notReady' if scenario == 'gatewayNotReady' else None}})
    elif method == 'account/read':
        assert msg['params']['refreshToken'] is False
        if scenario == 'expiredSession':
            send({'id': msg['id'], 'error': {'code': -32603, 'message': 'workspace routing discovery unauthorized (401)'}})
            continue
        send({'id': msg['id'], 'result': {'requiresOpenaiAuth': 1 if scenario == 'numericRequiresAuth' else True, 'account': None if scenario == 'signedOut' else {'type': 'chatgpt', 'email': 'synthetic-private@example.com', 'planType': 'plus'}}})
    elif method == 'account/rateLimits/read':
        assert msg['params'] == {'excludeResetCreditDetails': True}
        if scenario == 'lostSession':
            send({'id': msg['id'], 'error': {'code': -32600, 'message': 'codex account authentication required to read rate limits'}})
            continue
        if scenario == 'monthlyCredit':
            credit = {'remainingPercent': 72, 'resetsAt': 2100000000, 'limit': 'synthetic-private-limit', 'used': 'synthetic-private-used'}
            limits = {'limitId': 'codex', 'planType': 'enterprise_cbp_usage_based', 'primary': None, 'secondary': None, 'individualLimit': credit}
            send({'id': msg['id'], 'result': {'rateLimits': limits}})
            continue
        reads += 1
        if scenario == 'notification': send({'method': 'account/rateLimits/updated', 'params': {'rateLimits': {'secondary': None}}})
        send({'id': msg['id'], 'result': {'rateLimits': {'limitId': 'codex', 'primary': {'usedPercent': 61 if reads == 2 else 37, 'windowDurationMins': 300, 'resetsAt': 2100000000}}}})
    else:
        raise Exception('Unexpected method')
"""#
    }
}
