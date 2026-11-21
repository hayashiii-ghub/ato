import Foundation
import UsageCore

enum UsageDisplayText {
    static func status(_ usage: ServiceUsage, at date: Date) -> String? {
        if usage.isFiveHourArcBlocked(at: date) { return "Weekly usage limit reached." }
        if usage.ringValues(at: date).hasReading { return nil }

        switch usage.state {
        case .disabled: return "Enable AI usage to connect."
        case .setupRequired:
            return usage.service == .gemini
                ? "Allow Antigravity sign-in access in ato? to update usage."
                : "Install or update the Codex CLI, then refresh."
        case .signInRequired:
            switch usage.service {
            case .codex: return "Sign in to the Codex CLI with ChatGPT, then refresh."
            case .claude: return "Use Claude Code in a terminal with the status-line helper, then refresh to receive usage."
            case .grokBot: return "Run grok login for your Grok Build subscription, then refresh."
            case .gemini: return "Sign in with Google in Antigravity or use agy to renew its session, then refresh."
            }
        case .unavailable:
            return "Could not update. Try refreshing in a moment."
        case .ready:
            if usage.hasFreshReading(at: date), usage.windows.contains(where: { $0.resetsAt.map { $0 <= date } ?? false }) {
                switch usage.service {
                case .claude: return "A usage window has reset. Use Claude Code in a terminal, then refresh."
                default: return "A usage window has reset. Refresh to receive a new reading."
                }
            }
            switch usage.service {
            case .claude: return "Use Claude Code in a terminal, then refresh to update your usage."
            default: return "Waiting for a fresh reading."
            }
        }
    }

    static func countdown(until reset: Date, from date: Date) -> String? {
        let seconds = reset.timeIntervalSince(date)
        guard seconds.isFinite, seconds > 0 else { return nil }
        if seconds < 60 { return "<1m" }
        guard let totalMinutes = Int(exactly: floor(seconds / 60)) else { return nil }
        let units = [
            (totalMinutes / 1440, "d"),
            (totalMinutes % 1440 / 60, "h"),
            (totalMinutes % 60, "m")
        ]
        return units.filter { $0.0 > 0 }.prefix(2).map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }
}
