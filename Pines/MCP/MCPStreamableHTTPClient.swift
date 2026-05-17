import Foundation
import PinesCore

enum MCPTransportError: Error, LocalizedError {
    case insecureHTTPNotAllowed(URL)
    case missingBearerToken
    case invalidHTTPResponse
    case httpStatus(Int, String)
    case unauthorized(String?)
    case invalidJSONRPCResponse
    case rpcError(MCPJSONRPCError)

    var errorDescription: String? {
        switch self {
        case let .insecureHTTPNotAllowed(url):
            "MCP server \(url.absoluteString) uses insecure HTTP. Use HTTPS or enable insecure local HTTP for development."
        case .missingBearerToken:
            "MCP server authentication requires a stored token."
        case .invalidHTTPResponse:
            "MCP server returned a non-HTTP response."
        case let .httpStatus(status, body):
            "MCP server returned HTTP \(status): \(body.prefix(240))"
        case let .unauthorized(metadataURL):
            metadataURL.map { "MCP server requires OAuth authorization metadata at \($0)." } ?? "MCP server requires OAuth authorization."
        case .invalidJSONRPCResponse:
            "MCP server returned an invalid JSON-RPC response."
        case let .rpcError(error):
            "MCP JSON-RPC error \(error.code): \(error.message)"
        }
    }
}

struct MCPInitializeResult: Decodable, Sendable {
    var protocolVersion: String
    var capabilities: JSONValue?
    var serverInfo: MCPImplementation?
}

struct MCPToolsListResult: Decodable, Sendable {
    var tools: [MCPToolDefinition]
}

struct MCPServerNotification: Sendable {
    var method: String
    var params: JSONValue?
}

enum MCPServerEvent: Sendable {
    case notification(MCPServerNotification)
    case samplingRequest(id: JSONValue, request: MCPSamplingRequest)
    case request(id: JSONValue, method: String, params: JSONValue?)
}

private actor MCPStreamableHTTPClientState {
    private(set) var server: MCPServerConfiguration
    private var sessionID: String?
    private var negotiatedProtocolVersion: String?
    private var nextID = 1

    init(server: MCPServerConfiguration) {
        self.server = server
    }

    func update(server: MCPServerConfiguration) {
        self.server = server
    }

    func setNegotiatedProtocolVersion(_ version: String) {
        negotiatedProtocolVersion = version
    }

    func setSessionID(_ sessionID: String?) {
        self.sessionID = sessionID
    }

    func hasSessionID() -> Bool {
        sessionID != nil
    }

    func nextRequestID(expectsResponse: Bool) -> Int? {
        guard expectsResponse else { return nil }
        defer { nextID += 1 }
        return nextID
    }

    func baseHeaders() -> [(String, String)] {
        var headers = [(String, String)]()
        if let negotiatedProtocolVersion {
            headers.append(("MCP-Protocol-Version", negotiatedProtocolVersion))
        }
        if let sessionID {
            headers.append(("Mcp-Session-Id", sessionID))
        }
        return headers
    }
}

final class MCPStreamableHTTPClient: Sendable {
    static let currentProtocolVersion = "2025-11-25"

    private let state: MCPStreamableHTTPClientState
    private let secretStore: any SecretStore
    private let urlSession: URLSession
    private let featurePolicy: MCPClientFeaturePolicy

    init(
        server: MCPServerConfiguration,
        secretStore: any SecretStore,
        featurePolicy: MCPClientFeaturePolicy? = nil,
        urlSession: URLSession = .shared
    ) {
        state = MCPStreamableHTTPClientState(server: server)
        self.secretStore = secretStore
        self.urlSession = urlSession
        self.featurePolicy = featurePolicy ?? MCPClientFeaturePolicy(
            resourcesEnabled: server.resourcesEnabled,
            promptsEnabled: server.promptsEnabled,
            samplingEnabled: server.samplingEnabled,
            subscriptionsEnabled: server.subscriptionsEnabled
        )
    }

    func update(server: MCPServerConfiguration) async {
        await state.update(server: server)
    }

    func initialize() async throws -> MCPInitializeResult {
        let params: JSONValue = .object([
            "protocolVersion": .string(Self.currentProtocolVersion),
            "capabilities": featurePolicy.initializeCapabilities,
            "clientInfo": .object([
                "name": .string("Pines"),
                "version": .string("0.1.0"),
            ]),
        ])
        let result: MCPInitializeResult = try await sendRequest(method: "initialize", params: params)
        await state.setNegotiatedProtocolVersion(result.protocolVersion)
        try await sendNotification(method: "notifications/initialized", params: nil)
        return result
    }

    func listTools() async throws -> [MCPToolDefinition] {
        let result: MCPToolsListResult = try await sendRequest(method: "tools/list", params: nil)
        return result.tools
    }

    func callTool(name: String, argumentsJSON: String) async throws -> MCPToolCallResult {
        let argumentsValue = try JSONDecoder().decode(JSONValue.self, from: Data(argumentsJSON.utf8))
        let params: JSONValue = .object([
            "name": .string(name),
            "arguments": argumentsValue,
        ])
        return try await sendRequest(method: "tools/call", params: params)
    }

    func listResources() async throws -> [MCPResourceRecord] {
        var cursor: String?
        var records = [MCPResourceRecord]()
        let serverID = await state.server.id
        repeat {
            let params = cursor.map { JSONValue.object(["cursor": .string($0)]) }
            let result: MCPResourcesListResult = try await sendRequest(method: "resources/list", params: params)
            records.append(contentsOf: result.resources.map { $0.record(serverID: serverID) })
            cursor = result.nextCursor
        } while cursor != nil
        return records
    }

    func readResource(uri: String) async throws -> [MCPResourceContent] {
        let result: MCPResourceReadResult = try await sendRequest(
            method: "resources/read",
            params: .object(["uri": .string(uri)])
        )
        return result.contents
    }

    func listResourceTemplates() async throws -> [MCPResourceTemplateRecord] {
        var cursor: String?
        var records = [MCPResourceTemplateRecord]()
        let serverID = await state.server.id
        repeat {
            let params = cursor.map { JSONValue.object(["cursor": .string($0)]) }
            let result: MCPResourceTemplatesListResult = try await sendRequest(method: "resources/templates/list", params: params)
            records.append(contentsOf: result.resourceTemplates.map { $0.record(serverID: serverID) })
            cursor = result.nextCursor
        } while cursor != nil
        return records
    }

    func subscribeResource(uri: String) async throws {
        _ = try await sendRequestEmpty(method: "resources/subscribe", params: .object(["uri": .string(uri)]))
    }

    func unsubscribeResource(uri: String) async throws {
        _ = try await sendRequestEmpty(method: "resources/unsubscribe", params: .object(["uri": .string(uri)]))
    }

    func listPrompts() async throws -> [MCPPromptRecord] {
        var cursor: String?
        var records = [MCPPromptRecord]()
        let serverID = await state.server.id
        repeat {
            let params = cursor.map { JSONValue.object(["cursor": .string($0)]) }
            let result: MCPPromptsListResult = try await sendRequest(method: "prompts/list", params: params)
            records.append(contentsOf: result.prompts.map { $0.record(serverID: serverID) })
            cursor = result.nextCursor
        } while cursor != nil
        return records
    }

    func getPrompt(name: String, arguments: [String: String]) async throws -> MCPPromptResult {
        var argumentObject = [String: JSONValue]()
        for (key, value) in arguments {
            argumentObject[key] = .string(value)
        }
        return try await sendRequest(
            method: "prompts/get",
            params: .object([
                "name": .string(name),
                "arguments": .object(argumentObject),
            ])
        )
    }

    func sendSamplingResult(id: JSONValue, result: MCPSamplingResult) async throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(result))
        try await sendJSONRPCResponse(id: id, result: value)
    }

    func sendJSONRPCError(id: JSONValue, code: Int, message: String) async throws {
        try await sendJSONRPCResponse(
            id: id,
            error: .object([
                "code": .number(Double(code)),
                "message": .string(message),
            ])
        )
    }

    func terminateSession() async {
        guard await state.hasSessionID() else { return }
        let server = await state.server
        var request = URLRequest(url: server.endpointURL)
        request.httpMethod = "DELETE"
        await applyBaseHeaders(to: &request)
        _ = try? await urlSession.data(for: request)
        await state.setSessionID(nil)
    }

    func notificationStream() -> AsyncThrowingStream<MCPServerNotification, Error> {
        let events = serverEventStream()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if case let .notification(notification) = event {
                            continuation.yield(notification)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func serverEventStream() -> AsyncThrowingStream<MCPServerEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let server = await self.state.server
                    var request = URLRequest(url: server.endpointURL)
                    request.httpMethod = "GET"
                    request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
                    try await self.applyAuthHeader(to: &request, server: server)
                    await self.applyBaseHeaders(to: &request)

                    let (bytes, response) = try await self.urlSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw MCPTransportError.invalidHTTPResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw MCPTransportError.httpStatus(http.statusCode, "")
                    }
                    if let headerSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !headerSessionID.isEmpty {
                        await self.state.setSessionID(headerSessionID)
                    }

                    var dataLines = [String]()
                    for try await rawLine in bytes.lines {
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if line.isEmpty {
                            if let event = try Self.event(fromSSEDataLines: dataLines, serverID: server.id) {
                                continuation.yield(event)
                            }
                            dataLines.removeAll()
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func sendNotification(method: String, params: JSONValue?) async throws {
        _ = try await sendJSONRPC(method: method, params: params, expectsResponse: false)
    }

    private func sendRequest<Result: Decodable>(method: String, params: JSONValue?) async throws -> Result {
        let data: Data = try await sendJSONRPC(method: method, params: params, expectsResponse: true)
        return try Self.decodeJSONRPCResult(Result.self, from: data)
    }

    private func sendRequestEmpty(method: String, params: JSONValue?) async throws {
        let _: MCPEmptyResult = try await sendRequest(method: method, params: params)
    }

    private func sendJSONRPCResponse(id: JSONValue, result: JSONValue? = nil, error: JSONValue? = nil) async throws {
        let server = await state.server
        var body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.jsonObject,
        ]
        if let result {
            body["result"] = result.jsonObject
        }
        if let error {
            body["error"] = error.jsonObject
        }
        var request = URLRequest(url: server.endpointURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await applyAuthHeader(to: &request, server: server)
        await applyBaseHeaders(to: &request)
        let (_, http) = try await urlSession.data(for: request)
        guard (200..<300).contains(http.statusCode) else {
            throw MCPTransportError.invalidHTTPResponse
        }
    }

    private func sendJSONRPC(method: String, params: JSONValue?, expectsResponse: Bool) async throws -> Data {
        let server = await state.server
        try validateEndpoint(server.endpointURL, server: server)
        let id = await state.nextRequestID(expectsResponse: expectsResponse)
        var body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let id {
            body["id"] = id
        }
        if let params {
            body["params"] = params.jsonObject
        }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (data, http) = try await postJSONRPC(bodyData: bodyData, method: method, server: server, forceOAuthRefresh: false)
        if http.statusCode == 401, server.authMode == .oauthPKCE {
            let (retryData, retryHTTP) = try await postJSONRPC(bodyData: bodyData, method: method, server: server, forceOAuthRefresh: true)
            guard (200..<300).contains(retryHTTP.statusCode) else {
                throw Self.httpError(data: retryData, response: retryHTTP)
            }
            return try decodeResponseData(retryData, response: retryHTTP, expectsResponse: expectsResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.httpError(data: data, response: http)
        }
        return try decodeResponseData(data, response: http, expectsResponse: expectsResponse)
    }

    private func postJSONRPC(
        bodyData: Data,
        method: String,
        server: MCPServerConfiguration,
        forceOAuthRefresh: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: server.endpointURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = method == "tools/call" ? 60 : 15
        request.httpBody = bodyData
        try await applyAuthHeader(to: &request, server: server, forceOAuthRefresh: forceOAuthRefresh)
        await applyBaseHeaders(to: &request)

        let (data, http) = try await urlSession.data(for: request)
        if let headerSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !headerSessionID.isEmpty {
            await state.setSessionID(headerSessionID)
        }
        return (data, http)
    }

    private func decodeResponseData(_ data: Data, response http: HTTPURLResponse, expectsResponse: Bool) throws -> Data {
        guard expectsResponse else {
            return Data()
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/event-stream") {
            return try Self.firstJSONRPCData(fromSSE: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    private func validateEndpoint(_ url: URL, server: MCPServerConfiguration) throws {
        guard url.scheme?.lowercased() == "http" else { return }
        if server.allowInsecureLocalHTTP, Self.isLocalHTTPHost(url.host(percentEncoded: false)) {
            return
        }
        throw MCPTransportError.insecureHTTPNotAllowed(url)
    }

    private func applyBaseHeaders(to request: inout URLRequest) async {
        for (field, value) in await state.baseHeaders() {
            request.addValue(value, forHTTPHeaderField: field)
        }
    }

    private func applyAuthHeader(
        to request: inout URLRequest,
        server: MCPServerConfiguration,
        forceOAuthRefresh: Bool = false
    ) async throws {
        switch server.authMode {
        case .none:
            break
        case .bearerToken:
            guard let token = try await secretStore.read(service: server.keychainService, account: server.keychainAccount),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw MCPTransportError.missingBearerToken
            }
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .oauthPKCE:
            guard let token = try await oauthAccessToken(forceRefresh: forceOAuthRefresh, server: server),
                  !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw MCPTransportError.missingBearerToken
            }
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func oauthAccessToken(forceRefresh: Bool, server: MCPServerConfiguration) async throws -> String? {
        if !forceRefresh,
           let token = try await secretStore.read(service: server.keychainService, account: "\(server.keychainAccount).access_token"),
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return token
        }
        guard let refreshToken = try await secretStore.read(service: server.keychainService, account: "\(server.keychainAccount).refresh_token"),
              let tokenURL = server.oauthTokenURL,
              let clientID = server.oauthClientID,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "resource": server.oauthResource ?? server.endpointURL.absoluteString,
        ]
        request.httpBody = fields
            .map { "\($0.key.mcpStreamURLFormEncoded)=\($0.value.mcpStreamURLFormEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await urlSession.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            return nil
        }
        let token = try JSONDecoder().decode(MCPOAuthTokenResponse.self, from: data)
        try await secretStore.write(token.accessToken, service: server.keychainService, account: "\(server.keychainAccount).access_token")
        if let refreshToken = token.refreshToken {
            try await secretStore.write(refreshToken, service: server.keychainService, account: "\(server.keychainAccount).refresh_token")
        }
        return token.accessToken
    }

    private static func httpError(data: Data, response: HTTPURLResponse) -> Error {
        if response.statusCode == 401 {
            return MCPTransportError.unauthorized(Self.resourceMetadataURL(from: response))
        }
        return MCPTransportError.httpStatus(response.statusCode, String(decoding: data, as: UTF8.self))
    }

    static func resourceMetadataURL(from response: HTTPURLResponse) -> String? {
        let header = response.value(forHTTPHeaderField: "WWW-Authenticate")
            ?? response.allHeaderFields.first { key, _ in
                String(describing: key).caseInsensitiveCompare("WWW-Authenticate") == .orderedSame
            }.map { String(describing: $0.value) }
        guard let header else { return nil }
        let pattern = #"resource_metadata\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let range = Range(match.range(at: 1), in: header)
        else {
            return nil
        }
        return String(header[range])
    }

    private static func decodeJSONRPCResult<Result: Decodable>(_ type: Result.Type, from data: Data) throws -> Result {
        let envelope = try JSONDecoder().decode(MCPResponseEnvelope<Result>.self, from: data)
        if let error = envelope.error {
            throw MCPTransportError.rpcError(error)
        }
        guard let result = envelope.result else {
            throw MCPTransportError.invalidJSONRPCResponse
        }
        return result
    }

    private static func firstJSONRPCData(fromSSE text: String) throws -> Data {
        var dataLines = [String]()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                let joined = dataLines.joined(separator: "\n")
                if joined.contains(#""jsonrpc""#), !joined.contains(#""method""#) || joined.contains(#""result""#) || joined.contains(#""error""#) {
                    return Data(joined.utf8)
                }
                dataLines.removeAll()
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        if !dataLines.isEmpty {
            return Data(dataLines.joined(separator: "\n").utf8)
        }
        throw MCPTransportError.invalidJSONRPCResponse
    }

    private static func event(fromSSEDataLines dataLines: [String], serverID: MCPServerID) throws -> MCPServerEvent? {
        guard !dataLines.isEmpty,
              let data = dataLines.joined(separator: "\n").data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["jsonrpc"] as? String == "2.0",
              let method = object["method"] as? String
        else {
            return nil
        }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let params = value.objectValue?["params"]
        if let id = value.objectValue?["id"] {
            if method == "sampling/createMessage" {
                let request = try samplingRequest(id: id, serverID: serverID, params: params)
                return .samplingRequest(id: id, request: request)
            }
            return .request(id: id, method: method, params: params)
        }
        return .notification(MCPServerNotification(method: method, params: params))
    }

    private static func samplingRequest(id: JSONValue, serverID: MCPServerID, params: JSONValue?) throws -> MCPSamplingRequest {
        let data = try JSONEncoder().encode(params ?? .object([:]))
        let decoded = try JSONDecoder().decode(MCPSamplingCreateMessageParams.self, from: data)
        return MCPSamplingRequest(
            id: id.stableString,
            serverID: serverID,
            messages: decoded.messages,
            systemPrompt: decoded.systemPrompt,
            includeContext: decoded.includeContext,
            maxTokens: decoded.maxTokens,
            temperature: decoded.temperature,
            stopSequences: decoded.stopSequences ?? [],
            modelPreferences: decoded.modelPreferences,
            tools: decoded.tools ?? []
        )
    }

    private static func isLocalHTTPHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") {
            return true
        }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") {
            return true
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 172 && (16...31).contains(parts[1])
    }
}
