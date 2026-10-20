import Foundation
import UsageCore

enum AntigravityUsageClient {
    static func fetch(from location: URL = AntigravityStatuslineFile.url()) async -> ServiceUsage {
        // Even agy --print can start browser sign-in. Poll only the passive helper cache.
        AntigravityStatuslineFile.read(from: location)?.usage
            ?? ServiceUsage(service: .gemini, state: .setupRequired)
    }
}
