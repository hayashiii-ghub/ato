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
            let request: URLRequest
            switch service {
            case .codex:
                return await CodexAppServerClient.fetch()
            case .gemini:
                return await AntigravityUsageClient.fetch()
            case .cursor:
                var value = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
                value.setValue(try UsageCredentialReader.cursorCookie(), forHTTPHeaderField: "Cookie")
                value.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
                request = value
            case .claude:
                return ClaudeStatuslineFile.read()?.usage ?? ServiceUsage(service: .claude, state: .signInRequired)
            case .grokBot:
                var value = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!)
                value.httpMethod = "POST"
                value.httpBody = Data("{}".utf8)
                value.setValue("application/json", forHTTPHeaderField: "Content-Type")
                value.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
                value.setValue("Bearer \(try UsageCredentialReader.cursorToken())", forHTTPHeaderField: "Authorization")
                request = value
            }
            let data = try await read(request)
            switch service {
            case .codex, .gemini: throw UsageReadError.invalidResponse
            case .cursor: return try UsageResponseParser.cursor(data)
            case .claude: throw UsageReadError.invalidResponse
            case .grokBot: return try UsageResponseParser.grokBot(data)
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
