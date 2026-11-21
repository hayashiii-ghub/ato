import Foundation
import UsageCore

enum GrokBuildUsageClient {
    private static let endpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private static let customAuthVariables = [
        "XAI_API_KEY", "GROK_AUTH", "GROK_OIDC_ISSUER", "GROK_OIDC_CLIENT_ID",
        "GROK_OAUTH2_ISSUER", "GROK_OAUTH2_CLIENT_ID", "GROK_OAUTH2_PRINCIPAL_TYPE",
        "GROK_OAUTH2_PRINCIPAL_ID", "GROK_AUTH_PROVIDER_COMMAND", "GROK_LOCAL_AUTH",
        "GROK_CLI_CHAT_PROXY_BASE_URL", "GROK_MODELS_BASE_URL", "GROK_CONFIG", "GROK_CONFIG_PATH"
    ]
    private static let authSections = #"(?m)^\s*(?:\[\[?\s*)?["']?(?:auth|grok_com_config|endpoints)["']?\s*[.\]=]"#

    static func fetch(token: @Sendable () throws -> String, read: @Sendable (URLRequest) async throws -> Data,
                      now: Date = Date()) async throws -> ServiceUsage {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        return try UsageResponseParser.grokBuild(await read(request), now: now)
    }

    static func token(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      systemConfiguration: URL = URL(fileURLWithPath: "/etc/grok"),
                      environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        guard !customAuthVariables.contains(where: { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })
        else { throw UsageReadError.missingSession }
        let directory: URL
        if let location = environment["GROK_HOME"], !location.isEmpty {
            guard location.hasPrefix("/") else { throw UsageReadError.missingSession }
            directory = URL(fileURLWithPath: location, isDirectory: true)
        } else {
            directory = home.appendingPathComponent(".grok", isDirectory: true)
        }
        // Managed auth or endpoint settings can select a different deployment from this same file.
        let configs = ["config.toml", "managed_config.toml", "requirements.toml"].map { directory.appendingPathComponent($0) }
            + ["managed_config.toml", "requirements.toml"].map { systemConfiguration.appendingPathComponent($0) }
        for config in configs where FileManager.default.fileExists(atPath: config.path) {
            guard let data = try? UsageCredentialReader.readSmallFile(config),
                  let contents = String(data: data, encoding: .utf8),
                  contents.range(of: authSections, options: .regularExpression) == nil else {
                throw UsageReadError.missingSession
            }
        }
        let file = directory.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw UsageReadError.missingSession }
        let credentials = try JSONDecoder().decode([String: Credential].self, from: UsageCredentialReader.readSmallFile(file))
        let selected = credentials["https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828"]
            ?? credentials["https://accounts.x.ai/sign-in"]
        guard let selected, selected.auth_mode != "api_key", let key = selected.key,
              UsageCredentialReader.isBearerToken(key) else { throw UsageReadError.missingSession }
        return key
    }

    private struct Credential: Decodable {
        let key: String?
        let auth_mode: String?
    }
}
