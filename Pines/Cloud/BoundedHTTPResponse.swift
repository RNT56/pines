import Foundation
import PinesCore

enum BoundedHTTPResponse {
    enum RedirectScope {
        case sameOrigin
        case publicHTTPS
    }

    static let jsonLimit = 32 * 1024 * 1024
    static let fileLimit = 64 * 1024 * 1024
    static let videoLimit = 512 * 1024 * 1024

    static func data(
        for request: URLRequest,
        session: URLSession,
        maxBytes: Int,
        redirectScope: RedirectScope = .sameOrigin
    ) async throws -> (Data, HTTPURLResponse) {
        guard let originURL = request.url else { throw CloudProviderError.invalidResponse }
        let redirectPolicy = BoundedRedirectPolicy(originURL: originURL, scope: redirectScope)
        let (bytes, response) = try await session.bytes(for: request, delegate: redirectPolicy)
        guard let http = response as? HTTPURLResponse else {
            throw CloudProviderError.invalidResponse
        }
        guard let finalURL = http.url,
              BoundedRedirectPolicy.isAllowed(finalURL, from: originURL, scope: redirectScope)
        else {
            throw CloudProviderError.invalidResponse
        }
        try validate(expectedContentLength: http.expectedContentLength, maxBytes: maxBytes)

        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(min(maxBytes, Int(http.expectedContentLength)))
        }
        for try await byte in bytes {
            try append(byte, to: &data, maxBytes: maxBytes)
        }
        return (data, http)
    }

    static func validate(expectedContentLength: Int64, maxBytes: Int) throws {
        guard expectedContentLength <= Int64(maxBytes) else {
            throw CloudProviderError.responseTooLarge(maxBytes: maxBytes)
        }
    }

    static func append(_ byte: UInt8, to data: inout Data, maxBytes: Int) throws {
        guard data.count < maxBytes else {
            throw CloudProviderError.responseTooLarge(maxBytes: maxBytes)
        }
        data.append(byte)
    }
}

private final class BoundedRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let originURL: URL
    private let scope: BoundedHTTPResponse.RedirectScope

    init(originURL: URL, scope: BoundedHTTPResponse.RedirectScope) {
        self.originURL = originURL
        self.scope = scope
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let target = request.url, Self.isAllowed(target, from: originURL, scope: scope) else {
            completionHandler(nil)
            return
        }
        var redirected = request
        if !EndpointSecurityPolicy.isSameOrigin(originURL, target) {
            for header in ["Authorization", "Cookie", "Proxy-Authorization", "X-Api-Key", "X-Goog-Api-Key", "X-Subscription-Token"] {
                redirected.setValue(nil, forHTTPHeaderField: header)
            }
        }
        completionHandler(redirected)
    }

    static func isAllowed(
        _ target: URL,
        from origin: URL,
        scope: BoundedHTTPResponse.RedirectScope
    ) -> Bool {
        switch scope {
        case .sameOrigin:
            return EndpointSecurityPolicy.isSameOrigin(origin, target)
        case .publicHTTPS:
            guard (try? EndpointSecurityPolicy().validate(target, useCase: .webTool)) != nil,
                  (try? EndpointSecurityPolicy.validateResolvedPublicAddresses(for: target)) != nil
            else { return false }
            return true
        }
    }
}
