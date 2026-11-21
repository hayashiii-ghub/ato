import UsageCore
import Foundation

enum UsageClient {
    static func fetch(_ service: UsageService,
                      grokToken: @Sendable () throws -> String = { try GrokBuildUsageClient.token() },
                      antigravityToken: @Sendable () throws -> String = { try AntigravityUsageClient.token() },
                      read: @Sendable (URLRequest) async throws -> Data = { try await readResponse($0) }) async -> ServiceUsage {
        do {
            switch service {
            case .codex:
                return await CodexAppServerClient.fetch()
            case .gemini:
                return try await AntigravityUsageClient.fetch(token: antigravityToken, read: read)
            case .claude:
                return ClaudeStatuslineFile.read()?.usage ?? ServiceUsage(service: .claude, state: .signInRequired)
            case .grokBot:
                return try await GrokBuildUsageClient.fetch(token: grokToken, read: read)
            }
        } catch UsageReadError.keychainAccessRequired {
            return ServiceUsage(service: service, state: .setupRequired)
        } catch UsageReadError.missingSession, UsageReadError.expiredSession {
            return ServiceUsage(service: service, state: .signInRequired)
        } catch {
            return ServiceUsage(service: service, state: .unavailable)
        }
    }

    private static func readResponse(_ input: URLRequest) async throws -> Data {
        let session = UsageHTTPSession.make(requestTimeout: 20, resourceTimeout: 30)
        defer { session.invalidateAndCancel() }
        var request = input
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("UsageRings/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")", forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageReadError.requestFailed }
        if http.statusCode == 401 || http.statusCode == 403 { throw UsageReadError.expiredSession }
        guard http.statusCode == 200, data.count <= 1_048_576 else { throw UsageReadError.requestFailed }
        return data
    }
}
