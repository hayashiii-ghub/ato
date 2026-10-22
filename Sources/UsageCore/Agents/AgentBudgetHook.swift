import CoreFoundation
import CryptoKit
import Darwin
import Foundation

public enum AgentBudgetHookClient: String, CaseIterable, Sendable {
    case codex, claude, cursor, antigravity

    public var provider: String { self == .antigravity ? "gemini" : rawValue }

    var sessionField: String {
        switch self {
        case .codex, .claude: "session_id"
        case .cursor: "conversation_id"
        case .antigravity: "conversationId"
        }
    }

    var event: String {
        switch self {
        case .codex, .claude: "PostToolUse"
        case .cursor: "postToolUse"
        case .antigravity: "PreInvocation"
        }
    }
}

public struct AgentBudgetHookOptions: Sendable {
    public let client: AgentBudgetHookClient
    public let cli: URL
    public let stateDirectory: URL

    public init(client: AgentBudgetHookClient, cli: URL,
                stateDirectory: URL = AgentBudgetHook.defaultStateDirectory) {
        self.client = client
        self.cli = cli
        self.stateDirectory = stateDirectory
    }

    public static func parse(arguments: [String]) -> Self? {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard ["--client", "--cli", "--state-dir"].contains(key), values[key] == nil,
                  index + 1 < arguments.count else { return nil }
            values[key] = arguments[index + 1]
            index += 2
        }
        guard let name = values["--client"], let client = AgentBudgetHookClient(rawValue: name),
              let cli = values["--cli"], AgentBudgetHook.absolutePath(cli) else { return nil }
        let state = values["--state-dir"] ?? AgentBudgetHook.defaultStateDirectory.path
        guard AgentBudgetHook.absolutePath(state) else { return nil }
        return Self(client: client, cli: URL(fileURLWithPath: cli), stateDirectory: URL(fileURLWithPath: state))
    }
}

/// A passive hook: it reads the existing CLI snapshot and never starts or configures providers.
public enum AgentBudgetHook {
    public static let maximumInputBytes = 65_536
    public static let maximumOutputBytes = 8_192
    static let maximumStateBytes = 1_048_576
    static let maximumSessions = 128
    static let maximumWindows = 8
    static let maximumBoundaries = 8
    static let checkInterval: TimeInterval = 60
    static let retention: TimeInterval = 7 * 24 * 60 * 60
    static let maximumAge: TimeInterval = 1_200
    static let quiet = Data("{}".utf8)

    /// Native state is deliberately separate from the optional Python prototype's cache.
    public static var defaultStateDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ato-budget-native-hooks-\(getuid())")
    }

    public static func readStandardInput() -> Data? {
        AgentBudgetHookProcess.readInput(descriptor: STDIN_FILENO, limit: maximumInputBytes, timeout: 1)
    }

    public static func run(options: AgentBudgetHookOptions, payload: Data) -> Data {
        run(options: options, payload: payload, now: Date.init) { cli, client in
            AgentBudgetHookProcess.report(cli: cli, provider: client.provider)
        }
    }

    static func run(options: AgentBudgetHookOptions, payload: Data, now: () -> Date,
                    readReport: (URL, AgentBudgetHookClient) -> Data?) -> Data {
        guard let key = sessionKey(client: options.client, payload: payload),
              absolutePath(options.cli.path), absolutePath(options.stateDirectory.path),
              AgentBudgetHookProcess.isExecutableFile(options.cli) else { return quiet }
        do {
            let store = try AgentBudgetHookState(directory: options.stateDirectory)
            let checkedAt = now().timeIntervalSince1970
            guard checkedAt.isFinite else { return quiet }
            var sessions = try store.load().filter { key, value in
                validHash(key) && value.checkedAt.isFinite
                    && (-60..<retention).contains(checkedAt - value.checkedAt)
            }
            let previous = sessions[key]
            if let previous, checkedAt - previous.checkedAt < checkInterval { return quiet }

            let report = readReport(options.cli, options.client)
            let observedNow = now().timeIntervalSince1970
            guard observedNow.isFinite else { return quiet }
            let snapshot = report.flatMap { verifiedReport($0, client: options.client, now: observedNow) }
            let update = advance(previous: previous, snapshot: snapshot, client: options.client,
                                 checkedAt: checkedAt, now: observedNow)
            sessions[key] = update.session
            sessions = Dictionary(uniqueKeysWithValues: sessions.sorted {
                $0.value.checkedAt == $1.value.checkedAt ? $0.key < $1.key : $0.value.checkedAt > $1.value.checkedAt
            }.prefix(maximumSessions).map { ($0.key, $0.value) })
            // A notice is delivered only after its deduplication state was committed successfully.
            try store.save(sessions)
            guard !update.notices.isEmpty else { return quiet }
            let object = output(client: options.client, notice: update.notices.joined(separator: "\n"))
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return data.count <= maximumOutputBytes ? data : quiet
        } catch {
            // Invalid, locked, or unavailable state is unknown. Hooks never block the agent's work.
            return quiet
        }
    }

    static func sessionKey(client: AgentBudgetHookClient, payload: Data) -> String? {
        guard let object = object(payload, limit: maximumInputBytes),
              let session = object[client.sessionField] as? String,
              (1...512).contains(session.unicodeScalars.count) else { return nil }
        let event = object["hook_event_name"] ?? object["hookEventName"]
        if let event {
            guard event as? String == client.event else { return nil }
        } else if client != .antigravity {
            return nil
        }
        return hash(client.rawValue + "\0" + session)
    }

    struct Alert {
        let id: String
        let remaining: Double
        let observed: TimeInterval
        let reset: TimeInterval?
        let stage: Int
        let period: String?
    }

    struct Snapshot {
        let observed: TimeInterval?
        let alerts: [Alert]
    }

    static func verifiedReport(_ data: Data, client: AgentBudgetHookClient, now: TimeInterval) -> Snapshot? {
        guard let report = object(data, limit: maximumInputBytes), number(report["schemaVersion"]) == 1,
              let schema = report["schemaVersion"] as? NSNumber,
              !["f", "d"].contains(String(cString: schema.objCType)),
              let generated = timestamp(report["generatedAt"]), (-60..<maximumAge).contains(now - generated),
              let services = report["services"] as? [Any], let alerts = report["alerts"] as? [Any] else { return nil }
        var windows: [String: ([String: Any], TimeInterval)] = [:]
        var newest: TimeInterval?
        for value in services {
            guard let service = value as? [String: Any], service["provider"] as? String == client.provider,
                  ["ready", "partial"].contains(service["state"] as? String ?? ""),
                  let observed = timestamp(service["observedAt"]), (-60..<maximumAge).contains(now - observed),
                  let entries = service["windows"] as? [Any] else { continue }
            newest = max(newest ?? observed, observed)
            for entry in entries {
                guard let window = entry as? [String: Any], let id = window["id"] as? String,
                      (1...128).contains(id.unicodeScalars.count) else { continue }
                windows[id] = (window, observed)
            }
        }
        var valid: [String: Alert] = [:]
        for value in alerts {
            guard let alert = value as? [String: Any], alert["provider"] as? String == client.provider,
                  let id = alert["windowId"] as? String, let (window, observed) = windows[id],
                  boolean(window["isMain"]) == true, window["state"] as? String == "ready",
                  let remaining = number(alert["remainingPercent"]), (0..<20).contains(remaining),
                  number(window["remainingPercent"]) == remaining,
                  timestamp(alert["observedAt"]) == observed,
                  let expiry = timestamp(window["validUntil"]), expiry > now else { continue }
            let resetValue = alert["resetsAt"]
            let reset = timestamp(resetValue)
            guard sameReset(window["resetsAt"], resetValue),
                  resetValue == nil || resetValue is NSNull || (reset != nil && reset! > now) else { continue }
            let stage = remaining < 5 ? 5 : remaining < 10 ? 10 : 20
            valid[id] = Alert(id: id, remaining: remaining, observed: observed, reset: reset,
                              stage: stage, period: window["period"] as? String)
        }
        return Snapshot(observed: newest, alerts: valid.keys.sorted().prefix(maximumWindows).compactMap { valid[$0] })
    }

    static func advance(previous: AgentBudgetHookSession?, snapshot: Snapshot?, client: AgentBudgetHookClient,
                        checkedAt: TimeInterval, now: TimeInterval) -> (session: AgentBudgetHookSession, notices: [String]) {
        let newest = [previous?.observed, snapshot?.observed].compactMap { $0 }.max()
        var current = AgentBudgetHookSession(checkedAt: checkedAt, observed: newest, windows: [:])
        var notices: [String] = []
        for alert in snapshot?.alerts ?? [] {
            let key = hash(alert.id)
            let old = previous?.windows[key]
            if newest.map({ $0 > alert.observed }) == true
                || previous?.observed.map({ $0 >= alert.observed }) == true
                || old.map({ $0.observed >= alert.observed }) == true { continue }
            var boundaries = old?.notices ?? []
            let existing = boundaries.first { $0.reset == alert.reset }?.stage
            let stage = min(existing ?? alert.stage, alert.stage)
            if existing == nil || alert.stage < existing! {
                notices.append(notice(alert, client: client, now: now))
            }
            boundaries.removeAll { $0.reset == alert.reset }
            boundaries.append(AgentBudgetHookBoundary(reset: alert.reset, stage: stage))
            current.windows[key] = AgentBudgetHookWindow(observed: alert.observed,
                                                         notices: Array(boundaries.suffix(maximumBoundaries)))
        }
        // A failed read, recovery, or missing alert must not erase previously noticed stages.
        for (key, value) in (previous?.windows ?? [:]).sorted(by: { $0.key < $1.key }) {
            if current.windows[key] == nil && current.windows.count < maximumWindows { current.windows[key] = value }
        }
        return (current, notices)
    }

    static func notice(_ alert: Alert, client: AgentBudgetHookClient, now: TimeInterval) -> String {
        let label: String
        switch client {
        case .codex: label = "Codex"
        case .claude: label = "Claude"
        case .cursor: label = "Cursor"
        case .antigravity: label = "Gemini (Antigravity)"
        }
        let periods = ["fiveHours": "5h", "week": "Week"]
        let known = ["primary": "Primary", "secondary": "Secondary", "five_hour": "5h", "seven_day": "Week",
                     "fiveHours": "5h", "week": "Week", "total": "Month"]
        let title = alert.period.flatMap { periods[$0] } ?? known[alert.id] ?? "window \(hash(alert.id).prefix(8))"
        let remaining = alert.remaining.rounded() == alert.remaining ? String(Int(alert.remaining)) : String(alert.remaining)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let observed = formatter.string(from: Date(timeIntervalSince1970: alert.observed))
        return "ato? / \(label) / \(title): \(remaining)% remaining; \(resetText(alert.reset, now: now)) (below \(alert.stage)%; observed \(observed))."
    }

    static func resetText(_ reset: TimeInterval?, now: TimeInterval) -> String {
        guard let reset else { return "reset unknown" }
        let value = max(0, ceil((reset - now) / 60))
        guard value.isFinite, value < Double(Int.max) else { return "reset unknown" }
        let minutes = Int(value)
        let days = minutes / 1_440, hours = (minutes % 1_440) / 60, rest = minutes % 60
        if days > 0 { return "reset in \(days)d \(hours)h" }
        return hours > 0 ? "reset in \(hours)h \(rest)m" : "reset in \(rest)m"
    }

    static func output(client: AgentBudgetHookClient, notice: String) -> [String: Any] {
        switch client {
        case .cursor: ["additional_context": notice]
        case .antigravity: ["injectSteps": [["ephemeralMessage": notice]]]
        case .codex, .claude: ["hookSpecificOutput": ["hookEventName": "PostToolUse", "additionalContext": notice]]
        }
    }

    static func object(_ data: Data, limit: Int) -> [String: Any]? {
        guard data.count <= limit, boundedJSONDepth(data),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return value as? [String: Any]
    }

    static func boundedJSONDepth(_ data: Data) -> Bool {
        var depth = 0, quoted = false, escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 91 || byte == 123 { depth += 1; if depth > 64 { return false } }
            else if byte == 93 || byte == 125 { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0 && !quoted
    }

    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    static func timestamp(_ value: Any?) -> TimeInterval? {
        guard let text = value as? String, text.utf8.count <= 64 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: text) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }()
        guard let value = date?.timeIntervalSince1970, value.isFinite else { return nil }
        return value
    }

    private static func sameReset(_ first: Any?, _ second: Any?) -> Bool {
        if (first == nil || first is NSNull) && (second == nil || second is NSNull) { return true }
        guard let first = first as? String, let second = second as? String else { return false }
        return first == second
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func validHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func absolutePath(_ value: String) -> Bool {
        value.hasPrefix("/") && value.utf8.count < Int(PATH_MAX) && !value.utf8.contains(0)
    }
}
