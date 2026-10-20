import Foundation
import UsageCore

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || arguments == ["--provider", "gemini"] else { exit(0) }
let gemini = !arguments.isEmpty
let provider = gemini ? "Gemini" : "Claude"

// Provider CLIs own stdin. Never save the original payload or log its contents.
do {
    var data = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
        data.append(chunk)
        guard data.count <= 1_048_576 else { exit(0) }
    }
    if gemini {
        let usage = try AntigravityUsageParser.parse(data)
        let cache = try AntigravityStatuslineFile.write(usage)
        let now = Date()
        let text = cache.usage.windows.compactMap { window in
            cache.usage.remainingPercent(for: window, at: now).map { "\(window.title): \(Int($0.rounded()))% left" }
        }.joined(separator: " · ")
        print(text.isEmpty ? provider : text)
    } else if let input = try ClaudeStatusline.parse(data) {
        try ClaudeStatuslineFile.write(input)
        print(input.usage.windows.map { "\($0.title): \(Int($0.remainingPercent.rounded()))% left" }.joined(separator: " · "))
    } else {
        print(provider)
    }
} catch {
    // Status-line failures must not interrupt the CLI or expose session data.
    print(provider)
}
