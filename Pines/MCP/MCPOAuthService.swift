import AuthenticationServices
import CryptoKit
import Foundation
import PinesCore
import Security
import UIKit

@MainActor
final class MCPOAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    var activeSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let scene = scenes.first {
            return ASPresentationAnchor(windowScene: scene)
        }
        preconditionFailure("OAuth presentation requires an active UIWindowScene.")
    }
}

@MainActor
struct MCPOAuthService {
    nonisolated static let redirectURI = "pines://oauth/mcp"

    let secretStore: any SecretStore
    let auditRepository: (any AuditEventRepository)?
    private let presentationContextProvider = MCPOAuthPresentationContextProvider()

    func discover(server: MCPServerConfiguration) async throws -> MCPDiscoveredOAuthConfiguration {
        let discovery = MCPOAuthDiscoveryService(urlSession: .shared)
        let result = try await discovery.discover(server: server)
        try await auditRepository?.append(
            AuditEvent(
                category: .security,
                summary: "Discovered OAuth metadata for MCP server \(server.displayName)",
                networkDomains: server.endpointURL.host(percentEncoded: false).map { [$0] } ?? []
            )
        )
        return result
    }

    func connect(server: MCPServerConfiguration) async throws {
        guard let authorizationURL = server.oauthAuthorizationURL,
              let tokenURL = server.oauthTokenURL,
              let clientID = server.oauthClientID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientID.isEmpty
        else {
            throw InferenceError.invalidRequest("OAuth MCP servers require authorization URL, token URL, and client ID.")
        }

        let verifier = Self.codeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "resource", value: server.oauthResource ?? server.endpointURL.absoluteString),
            URLQueryItem(name: "state", value: UUID().uuidString),
        ])
        if let scopes = server.oauthScopes, !scopes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: scopes))
        }
        components?.queryItems = queryItems
        guard let authURL = components?.url else {
            throw InferenceError.invalidRequest("OAuth authorization URL is invalid.")
        }

        let callbackURL = try await authenticate(url: authURL)
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw InferenceError.invalidRequest("OAuth callback did not contain an authorization code.")
        }

        let token = try await exchangeCode(
            code,
            verifier: verifier,
            tokenURL: tokenURL,
            clientID: clientID,
            resource: server.oauthResource ?? server.endpointURL.absoluteString
        )
        try await secretStore.write(token.accessToken, service: server.keychainService, account: "\(server.keychainAccount).access_token")
        if let refreshToken = token.refreshToken {
            try await secretStore.write(refreshToken, service: server.keychainService, account: "\(server.keychainAccount).refresh_token")
        }
        try await auditRepository?.append(
            AuditEvent(category: .security, summary: "Connected OAuth for MCP server \(server.displayName)")
        )
    }

    func disconnect(server: MCPServerConfiguration) async throws {
        try await secretStore.delete(service: server.keychainService, account: "\(server.keychainAccount).access_token")
        try await secretStore.delete(service: server.keychainService, account: "\(server.keychainAccount).refresh_token")
        try await auditRepository?.append(
            AuditEvent(category: .security, summary: "Disconnected OAuth for MCP server \(server.displayName)")
        )
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "pines") { callbackURL, error in
                Task { @MainActor in
                    presentationContextProvider.activeSession = nil
                }
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? InferenceError.cancelled)
                }
            }
            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = true
            presentationContextProvider.activeSession = session
            guard session.start() else {
                presentationContextProvider.activeSession = nil
                continuation.resume(throwing: InferenceError.invalidRequest("OAuth authentication could not start without an active presentation scene."))
                return
            }
        }
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        tokenURL: URL,
        clientID: String,
        resource: String
    ) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
            "resource": resource,
        ]
        request.httpBody = fields
            .map { "\($0.key.urlFormEncoded)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw InferenceError.invalidRequest("OAuth token exchange failed.")
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

struct MCPDiscoveredOAuthConfiguration: Hashable, Sendable {
    var authorizationURL: URL
    var tokenURL: URL
    var clientID: String
    var scopes: String?
    var resource: String
}

struct MCPOAuthDiscoveryService {
    let urlSession: URLSession

    func discover(server: MCPServerConfiguration) async throws -> MCPDiscoveredOAuthConfiguration {
        try validateEndpoint(server)
        let metadataURL = try await protectedResourceMetadataURL(for: server)
        let protectedResource = try await fetchProtectedResourceMetadata(metadataURL)
        guard let authorizationServer = protectedResource.authorizationServers.first else {
            throw InferenceError.invalidRequest("MCP OAuth metadata did not include an authorization server.")
        }
        let authorizationMetadata = try await fetchAuthorizationServerMetadata(issuer: authorizationServer)
        let clientID = try await dynamicClientIDIfAvailable(metadata: authorizationMetadata)
            ?? server.oauthClientID
            ?? ""
        guard !clientID.isEmpty else {
            throw InferenceError.invalidRequest("Authorization server does not support dynamic client registration. Enter a client ID manually.")
        }
        let scope = authorizationMetadata.scopesSupported?.joined(separator: " ")
        return MCPDiscoveredOAuthConfiguration(
            authorizationURL: authorizationMetadata.authorizationEndpoint,
            tokenURL: authorizationMetadata.tokenEndpoint,
            clientID: clientID,
            scopes: scope,
            resource: protectedResource.resource ?? server.endpointURL.absoluteString
        )
    }

    private func validateEndpoint(_ server: MCPServerConfiguration) throws {
        guard server.endpointURL.scheme?.lowercased() == "http" else { return }
        let host = server.endpointURL.host(percentEncoded: false)?.lowercased()
        let local = host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host?.hasSuffix(".local") == true
            || host?.hasPrefix("10.") == true
            || host?.hasPrefix("192.168.") == true
        guard server.allowInsecureLocalHTTP, local else {
            throw MCPTransportError.insecureHTTPNotAllowed(server.endpointURL)
        }
    }

    private func protectedResourceMetadataURL(for server: MCPServerConfiguration) async throws -> URL {
        var request = URLRequest(url: server.endpointURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": MCPStreamableHTTPClient.currentProtocolVersion,
                "capabilities": [:],
                "clientInfo": ["name": "Pines", "version": "0.1.0"],
            ],
        ])
        if let (_, response) = try? await urlSession.data(for: request),
           let metadata = MCPStreamableHTTPClient.resourceMetadataURL(from: response),
           let metadataURL = URL(string: metadata)
        {
            return metadataURL
        }

        guard var components = URLComponents(url: server.endpointURL, resolvingAgainstBaseURL: false) else {
            throw InferenceError.invalidRequest("MCP endpoint URL is invalid.")
        }
        components.path = "/.well-known/oauth-protected-resource"
        components.query = nil
        guard let fallbackURL = components.url else {
            throw InferenceError.invalidRequest("Could not build protected resource metadata URL.")
        }
        return fallbackURL
    }

    private func fetchProtectedResourceMetadata(_ url: URL) async throws -> ProtectedResourceMetadata {
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InferenceError.invalidRequest("Could not fetch OAuth protected resource metadata.")
        }
        return try JSONDecoder().decode(ProtectedResourceMetadata.self, from: data)
    }

    private func fetchAuthorizationServerMetadata(issuer: URL) async throws -> AuthorizationServerMetadata {
        let candidates = authorizationMetadataCandidates(for: issuer)
        for candidate in candidates {
            if let (data, response) = try? await urlSession.data(from: candidate),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let metadata = try? JSONDecoder().decode(AuthorizationServerMetadata.self, from: data)
            {
                return metadata
            }
        }
        throw InferenceError.invalidRequest("Could not fetch OAuth authorization server metadata.")
    }

    private func dynamicClientIDIfAvailable(metadata: AuthorizationServerMetadata) async throws -> String? {
        guard let registrationEndpoint = metadata.registrationEndpoint else {
            return nil
        }
        var request = URLRequest(url: registrationEndpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Pines",
            "redirect_uris": [MCPOAuthService.redirectURI],
            "token_endpoint_auth_method": "none",
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
        ])
        let (data, response) = try await urlSession.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            return nil
        }
        return try JSONDecoder().decode(DynamicClientRegistrationResponse.self, from: data).clientID
    }

    private func authorizationMetadataCandidates(for issuer: URL) -> [URL] {
        if issuer.path.contains(".well-known") {
            return [issuer]
        }
        var oauth = URLComponents(url: issuer, resolvingAgainstBaseURL: false)
        oauth?.path = "/.well-known/oauth-authorization-server"
        oauth?.query = nil
        var openID = URLComponents(url: issuer, resolvingAgainstBaseURL: false)
        openID?.path = "/.well-known/openid-configuration"
        openID?.query = nil
        return [oauth?.url, openID?.url, issuer].compactMap { $0 }
    }
}

private struct ProtectedResourceMetadata: Decodable {
    var resource: String?
    var authorizationServers: [URL]

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
    }
}

private struct AuthorizationServerMetadata: Decodable {
    var authorizationEndpoint: URL
    var tokenEndpoint: URL
    var registrationEndpoint: URL?
    var scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case scopesSupported = "scopes_supported"
    }
}

private struct DynamicClientRegistrationResponse: Decodable {
    var clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct OAuthTokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
