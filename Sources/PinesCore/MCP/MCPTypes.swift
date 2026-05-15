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
        self.status = status
        self.lastError = lastError
        self.lastConnectedAt = lastConnectedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
}
