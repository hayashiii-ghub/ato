import Foundation

public enum UsageHTTPSession {
    public static func make(configuration: URLSessionConfiguration = .ephemeral,
                            requestTimeout: TimeInterval, resourceTimeout: TimeInterval,
                            allowsProxy: Bool = true) -> URLSession {
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if !allowsProxy { configuration.connectionProxyDictionary = [:] }
        return URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
