import Foundation
import UsageCore

enum UsageBridgeClient {
    static func load(configuration: URLSessionConfiguration = .ephemeral) async throws -> UsageSnapshot {
        do {
            return try await UsageSnapshotBridge.load(configuration: configuration)
        } catch UsageSnapshotBridge.Failure.invalidResponse {
            throw UsageCLIError.invalidResponse
        } catch {
            throw UsageCLIError.appUnavailable
        }
    }
}
