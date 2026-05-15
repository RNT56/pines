import Foundation

public enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var anySendable: any Sendable {
        switch self {
        case let .object(value):
            value.mapValues(\.anySendable)
        case let .array(value):
            value.map(\.anySendable)
        case let .string(value):
            value
        case let .number(value):
            value
        case let .bool(value):
            value
        case .null:
            NSNull()
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    public static func objectSchema() -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    }
}

public struct MCPServerID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        rawValue = value
    }
}

public enum MCPAuthMode: String, Codable, Sendable, CaseIterable {
    case none
    case bearerToken
    case oauthPKCE
}

public enum MCPConnectionStatus: String, Codable, Sendable, CaseIterable {
    case disconnected
    case connecting
    case ready
    case degraded
    case failed
    case requiresAuthentication
}

public struct MCPServerConfiguration: Identifiable, Hashable, Codable, Sendable {
    public var id: MCPServerID
    public var displayName: String
    public var endpointURL: URL
    public var authMode: MCPAuthMode
    public var enabled: Bool
    public var allowInsecureLocalHTTP: Bool
    public var keychainService: String
    public var keychainAccount: String
    public var oauthAuthorizationURL: URL?
    public var oauthTokenURL: URL?
    public var oauthClientID: String?
    public var oauthScopes: String?
    public var oauthResource: String?
    public var resourcesEnabled: Bool
    public var promptsEnabled: Bool
    public var samplingEnabled: Bool
    public var byokSamplingEnabled: Bool
    public var subscriptionsEnabled: Bool
    public var maxSamplingRequestsPerSession: Int
    public var status: MCPConnectionStatus
    public var lastError: String?
    public var lastConnectedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: MCPServerID,
        displayName: String,
        endpointURL: URL,
        authMode: MCPAuthMode = .none,
        enabled: Bool = true,
        allowInsecureLocalHTTP: Bool = false,
        keychainService: String = "com.schtack.pines.mcp",
        keychainAccount: String,
        oauthAuthorizationURL: URL? = nil,
        oauthTokenURL: URL? = nil,
        oauthClientID: String? = nil,
        oauthScopes: String? = nil,
        oauthResource: String? = nil,
        resourcesEnabled: Bool = false,
        promptsEnabled: Bool = false,
        samplingEnabled: Bool = false,
        byokSamplingEnabled: Bool = false,
        subscriptionsEnabled: Bool = false,
        maxSamplingRequestsPerSession: Int = 3,
        status: MCPConnectionStatus = .disconnected,
        lastError: String? = nil,
        lastConnectedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.endpointURL = endpointURL
        self.authMode = authMode
        self.enabled = enabled
        self.allowInsecureLocalHTTP = allowInsecureLocalHTTP
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.oauthAuthorizationURL = oauthAuthorizationURL
        self.oauthTokenURL = oauthTokenURL
        self.oauthClientID = oauthClientID
        self.oauthScopes = oauthScopes
        self.oauthResource = oauthResource
        self.resourcesEnabled = resourcesEnabled
        self.promptsEnabled = promptsEnabled
        self.samplingEnabled = samplingEnabled
        self.byokSamplingEnabled = byokSamplingEnabled
        self.subscriptionsEnabled = subscriptionsEnabled
        self.maxSamplingRequestsPerSession = max(0, maxSamplingRequestsPerSession)
        self.status = status
        self.lastError = lastError
        self.lastConnectedAt = lastConnectedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MCPClientFeaturePolicy: Hashable, Codable, Sendable {
    public var resourcesEnabled: Bool
    public var promptsEnabled: Bool
    public var samplingEnabled: Bool
    public var subscriptionsEnabled: Bool

    public init(
        resourcesEnabled: Bool = false,
        promptsEnabled: Bool = false,
        samplingEnabled: Bool = false,
        subscriptionsEnabled: Bool = false
    ) {
        self.resourcesEnabled = resourcesEnabled
        self.promptsEnabled = promptsEnabled
        self.samplingEnabled = samplingEnabled
        self.subscriptionsEnabled = subscriptionsEnabled
    }

    public var initializeCapabilities: JSONValue {
        var capabilities = [String: JSONValue]()
        if samplingEnabled {
            capabilities["sampling"] = .object([:])
        }
        return .object(capabilities)
    }
}

public struct MCPToolRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String { namespacedName }
    public var serverID: MCPServerID
    public var originalName: String
    public var namespacedName: String
    public var displayName: String
    public var description: String
    public var inputSchema: JSONValue
    public var enabled: Bool
    public var lastDiscoveredAt: Date
    public var lastError: String?

    public init(
        serverID: MCPServerID,
        originalName: String,
        namespacedName: String,
        displayName: String,
        description: String,
        inputSchema: JSONValue,
        enabled: Bool = true,
        lastDiscoveredAt: Date = Date(),
        lastError: String? = nil
    ) {
        self.serverID = serverID
        self.originalName = originalName
        self.namespacedName = namespacedName
        self.displayName = displayName
        self.description = description
        self.inputSchema = inputSchema
        self.enabled = enabled
        self.lastDiscoveredAt = lastDiscoveredAt
        self.lastError = lastError
    }
}

public enum MCPRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct MCPImplementation: Codable, Hashable, Sendable {
    public var name: String
    public var version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct MCPJSONRPCError: Codable, Hashable, Error, Sendable {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct MCPToolDefinition: Codable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema
    }

    public init(name: String, description: String?, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        inputSchema = try container.decodeIfPresent(JSONValue.self, forKey: .inputSchema) ?? JSONValue.objectSchema()
    }
}

public struct MCPContentBlock: Codable, Hashable, Sendable {
    public var type: String
    public var text: String?
    public var data: String?
    public var mimeType: String?

    public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }
}

public struct MCPAnnotations: Codable, Hashable, Sendable {
    public var audience: [MCPRole]?
    public var priority: Double?
    public var lastModified: String?

    public init(audience: [MCPRole]? = nil, priority: Double? = nil, lastModified: String? = nil) {
        self.audience = audience
        self.priority = priority
        self.lastModified = lastModified
    }
}

public struct MCPIcon: Codable, Hashable, Sendable {
    public var src: String
    public var mimeType: String?
    public var sizes: [String]?

    public init(src: String, mimeType: String? = nil, sizes: [String]? = nil) {
        self.src = src
        self.mimeType = mimeType
        self.sizes = sizes
    }
}

public struct MCPResourceRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String { uri }
    public var serverID: MCPServerID
    public var uri: String
    public var name: String
    public var title: String?
    public var description: String?
    public var mimeType: String?
    public var size: Int64?
    public var icons: [MCPIcon]
    public var annotations: MCPAnnotations?
    public var selectedForContext: Bool
    public var subscribed: Bool
    public var lastDiscoveredAt: Date

    public init(
        serverID: MCPServerID,
        uri: String,
        name: String,
        title: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        size: Int64? = nil,
        icons: [MCPIcon] = [],
        annotations: MCPAnnotations? = nil,
        selectedForContext: Bool = false,
        subscribed: Bool = false,
        lastDiscoveredAt: Date = Date()
    ) {
        self.serverID = serverID
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
        self.size = size
        self.icons = icons
        self.annotations = annotations
        self.selectedForContext = selectedForContext
        self.subscribed = subscribed
        self.lastDiscoveredAt = lastDiscoveredAt
    }
}

public struct MCPResourceTemplateRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String { uriTemplate }
    public var serverID: MCPServerID
    public var uriTemplate: String
    public var name: String
    public var title: String?
    public var description: String?
    public var mimeType: String?
    public var icons: [MCPIcon]
    public var annotations: MCPAnnotations?
    public var lastDiscoveredAt: Date

    public init(
        serverID: MCPServerID,
        uriTemplate: String,
        name: String,
        title: String? = nil,
        description: String? = nil,
        mimeType: String? = nil,
        icons: [MCPIcon] = [],
        annotations: MCPAnnotations? = nil,
        lastDiscoveredAt: Date = Date()
    ) {
        self.serverID = serverID
        self.uriTemplate = uriTemplate
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
        self.icons = icons
        self.annotations = annotations
        self.lastDiscoveredAt = lastDiscoveredAt
    }
}

public struct MCPResourceContent: Codable, Hashable, Sendable {
    public var uri: String
    public var mimeType: String?
    public var text: String?
    public var blob: String?
    public var annotations: MCPAnnotations?

    public init(uri: String, mimeType: String? = nil, text: String? = nil, blob: String? = nil, annotations: MCPAnnotations? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
        self.annotations = annotations
    }
}

public struct MCPPromptArgument: Codable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var required: Bool?

    public init(name: String, description: String? = nil, required: Bool? = nil) {
        self.name = name
        self.description = description
        self.required = required
    }
}

public struct MCPPromptRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(serverID.rawValue):\(name)" }
    public var serverID: MCPServerID
    public var name: String
    public var title: String?
    public var description: String?
    public var arguments: [MCPPromptArgument]
    public var icons: [MCPIcon]
    public var lastDiscoveredAt: Date

    public init(
        serverID: MCPServerID,
        name: String,
        title: String? = nil,
        description: String? = nil,
        arguments: [MCPPromptArgument] = [],
        icons: [MCPIcon] = [],
        lastDiscoveredAt: Date = Date()
    ) {
        self.serverID = serverID
        self.name = name
        self.title = title
        self.description = description
        self.arguments = arguments
        self.icons = icons
        self.lastDiscoveredAt = lastDiscoveredAt
    }
}

public enum MCPMessageContent: Codable, Hashable, Sendable {
    case text(String)
    case image(data: String, mimeType: String)
    case audio(data: String, mimeType: String)
    case resource(MCPResourceContent)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: [MCPMessageContent])
    case unknown(JSONValue)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case data
        case mimeType
        case resource
        case id
        case name
        case input
        case toolUseID
        case toolUseId
        case content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "image":
            self = .image(
                data: try container.decodeIfPresent(String.self, forKey: .data) ?? "",
                mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "image/png"
            )
        case "audio":
            self = .audio(
                data: try container.decodeIfPresent(String.self, forKey: .data) ?? "",
                mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "audio/wav"
            )
        case "resource":
            self = .resource(try container.decode(MCPResourceContent.self, forKey: .resource))
        case "tool_use":
            self = .toolUse(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                input: try container.decodeIfPresent(JSONValue.self, forKey: .input) ?? .object([:])
            )
        case "tool_result":
            self = .toolResult(
                toolUseID: try container.decodeIfPresent(String.self, forKey: .toolUseID)
                    ?? container.decode(String.self, forKey: .toolUseId),
                content: try container.decodeIfPresent([MCPMessageContent].self, forKey: .content) ?? []
            )
        default:
            self = .unknown(try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(data, mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case let .audio(data, mimeType):
            try container.encode("audio", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case let .resource(resource):
            try container.encode("resource", forKey: .type)
            try container.encode(resource, forKey: .resource)
        case let .toolUse(id, name, input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case let .toolResult(toolUseID, content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
        case let .unknown(value):
            try value.encode(to: encoder)
        }
    }
}

public struct MCPPromptMessage: Codable, Hashable, Sendable {
    public var role: MCPRole
    public var content: [MCPMessageContent]

    enum CodingKeys: String, CodingKey {
        case role
        case content
    }

    public init(role: MCPRole, content: [MCPMessageContent]) {
        self.role = role
        self.content = content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(MCPRole.self, forKey: .role)
        if let content = try? container.decode([MCPMessageContent].self, forKey: .content) {
            self.content = content
        } else {
            self.content = [try container.decode(MCPMessageContent.self, forKey: .content)]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if content.count == 1 {
            try container.encode(content[0], forKey: .content)
        } else {
            try container.encode(content, forKey: .content)
        }
    }
}

public struct MCPPromptResult: Codable, Hashable, Sendable {
    public var description: String?
    public var messages: [MCPPromptMessage]

    public init(description: String? = nil, messages: [MCPPromptMessage]) {
        self.description = description
        self.messages = messages
    }
}

public struct MCPSamplingRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var serverID: MCPServerID
    public var messages: [MCPPromptMessage]
    public var systemPrompt: String?
    public var includeContext: String?
    public var maxTokens: Int?
    public var temperature: Double?
    public var stopSequences: [String]
    public var modelPreferences: JSONValue?
    public var tools: [MCPToolDefinition]

    public init(
        id: String,
        serverID: MCPServerID,
        messages: [MCPPromptMessage],
        systemPrompt: String? = nil,
        includeContext: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        stopSequences: [String] = [],
        modelPreferences: JSONValue? = nil,
        tools: [MCPToolDefinition] = []
    ) {
        self.id = id
        self.serverID = serverID
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.includeContext = includeContext
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.stopSequences = stopSequences
        self.modelPreferences = modelPreferences
        self.tools = tools
    }
}

public struct MCPSamplingResult: Codable, Hashable, Sendable {
    public var role: MCPRole
    public var content: MCPMessageContent
    public var model: String
    public var stopReason: String?

    public init(role: MCPRole = .assistant, content: MCPMessageContent, model: String, stopReason: String? = nil) {
        self.role = role
        self.content = content
        self.model = model
        self.stopReason = stopReason
    }
}

public struct MCPToolCallResult: Codable, Hashable, Sendable {
    public var content: [MCPContentBlock]
    public var structuredContent: JSONValue?
    public var isError: Bool?

    public init(content: [MCPContentBlock], structuredContent: JSONValue? = nil, isError: Bool? = nil) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }
}

public enum MCPNameSanitizer {
    public static func serverSlug(displayName: String, fallback: String) -> String {
        let slug = sanitize(displayName)
        return slug.isEmpty ? sanitize(fallback) : slug
    }

    public static func toolName(serverSlug: String, originalName: String) -> String {
        let original = sanitize(originalName)
        let base = "mcp.\(serverSlug).\(original.isEmpty ? "tool" : original)"
        guard base.count <= 64 else {
            let suffix = shortHash(for: "\(serverSlug).\(originalName)")
            let prefixBudget = max(1, 64 - 12)
            return "\(base.prefix(prefixBudget)).\(suffix)"
        }
        return base
    }

    private static func sanitize(_ value: String) -> String {
        let lowercased = value.lowercased()
        var output = ""
        var previousWasSeparator = false
        for scalar in lowercased.unicodeScalars {
            let allowed = isAlphaNumeric(scalar)
            if allowed {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                output.append("-")
                previousWasSeparator = true
            }
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    }

    private static func isAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            true
        default:
            false
        }
    }

    private static func shortHash(for value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16).prefix(10).description
    }
}

public protocol MCPServerRepository: Sendable {
    func listMCPServers() async throws -> [MCPServerConfiguration]
    func observeMCPServers() -> AsyncStream<[MCPServerConfiguration]>
    func upsertMCPServer(_ server: MCPServerConfiguration) async throws
    func deleteMCPServer(id: MCPServerID) async throws
    func listMCPTools(serverID: MCPServerID?) async throws -> [MCPToolRecord]
    func observeMCPTools() -> AsyncStream<[MCPToolRecord]>
    func replaceMCPTools(_ tools: [MCPToolRecord], serverID: MCPServerID) async throws
    func updateMCPToolEnabled(serverID: MCPServerID, namespacedName: String, enabled: Bool) async throws
    func listMCPResources(serverID: MCPServerID?) async throws -> [MCPResourceRecord]
    func observeMCPResources() -> AsyncStream<[MCPResourceRecord]>
    func replaceMCPResources(_ resources: [MCPResourceRecord], serverID: MCPServerID) async throws
    func updateMCPResourceSelection(serverID: MCPServerID, uri: String, selected: Bool) async throws
    func updateMCPResourceSubscription(serverID: MCPServerID, uri: String, subscribed: Bool) async throws
    func listMCPResourceTemplates(serverID: MCPServerID?) async throws -> [MCPResourceTemplateRecord]
    func replaceMCPResourceTemplates(_ templates: [MCPResourceTemplateRecord], serverID: MCPServerID) async throws
    func listMCPPrompts(serverID: MCPServerID?) async throws -> [MCPPromptRecord]
    func observeMCPPrompts() -> AsyncStream<[MCPPromptRecord]>
    func replaceMCPPrompts(_ prompts: [MCPPromptRecord], serverID: MCPServerID) async throws
}
