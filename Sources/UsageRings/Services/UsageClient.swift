import UsageCore
import Foundation

enum UsageClient {
    static func fetch(_ service: UsageService,
                      cursorToken: @Sendable () throws -> String = { try UsageCredentialReader.cursorToken() },
                      read: @Sendable (URLRequest) async throws -> Data = { try await readResponse($0) }) async -> ServiceUsage {
        do {
            switch service {
            case .codex:
                return await CodexAppServerClient.fetch()
            case .gemini:
                return await AntigravityUsageClient.fetch()
            case .cursor:
                let token = try cursorToken()
                async let plan = read(dashboardRequest(.planInfo, token: token))
                async let usage = read(dashboardRequest(.currentPeriodUsage, token: token))
                let (planData, usageData) = try await (plan, usage)
                return try UsageResponseParser.cursor(usageData, planInfo: planData)
            case .claude:
                return ClaudeStatuslineFile.read()?.usage ?? ServiceUsage(service: .claude, state: .signInRequired)
            case .grokBot:
                let request = dashboardRequest(.sandUsageStatus, token: try cursorToken())
                return try UsageResponseParser.grokBot(await read(request))
            }
        } catch CursorSafeStorage.Failure.permissionRequired {
            return ServiceUsage(service: service, state: .setupRequired)
        } catch UsageReadError.missingSession, UsageReadError.expiredSession {
            return ServiceUsage(service: service, state: .signInRequired)
        } catch {
            return ServiceUsage(service: service, state: .unavailable)
        }
    }

    private enum DashboardMethod: String {
        case planInfo = "GetPlanInfo"
        case currentPeriodUsage = "GetCurrentPeriodUsage"
        case sandUsageStatus = "GetSandUsageStatus"
    }

    private static func dashboardRequest(_ method: DashboardMethod, token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method.rawValue)")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func readResponse(_ input: URLRequest) async throws -> Data {
        let session = UsageHTTPSession.make(requestTimeout: 20, resourceTimeout: 30)
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
