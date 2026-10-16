import Foundation
import UsageCore

enum UsageDisplayText {
    static func status(_ usage: ServiceUsage, at date: Date) -> String? {
        if usage.isCurrent(at: date), usage.headline != nil { return nil }

        switch usage.state {
        case .disabled: return "Enable AI usage to connect."
        case .setupRequired:
            return usage.service == .gemini
                ? "Install or update Antigravity CLI (agy 1.1.11+), then refresh."
                : "Install or update the Codex CLI, then refresh."
        case .signInRequired:
            switch usage.service {
            case .codex: return "Sign in to the Codex CLI with ChatGPT, then refresh."
            case .cursor: return "Open Cursor and sign in, then refresh."
            case .claude: return "Use Claude Code, then refresh to receive usage."
            case .grokBot: return "Sign in to Cursor with your Grok account, then refresh."
            case .gemini: return "Sign in to Antigravity CLI, then refresh."
            }
        case .unavailable:
            return usage.service == .gemini
                ? "Could not read Antigravity CLI usage. Check /usage in agy, then refresh."
                : "Could not update. Try refreshing in a moment."
        case .ready:
            if let period = usage.preferredPeriod, usage.headline == nil {
                return "No reading for the selected \(period.title) window yet."
            }
            let windows = usage.preferredPeriod == nil ? usage.windows : [usage.headline].compactMap { $0 }
            if usage.hasFreshReading(at: date), windows.contains(where: { $0.resetsAt.map { $0 <= date } ?? false }) {
                return usage.service == .claude
                    ? "A usage window has reset. Use Claude Code, then refresh."
                    : "A usage window has reset. Refresh to receive a new reading."
            }
            return usage.service == .claude ? "Use Claude Code to update your usage." : "Waiting for a fresh reading."
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
