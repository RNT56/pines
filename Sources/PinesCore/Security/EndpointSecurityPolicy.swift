import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum EndpointSecurityError: Error, Equatable, LocalizedError, Sendable {
    case missingScheme
    case insecureRemoteHTTP(URL)
    case insecureLocalHTTPNotAllowed(URL)
    case privateNetworkTarget(URL)
    case unsupportedScheme(URL)

    public var errorDescription: String? {
        switch self {
        case .missingScheme:
            return "Endpoint URL is missing a scheme."
        case let .insecureRemoteHTTP(url):
            return "Remote endpoint \(Self.redactedURL(url)) must use HTTPS."
        case let .insecureLocalHTTPNotAllowed(url):
            return "Local HTTP endpoint \(Self.redactedURL(url)) requires explicit local-development approval."
        case let .privateNetworkTarget(url):
            return "Endpoint \(Self.redactedURL(url)) resolves to a local, private, or non-public address."
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
        useCase: UseCase,
        allowsExplicitLocalHTTP: Bool = false
    ) throws {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            throw EndpointSecurityError.missingScheme
        }
        if scheme == "https" {
            if useCase == .webTool, !Self.isPublicWebHost(url.host(percentEncoded: false)) {
                throw EndpointSecurityError.privateNetworkTarget(url)
            }
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

    public static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host(percentEncoded: false)?.lowercased() == rhs.host(percentEncoded: false)?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    /// Rejects URL hosts that are local, private, link-local, documentation-only, multicast,
    /// or otherwise non-public. This is deliberately stricter than provider endpoint policy:
    /// arbitrary web tools must not become a path into services on the user's network.
    public static func isPublicWebHost(_ host: String?) -> Bool {
        guard var normalized = host?.lowercased(), !normalized.isEmpty else {
            return false
        }
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized.removeFirst()
            normalized.removeLast()
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        if normalized == "localhost"
            || normalized.hasSuffix(".localhost")
            || normalized.hasSuffix(".local")
            || normalized.hasSuffix(".internal")
            || normalized == "home.arpa"
            || normalized.hasSuffix(".home.arpa")
        {
            return false
        }

        if let octets = ipv4Octets(normalized) {
            let first = octets[0]
            let second = octets[1]
            if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
            if first == 100, (64...127).contains(second) { return false }
            if first == 169, second == 254 { return false }
            if first == 172, (16...31).contains(second) { return false }
            if first == 192, second == 168 { return false }
            if first == 192, second == 0 { return false }
            if first == 192, second == 0, octets[2] == 2 { return false }
            if first == 198, second == 18 || second == 19 || second == 51 { return false }
            if first == 203, second == 0, octets[2] == 113 { return false }
            return true
        }

        // Reject alternate numeric IPv4 spellings accepted by some URL stacks.
        if normalized.allSatisfy(\.isNumber) || normalized.hasPrefix("0x") {
            return false
        }
        let dottedParts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        if dottedParts.count == 4, dottedParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return false
        }

        if normalized.contains(":") {
            if normalized.hasPrefix("::") { return false }
            if normalized.hasPrefix("fc") || normalized.hasPrefix("fd") { return false }
            if ["fe8", "fe9", "fea", "feb", "fec", "fed", "fee", "fef", "ff"].contains(where: normalized.hasPrefix) { return false }
            if normalized.hasPrefix("2001:db8") { return false }
        }

        return true
    }

    /// Resolves a public hostname immediately before a web-tool request and rejects the
    /// request if any returned address is non-public. URL validation is still repeated
    /// for redirects and the final response URL.
    public static func validateResolvedPublicAddresses(for url: URL) throws {
        guard let host = url.host(percentEncoded: false), isPublicWebHost(host) else {
            throw EndpointSecurityError.privateNetworkTarget(url)
        }
        guard ipv4Octets(host) == nil, !host.contains(":") else { return }

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, nil, &result) == 0, let first = result else {
            return
        }
        defer { freeaddrinfo(first) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ai_next }
            guard current.pointee.ai_family == AF_INET || current.pointee.ai_family == AF_INET6,
                  let address = current.pointee.ai_addr
            else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                address,
                current.pointee.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard status == 0 else { continue }
            let terminator = buffer.firstIndex(of: 0) ?? buffer.endIndex
            let resolved = String(
                decoding: buffer[..<terminator].map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            if !isPublicWebHost(resolved) {
                throw EndpointSecurityError.privateNetworkTarget(url)
            }
        }
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  (part.count == 1 || part.first != "0"),
                  let value = Int(part),
                  (0...255).contains(value)
            else { return nil }
            return value
        }
        return octets.count == 4 ? octets : nil
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
