import UsageCore
import Foundation

private final class UsageSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Session credentials are only ever sent to the original provider endpoint.
        completionHandler(nil)
    }
}

enum UsageClient {
    static func fetch(_ service: UsageService) async -> ServiceUsage {
        do {
            switch service {
            case .codex:
                return await CodexAppServerClient.fetch()
            case .gemini:
                return await AntigravityUsageClient.fetch()
            case .cursor:
                var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
                request.setValue(try UsageCredentialReader.cursorCookie(), forHTTPHeaderField: "Cookie")
                request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
                return try UsageResponseParser.cursor(await read(request))
            case .claude:
                return ClaudeStatuslineFile.read()?.usage ?? ServiceUsage(service: .claude, state: .signInRequired)
            case .grokBot:
                var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!)
                request.httpMethod = "POST"
                request.httpBody = Data("{}".utf8)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
                request.setValue("Bearer \(try UsageCredentialReader.cursorToken())", forHTTPHeaderField: "Authorization")
                return try UsageResponseParser.grokBot(await read(request))
            }
        } catch UsageReadError.missingSession, UsageReadError.expiredSession {
            return ServiceUsage(service: service, state: .signInRequired)
        } catch {
            return ServiceUsage(service: service, state: .unavailable)
        }
    }

    private static func read(_ input: URLRequest) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: UsageSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = input
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageRings/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageReadError.requestFailed }
        if http.statusCode == 401 || http.statusCode == 403 { throw UsageReadError.expiredSession }
        guard http.statusCode == 200, data.count <= 1_048_576 else { throw UsageReadError.requestFailed }
        return data
    }
}
