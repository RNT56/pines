import Foundation

public enum EndpointSecurityError: Error, Equatable, LocalizedError, Sendable {
    case missingScheme
    case insecureRemoteHTTP(URL)
    case insecureLocalHTTPNotAllowed(URL)
    case unsupportedScheme(URL)

    public var errorDescription: String? {
        switch self {
        case .missingScheme:
            return "Endpoint URL is missing a scheme."
        case let .insecureRemoteHTTP(url):
            return "Remote endpoint \(Self.redactedURL(url)) must use HTTPS."
        case let .insecureLocalHTTPNotAllowed(url):
            return "Local HTTP endpoint \(Self.redactedURL(url)) requires explicit local-development approval."
        case let .unsupportedScheme(url):
            return "Endpoint \(Self.redactedURL(url)) must use HTTPS, or localhost HTTP when explicitly allowed."
        }
    }

    private static func redactedURL(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? url.host(percentEncoded: false) ?? "endpoint"
    }
}

public struct EndpointSecurityPolicy: Sendable {
    public enum UseCase: Sendable {
        case cloudProvider
        case mcpEndpoint
        case oauthAuthorization
        case oauthToken
        case webTool
        case modelCatalog
    }

    public init() {}

    public func validate(
        _ url: URL,
        useCase _: UseCase,
        allowsExplicitLocalHTTP: Bool = false
    ) throws {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            throw EndpointSecurityError.missingScheme
        }
        if scheme == "https" {
            return
        }
        guard scheme == "http" else {
            throw EndpointSecurityError.unsupportedScheme(url)
        }
        guard Self.isLoopbackHost(url.host(percentEncoded: false)) else {
            throw EndpointSecurityError.insecureRemoteHTTP(url)
        }
        guard allowsExplicitLocalHTTP else {
            throw EndpointSecurityError.insecureLocalHTTPNotAllowed(url)
        }
    }

    public static func isLoopbackHost(_ host: String?) -> Bool {
        guard let normalized = host?.lowercased(), !normalized.isEmpty else {
            return false
        }
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized == "::1"
    }
}
