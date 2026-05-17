import Foundation
import PinesCore

struct MCPResponseEnvelope<Result: Decodable>: Decodable {
    var jsonrpc: String
    var id: JSONValue?
    var result: Result?
    var error: MCPJSONRPCError?
}

struct MCPEmptyResult: Decodable {}

struct MCPResourcesListResult: Decodable {
    var resources: [RemoteResource]
    var nextCursor: String?
}

struct MCPResourceReadResult: Decodable {
    var contents: [MCPResourceContent]
}

struct MCPResourceTemplatesListResult: Decodable {
    var resourceTemplates: [RemoteResourceTemplate]
    var nextCursor: String?
}

struct MCPPromptsListResult: Decodable {
    var prompts: [RemotePrompt]
    var nextCursor: String?
}

struct RemoteResource: Decodable {
    var uri: String
    var name: String
    var title: String?
    var description: String?
    var mimeType: String?
    var size: Int64?
    var icons: [MCPIcon]?
    var annotations: MCPAnnotations?

    func record(serverID: MCPServerID) -> MCPResourceRecord {
        MCPResourceRecord(
            serverID: serverID,
            uri: uri,
            name: name,
            title: title,
            description: description,
            mimeType: mimeType,
            size: size,
            icons: icons ?? [],
            annotations: annotations
        )
    }
}

struct RemoteResourceTemplate: Decodable {
    var uriTemplate: String
    var name: String
    var title: String?
    var description: String?
    var mimeType: String?
    var icons: [MCPIcon]?
    var annotations: MCPAnnotations?

    func record(serverID: MCPServerID) -> MCPResourceTemplateRecord {
        MCPResourceTemplateRecord(
            serverID: serverID,
            uriTemplate: uriTemplate,
            name: name,
            title: title,
            description: description,
            mimeType: mimeType,
            icons: icons ?? [],
            annotations: annotations
        )
    }
}

struct RemotePrompt: Decodable {
    var name: String
    var title: String?
    var description: String?
    var arguments: [MCPPromptArgument]?
    var icons: [MCPIcon]?

    func record(serverID: MCPServerID) -> MCPPromptRecord {
        MCPPromptRecord(
            serverID: serverID,
            name: name,
            title: title,
            description: description,
            arguments: arguments ?? [],
            icons: icons ?? []
        )
    }
}

struct MCPSamplingCreateMessageParams: Decodable {
    var messages: [MCPPromptMessage]
    var modelPreferences: JSONValue?
    var systemPrompt: String?
    var includeContext: String?
    var maxTokens: Int?
    var temperature: Double?
    var stopSequences: [String]?
    var tools: [MCPToolDefinition]?
}

struct MCPOAuthTokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

extension String {
    var mcpStreamURLFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

extension JSONValue {
    var stableString: String {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return String(value)
        case let .bool(value):
            return String(value)
        default:
            do {
                return String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
            } catch {
                return ""
            }
        }
    }

    var jsonObject: Any {
        switch self {
        case let .object(value):
            value.mapValues(\.jsonObject)
        case let .array(value):
            value.map(\.jsonObject)
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
}
