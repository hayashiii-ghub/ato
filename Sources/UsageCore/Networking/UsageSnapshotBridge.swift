import Foundation

public enum UsageSnapshotBridge {
    public enum Failure: Error, Equatable, Sendable {
        case unavailable, invalidResponse
    }

    public static func load(configuration: URLSessionConfiguration = .ephemeral,
                            requestTimeout: TimeInterval = 4, resourceTimeout: TimeInterval = 4) async throws -> UsageSnapshot {
        let session = UsageHTTPSession.make(configuration: configuration, requestTimeout: requestTimeout,
                                            resourceTimeout: resourceTimeout, allowsProxy: false)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: UsageSnapshot.bridgeURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("1", forHTTPHeaderField: "X-Usage-Rings-Widget")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200, response.expectedContentLength <= 65_536 else {
                throw Failure.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 65_536 else { throw Failure.invalidResponse }
                data.append(byte)
            }
            guard let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else {
                throw Failure.invalidResponse
            }
            return snapshot
        } catch let error as Failure {
            throw error
        } catch {
            throw Failure.unavailable
        }
    }
}
