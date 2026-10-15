import Foundation
import UsageCore

enum UsageBridgeClient {
    static func load(configuration: URLSessionConfiguration = .ephemeral) async throws -> UsageSnapshot {
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = nil
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: UsageSnapshot.bridgeURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("1", forHTTPHeaderField: "X-Usage-Rings-Widget")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200, response.expectedContentLength <= 65_536 else {
                throw UsageCLIError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 65_536 else { throw UsageCLIError.invalidResponse }
                data.append(byte)
            }
            guard let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else {
                throw UsageCLIError.invalidResponse
            }
            return snapshot
        } catch let error as UsageCLIError {
            throw error
        } catch {
            throw UsageCLIError.appUnavailable
        }
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
