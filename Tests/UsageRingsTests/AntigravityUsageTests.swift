import Darwin
import Foundation
import Testing
import UsageCore
@testable import UsageRings

struct AntigravityUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func geminiQuotaUsesTheMostConstrainedWindowAndDropsPrivateMetadata() throws {
        let usage = try AntigravityUsageParser.parse(payload(), now: now)
        #expect(usage.service == .gemini)
        #expect(usage.windows.count == 2)
        #expect(usage.headline?.title == "Week")
        #expect(abs((usage.remainingPercent(at: now) ?? 0) - 45.6) < 0.000_001)
        #expect(usage.windows.allSatisfy { $0.id.hasPrefix("gemini-") && $0.resetsAt != nil })
        let serialized = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
        #expect(!serialized.contains("synthetic-private"))
        #expect(!serialized.contains("3p-"))
        #expect(!serialized.contains("credits"))
        #expect(!serialized.contains("conversation"))
    }

    @Test func passedResetMakesEvenAFullBucketUnknown() throws {
        let expired = #"{"id":"gemini-5h","window":"5h","remaining_fraction":1,"reset_time":"2027-01-15T07:59:59Z"}"#
        let usage = try AntigravityUsageParser.parse(payload(buckets: expired), now: now)
        #expect(usage.remainingPercent(at: now) == nil)
    }

    @Test func missingDisabledMalformedAndThirdPartyQuotasNeverBecomeFullGemini() throws {
        for bucket in [
            #"{"id":"gemini-weekly","window":"weekly"}"#,
            #"{"id":"gemini-weekly","window":"weekly","remaining_fraction":-0.1,"reset_time":"2027-02-01T12:00:00Z"}"#,
            #"{"id":"gemini-weekly","window":"weekly","remaining_fraction":1.1,"reset_time":"2027-02-01T12:00:00Z"}"#,
            #"{"id":"gemini-weekly","window":"weekly","remaining_fraction":true,"reset_time":"2027-02-01T12:00:00Z"}"#,
            #"{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.5,"reset_time":"invalid"}"#,
            #"{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.5}"#,
            #"{"id":"gemini-unknown","window":"unknown","remaining_fraction":1,"reset_time":"2027-02-01T12:00:00Z"}"#,
            #"{"id":"3p-weekly","window":"weekly","remaining_fraction":0.5,"reset_time":"2027-02-01T12:00:00Z"}"#
        ] {
            #expect(throws: (any Error).self) { try AntigravityUsageParser.parse(payload(buckets: bucket), now: now) }
        }
        #expect(throws: (any Error).self) { try AntigravityUsageParser.parse(Data("{}".utf8)) }
        #expect(throws: (any Error).self) { try AntigravityUsageParser.parse(payload(group: "Claude and GPT models")) }
    }

    @Test func activeWeeklyQuotaSurvivesAnExplicitlyDisabledFiveHourBucket() throws {
        let buckets = #"{"id":"gemini-weekly","window":"weekly","remaining_fraction":0,"reset_time":"2027-02-01T12:00:00.125Z"},{"id":"gemini-5h","window":"5h"}"#
        let usage = try AntigravityUsageParser.parse(payload(buckets: buckets), now: now)
        #expect(usage.windows.count == 1)
        #expect(usage.remainingPercent(at: now) == 0)
        #expect(usage.headline?.resetsAt == Date(timeIntervalSince1970: 1_801_483_200.125))
    }

    @Test func rejectsAnAgentTurnAndAmbiguousOrWrongCommandResults() throws {
        let valid = String(decoding: payload(), as: UTF8.self)
        for invalid in [
            valid.replacingOccurrences(of: #""status":"SUCCESS""#, with: #""status":"ERROR""#),
            valid.replacingOccurrences(of: #""num_turns":0"#, with: #""num_turns":1"#),
            valid.replacingOccurrences(of: #""total_tokens":0"#, with: #""total_tokens":2"#),
            valid.replacingOccurrences(of: #""name":"usage""#, with: #""name":"credits""#)
        ] {
            #expect(throws: (any Error).self) { try AntigravityUsageParser.parse(Data(invalid.utf8)) }
        }
        let bucket = #"{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.5,"reset_time":"2027-02-01T12:00:00Z"}"#
        #expect(throws: (any Error).self) { try AntigravityUsageParser.parse(payload(buckets: "\(bucket),\(bucket)")) }
        #expect(try AntigravityUsageParser.parse(Data(valid.replacingOccurrences(of: #""name":"usage""#, with: #""name":"/usage""#).utf8)).service == .gemini)
    }

    @Test func fixedCLILocationsAndVersionGateCannotStartOldAgents() {
        let home = URL(fileURLWithPath: "/synthetic/home")
        var checked: [String] = []
        let executable = AntigravityUsageClient.executable(home: home) {
            checked.append($0)
            return $0 == "/synthetic/home/.local/bin/agy"
        }
        #expect(executable?.path == "/synthetic/home/.local/bin/agy")
        #expect(checked == ["/opt/homebrew/bin/agy", "/usr/local/bin/agy", "/synthetic/home/.local/bin/agy"])
        for value in ["1.1.11\n", "1.3.4", "2.0.0"] {
            #expect(AntigravityUsageClient.supportedVersion(Data(value.utf8)))
        }
        for value in ["1.1.10", "1.0.99", "0.99.0", "1.3.4-beta", "1.3.4\nprivate", "1.99999999999999999999999.0"] {
            #expect(!AntigravityUsageClient.supportedVersion(Data(value.utf8)))
        }
    }

    @Test func versionProbeRejectsUnsupportedCLIWithoutStartingUsage() async throws {
        let fixture = try Fixture("normal", version: "1.1.10")
        defer { fixture.remove() }
        await #expect(throws: AntigravityUsageError.unsupportedCLI) { try await fixture.read() }
        #expect(!FileManager.default.fileExists(atPath: fixture.record.path))
    }

    @Test func boundedNativeUsageHandlesFragmentedOutputWithoutAgentEnvironment() async throws {
        let fixture = try Fixture("fragmented")
        defer { fixture.remove() }
        let usage = try await fixture.read()
        #expect(usage.service == .gemini && usage.windows.count == 1)
        #expect(try fixture.processIsGone())
        #expect(try fixture.temporaryCWDIsGone())
    }

    @Test func oversizedAndFailedNativeOutputNeverBecomesUsage() async throws {
        for scenario in ["oversized", "nonzero", "invalid"] {
            let fixture = try Fixture(scenario)
            defer { fixture.remove() }
            await #expect(throws: (any Error).self) { try await fixture.read() }
            #expect(try fixture.processIsGone())
            #expect(try fixture.temporaryCWDIsGone())
        }
    }

    @Test func timeoutStopsTheOwnedProcessAndDescendantBeforeReturning() async throws {
        let fixture = try Fixture("hangWithChild")
        defer { fixture.remove() }
        await #expect(throws: AntigravityUsageError.timedOut) { try await fixture.read(timeout: 0.3) }
        #expect(try fixture.processIsGone())
        #expect(try fixture.temporaryCWDIsGone())
        let child = try #require(try fixture.childPID())
        for _ in 0..<100 where kill(child, 0) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(kill(child, 0) == -1 && errno == ESRCH)
    }

    @Test func cancelledUsageStopsAndReapsItsChild() async throws {
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

    @Test func anAlreadyCancelledReadCannotLaunchAChild() async throws {
        let fixture = try Fixture("normal")
        defer { fixture.remove() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.read()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: fixture.record.path))
    }

    private func payload(buckets: String = #"{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.456,"reset_time":"2027-02-01T12:00:00Z"},{"id":"gemini-5h","window":"5h","remaining_fraction":0.9,"reset_time":"2027-02-01T12:00:00Z"}"#,
                         group: String = "Gemini Models") -> Data {
        Data("""
        {"status":"SUCCESS","num_turns":0,"conversation_id":"synthetic-private-conversation","email":"synthetic-private@example.com", "usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"credits":"synthetic-private-credit","description":"synthetic-private-project","groups":[{"name":"\(group)","buckets":[\(buckets)]},{"name":"Claude and GPT models","buckets":[{"id":"3p-weekly","window":"weekly","remaining_fraction":0.01,"reset_time":"2027-02-01T12:00:00Z"}]}]}}}
        """.utf8)
    }

    private struct Fixture {
        let folder: URL
        let script: URL
        let record: URL
        let scenario: String
        let version: String

        init(_ scenario: String, version: String = "1.3.4") throws {
            self.scenario = scenario
            self.version = version
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("usage-rings-fake-agy-\(UUID().uuidString)")
            script = folder.appendingPathComponent("cli.py")
            record = folder.appendingPathComponent("record.json")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try Self.program.write(to: script, atomically: true, encoding: .utf8)
        }

        func read(timeout: TimeInterval = 3) async throws -> ServiceUsage {
            try await AntigravityUsageClient.read(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [script.path, scenario, record.path] + AntigravityUsageClient.usageArguments,
                versionArguments: [script.path, "version", version], timeout: timeout)
        }

        func remove() { try? FileManager.default.removeItem(at: folder) }
        func recorded() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as! [String: Any] }
        func processIsGone() throws -> Bool {
            let pid = try (recorded()["pid"] as! NSNumber).int32Value
            return kill(pid, 0) == -1 && errno == ESRCH
        }
        func temporaryCWDIsGone() throws -> Bool { try !FileManager.default.fileExists(atPath: recorded()["cwd"] as! String) }
        func childPID() throws -> pid_t? { try (recorded()["child"] as? NSNumber)?.int32Value }

        private static let program = #"""
import json, os, signal, subprocess, sys, time
assert os.environ.get('AGY_CLI_DISABLE_AUTO_UPDATE') == 'true'
assert not any(k in os.environ for k in ('GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS', 'ANTIGRAVITY_CONVERSATION_ID'))
assert not sys.stdin.isatty() and not sys.stdout.isatty()
assert sys.stdin.read() == ''
assert os.listdir(os.getcwd()) == []
scenario = sys.argv[1]
if scenario == 'version':
    print(sys.argv[2], flush=True)
    sys.exit(0)
assert sys.argv[3:] == ['--print', '/usage', '--output-format', 'json', '--log-file', '/dev/null']
record = {'pid': os.getpid(), 'cwd': os.getcwd()}
signal.signal(signal.SIGTERM, signal.SIG_IGN)
if scenario == 'hangWithChild':
    child = subprocess.Popen(['/usr/bin/python3', '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])
    record['child'] = child.pid
with open(sys.argv[2], 'w') as f: json.dump(record, f)
if scenario in ('hang', 'hangWithChild'): time.sleep(60)
if scenario == 'oversized':
    print('x' * 70000, flush=True)
    time.sleep(60)
if scenario == 'invalid':
    print('synthetic-private-invalid-data', flush=True)
    sys.exit(0)
data = {'status': 'SUCCESS', 'num_turns': 0, 'usage': {key: 0 for key in ('input_tokens', 'output_tokens', 'thinking_tokens', 'cache_read_tokens', 'total_tokens')}, 'command': {'name': 'usage', 'data': {'groups': [{'name': 'Gemini Models', 'buckets': [{'id': 'gemini-weekly', 'window': 'weekly', 'remaining_fraction': 0.75, 'reset_time': '2027-02-01T12:00:00Z'}]}]}}}
text = json.dumps(data) + '\n'
sys.stderr.write('synthetic-private-stderr' * 50000)
sys.stderr.flush()
if scenario == 'fragmented':
    for i in range(0, len(text), 7):
        sys.stdout.write(text[i:i+7]); sys.stdout.flush()
else:
    print(text, end='', flush=True)
sys.exit(1 if scenario == 'nonzero' else 0)
"""#
    }
}
