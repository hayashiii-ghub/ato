import Foundation
import Security
import UsageCore

enum AntigravityUsageClient {
    private static let hosts = ["daily-cloudcode-pa.googleapis.com", "cloudcode-pa.googleapis.com"]
    private static let access = Access()

    static func fetch(token: @Sendable () throws -> String, read: @Sendable (URLRequest) async throws -> Data,
                      now: Date = Date()) async throws -> ServiceUsage {
        let bearer = try token()
        var windows = try await readWindows("retrieveUserQuotaSummary", token: bearer, read: read) {
            try AntigravityQuotaResponse.summary($0, now: now)
        }
        if windows.isEmpty {
            windows = try await readWindows("fetchAvailableModels", token: bearer, read: read) {
                try AntigravityQuotaResponse.models($0)
            }
        }
        guard !windows.isEmpty else { throw UsageReadError.invalidResponse }
        return ServiceUsage(service: .gemini, state: .ready, windows: windows, updatedAt: now)
    }

    private static func readWindows(_ method: String, token: String, read: @Sendable (URLRequest) async throws -> Data,
                                    parse: @Sendable (Data) throws -> [UsageWindow]) async throws -> [UsageWindow] {
        async let preferred = readHost(hosts[0], method: method, token: token, read: read, parse: parse)
        async let secondary = readHost(hosts[1], method: method, token: token, read: read, parse: parse)
        let results = await [preferred, secondary]
        var seen = Set<String>()
        let windows = results.compactMap { try? $0.get() }.flatMap { $0 }.filter { seen.insert($0.id).inserted }
        if windows.isEmpty, results.allSatisfy({ result in
            guard case let .failure(error) = result, case UsageReadError.expiredSession = error else { return false }
            return true
        }) {
            throw UsageReadError.expiredSession
        }
        return windows
    }

    private static func readHost(_ host: String, method: String, token: String, read: @Sendable (URLRequest) async throws -> Data,
                                 parse: @Sendable (Data) throws -> [UsageWindow]) async -> Result<[UsageWindow], any Error> {
        do {
            var request = URLRequest(url: URL(string: "https://\(host)/v1internal:\(method)")!, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("antigravity/hub/2.24.0 (aidev_client; os_type=darwin; arch=arm64; cl=963137146)",
                             forHTTPHeaderField: "User-Agent")
            return .success(try parse(await read(request)))
        } catch {
            return .failure(error)
        }
    }

    static func token(allowingInteraction: Bool = false,
                      home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      environment: [String: String] = ProcessInfo.processInfo.environment,
                      now: Date = Date()) throws -> String {
        guard !["1", "true"].contains(environment["AGY_ADC_AUTH"]?.lowercased() ?? "") else {
            throw UsageReadError.missingSession
        }
        let configuredHome = environment["GEMINI_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        let directory: URL
        if let configuredHome {
            guard configuredHome.hasPrefix("/") else { throw UsageReadError.missingSession }
            directory = URL(fileURLWithPath: configuredHome, isDirectory: true)
        } else {
            directory = home.appendingPathComponent(".gemini", isDirectory: true)
        }
        let file = directory.appendingPathComponent("antigravity-cli/antigravity-oauth-token")
        if FileManager.default.fileExists(atPath: file.path) {
            return try decodeSession(UsageCredentialReader.readSmallFile(file), now: now).accessToken
        }
        // An isolated profile without its own token must not use the default account.
        guard configuredHome == nil else { throw UsageReadError.missingSession }
        return try access.token(allowingInteraction: allowingInteraction, now: now)
    }

    static func keychainQuery(allowingInteraction: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "gemini",
            kSecAttrAccount as String: "antigravity",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationUI as String: allowingInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        ]
    }

    private struct Credential: Decodable {
        struct Token: Decodable {
            let access_token: String
            let expiry: String
        }
        let token: Token
    }

    private struct Session {
        let accessToken: String
        let expiry: Date
    }

    private static func decodeSession(_ data: Data, now: Date) throws -> Session {
        guard !data.isEmpty, data.count <= 65_536, let text = String(data: data, encoding: .utf8) else {
            throw UsageReadError.invalidResponse
        }
        let decoded: Data
        if text.hasPrefix("go-keyring-base64:") {
            guard let payload = Data(base64Encoded: String(text.dropFirst("go-keyring-base64:".count))) else {
                throw UsageReadError.invalidResponse
            }
            decoded = payload
        } else if text.hasPrefix("go-keyring-encoded:") {
            let hex = Array(text.dropFirst("go-keyring-encoded:".count).utf8)
            guard hex.count.isMultiple(of: 2) else { throw UsageReadError.invalidResponse }
            var bytes = Data()
            for index in stride(from: 0, to: hex.count, by: 2) {
                guard let byte = UInt8(String(decoding: hex[index...index + 1], as: UTF8.self), radix: 16) else {
                    throw UsageReadError.invalidResponse
                }
                bytes.append(byte)
            }
            decoded = bytes
        } else {
            decoded = data
        }
        let token = try JSONDecoder().decode(Credential.self, from: decoded).token
        guard UsageCredentialReader.isBearerToken(token.access_token),
              let expiry = UsageResponseParser.parseDate(token.expiry), expiry > now.addingTimeInterval(60) else {
            throw UsageReadError.expiredSession
        }
        return Session(accessToken: token.access_token, expiry: expiry)
    }

    private final class Access: @unchecked Sendable {
        private let lock = NSLock()
        private var authorizedSession: Session?

        func token(allowingInteraction: Bool, now: Date) throws -> String {
            try lock.withLock {
                let query = keychainQuery(allowingInteraction: allowingInteraction) as CFDictionary
                let (status, data) = ProviderKeychain.read(query, allowingInteraction: allowingInteraction)
                switch status {
                case errSecSuccess:
                    authorizedSession = nil
                    guard let data else { throw UsageReadError.invalidResponse }
                    let session = try decodeSession(data, now: now)
                    if allowingInteraction { authorizedSession = session }
                    return session.accessToken
                case errSecItemNotFound:
                    authorizedSession = nil
                    throw UsageReadError.missingSession
                case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
                    if !allowingInteraction, let session = authorizedSession, session.expiry > now.addingTimeInterval(60) {
                        return session.accessToken
                    }
                    authorizedSession = nil
                    throw UsageReadError.keychainAccessRequired
                default:
                    authorizedSession = nil
                    throw UsageReadError.requestFailed
                }
            }
        }
    }
}
