import Foundation
import UsageCore

enum UsageCLIError: String, Error {
    case invalidArguments, appUnavailable, invalidResponse
}

enum UsageCLICommand: Equatable {
    case help
    case status(json: Bool, provider: UsageService?, thresholdPercent: Double = 20)

    init(arguments: [String]) throws {
        guard let command = arguments.first else { self = .help; return }
        if arguments == ["--help"] || arguments == ["-h"] || arguments == ["status", "--help"] {
            self = .help
            return
        }
        guard command == "status" else { throw UsageCLIError.invalidArguments }
        var json = false
        var provider: UsageService?
        var thresholdPercent: Double?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                guard !json else { throw UsageCLIError.invalidArguments }
                json = true
            case "--provider":
                index += 1
                guard provider == nil, index < arguments.count else { throw UsageCLIError.invalidArguments }
                let identifier = arguments[index] == "grok" ? "grokBot" : arguments[index]
                guard let value = UsageService(rawValue: identifier) else { throw UsageCLIError.invalidArguments }
                provider = value
            case "--threshold":
                index += 1
                guard thresholdPercent == nil, index < arguments.count,
                      let value = Double(arguments[index]), value.isFinite, value > 0, value <= 100 else {
                    throw UsageCLIError.invalidArguments
                }
                thresholdPercent = value
            default: throw UsageCLIError.invalidArguments
            }
            index += 1
        }
        self = .status(json: json, provider: provider, thresholdPercent: thresholdPercent ?? 20)
    }
}

struct UsageCLIResult {
    let exitCode: Int32
    let output: String
}

enum UsageCLI {
    static let help = """
    Usage: usage-rings status [--json] [--provider codex|claude|cursor|grok|gemini] [--threshold PERCENT]
           usage-rings --help

    Reads the running ato? app's current usage snapshot.
    Low-remaining alerts default to 20%. Threshold must be above 0 and at most 100.
    """

    static func run(arguments: [String], now: Date? = nil,
                    fetch: @Sendable () async throws -> UsageSnapshot = { try await UsageBridgeClient.load() }) async -> UsageCLIResult {
        do {
            switch try UsageCLICommand(arguments: arguments) {
            case .help: return UsageCLIResult(exitCode: 0, output: help)
            case .status(let json, let provider, let thresholdPercent):
                let snapshot = try await fetch()
                let report = UsageStatusReport(snapshot: snapshot, provider: provider, now: now ?? Date(),
                                               thresholdPercent: thresholdPercent)
                guard json else { return UsageCLIResult(exitCode: 0, output: plain(report)) }
                guard let output = try? encodeJSON(report) else { throw UsageCLIError.invalidResponse }
                return UsageCLIResult(exitCode: 0, output: output)
            }
        } catch {
            let failure = error as? UsageCLIError ?? .appUnavailable
            return UsageCLIResult(exitCode: failure == .invalidArguments ? 2 : 1,
                                  output: errorOutput(failure, json: arguments.contains("--json")))
        }
    }

    private static func plain(_ report: UsageStatusReport) -> String {
        let statuses = report.services.map { service in
            let age = service.ageSeconds.map { String(format: "%.0fs old", $0) } ?? "no reading"
            var lines = ["\(service.provider): \(service.state) (\(age))"]
            for window in service.windows where window.isMain {
                let remaining = window.remainingPercent.map { String(format: "%.1f%% left", $0) } ?? "—"
                lines.append("  \(window.title): \(remaining) [\(window.state)]")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
        let attention = report.alerts.map { alert in
            "attention: \(alert.provider) \(alert.title) \(String(format: "%.1f%% left", alert.remainingPercent)); reset in \(resetInterval(alert.secondsUntilReset))"
        }
        return ([statuses] + attention).joined(separator: "\n")
    }

    private static func resetInterval(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "unknown" }
        if seconds < 60 { return "<1m" }
        if seconds < 3_600 { return String(format: "%.0fm", ceil(seconds / 60)) }
        if seconds < 86_400 { return String(format: "%.1fh", seconds / 3_600) }
        return String(format: "%.1fd", seconds / 86_400)
    }

    private static func errorOutput(_ failure: UsageCLIError, json: Bool) -> String {
        if json {
            return (try? encodeJSON(ErrorReport(error: failure.rawValue)))
                ?? #"{"error":"invalidResponse","schemaVersion":1}"#
        }
        switch failure {
        case .invalidArguments: return "usage-rings: invalid arguments\n\(help)"
        case .appUnavailable: return "usage-rings: app unavailable. Open ato? and try again."
        case .invalidResponse: return "usage-rings: invalid app response."
        }
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private struct ErrorReport: Encodable {
        let schemaVersion = 1
        let error: String
    }
}
