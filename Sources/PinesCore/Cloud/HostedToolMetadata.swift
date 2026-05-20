import Foundation

public extension CloudProviderMetadataKeys {
    static let providerCitationsJSON = "pines.provider.citations_json"
}

public struct HostedToolAuditEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerItemID: String?
    public var type: String
    public var kind: OpenAIHostedToolKind
    public var status: OpenAIHostedToolCallStatus?
    public var name: String?
    public var action: JSONValue?
    public var containerID: String?
    public var serverLabel: String?
    public var serverURL: String?
    public var requiresAgentExecution: Bool
    public var requiresApproval: Bool
    public var raw: JSONValue

    public init(
        id: String,
        providerItemID: String? = nil,
        type: String,
        kind: OpenAIHostedToolKind,
        status: OpenAIHostedToolCallStatus? = nil,
        name: String? = nil,
        action: JSONValue? = nil,
        containerID: String? = nil,
        serverLabel: String? = nil,
        serverURL: String? = nil,
        requiresAgentExecution: Bool,
        requiresApproval: Bool,
        raw: JSONValue
    ) {
        self.id = id
        self.providerItemID = providerItemID
        self.type = type
        self.kind = kind
        self.status = status
        self.name = name
        self.action = action
        self.containerID = containerID
        self.serverLabel = serverLabel
        self.serverURL = serverURL
        self.requiresAgentExecution = requiresAgentExecution
        self.requiresApproval = requiresApproval
        self.raw = raw
    }
}

public struct ProviderArtifactMaterialization: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var providerItemID: String?
    public var kind: OpenAIArtifactKind
    public var type: String
    public var hostedToolCallID: OpenAIHostedToolCallID?
    public var providerFileID: OpenAIProviderFileID?
    public var containerID: String?
    public var fileName: String?
    public var contentType: String?
    public var byteCount: Int64?
    public var encoding: String?
    public var text: String?
    public var raw: JSONValue

    public init(
        id: String,
        providerItemID: String? = nil,
        kind: OpenAIArtifactKind,
        type: String,
        hostedToolCallID: OpenAIHostedToolCallID? = nil,
        providerFileID: OpenAIProviderFileID? = nil,
        containerID: String? = nil,
        fileName: String? = nil,
        contentType: String? = nil,
        byteCount: Int64? = nil,
        encoding: String? = nil,
        text: String? = nil,
        raw: JSONValue
    ) {
        self.id = id
        self.providerItemID = providerItemID
        self.kind = kind
        self.type = type
        self.hostedToolCallID = hostedToolCallID
        self.providerFileID = providerFileID
        self.containerID = containerID
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.encoding = encoding
        self.text = text
        self.raw = raw
    }
}

public extension Dictionary where Key == String, Value == String {
    var hostedToolAuditEntries: [HostedToolAuditEntry] {
        HostedToolMetadataParser.hostedToolAuditEntries(from: self)
    }

    var providerArtifactMaterializations: [ProviderArtifactMaterialization] {
        HostedToolMetadataParser.providerArtifactMaterializations(from: self)
    }

    var providerCitations: [ProviderCitation] {
        HostedToolMetadataParser.providerCitations(from: self)
    }
}

public enum HostedToolMetadataParser {
    public static func hostedToolAuditEntries(from metadata: [String: String]) -> [HostedToolAuditEntry] {
        let values = decodedJSONArray(metadata[CloudProviderMetadataKeys.openAIHostedToolCallsJSON])
            + decodedJSONArray(metadata[CloudProviderMetadataKeys.anthropicHostedToolCallsJSON])
        return values.compactMap(hostedToolAuditEntry(from:))
    }

    public static func providerArtifactMaterializations(from metadata: [String: String]) -> [ProviderArtifactMaterialization] {
        let values = decodedJSONArray(metadata[CloudProviderMetadataKeys.openAIArtifactsJSON])
            + decodedJSONArray(metadata[CloudProviderMetadataKeys.anthropicArtifactsJSON])
            + decodedJSONArray(metadata[CloudProviderMetadataKeys.anthropicFileReferencesJSON])
        return values.compactMap(providerArtifact(from:))
    }

    public static func providerCitations(from metadata: [String: String]) -> [ProviderCitation] {
        guard let raw = metadata[CloudProviderMetadataKeys.providerCitationsJSON],
              let data = raw.data(using: .utf8),
              let citations = try? JSONDecoder().decode([ProviderCitation].self, from: data)
        else { return [] }
        return citations
    }

    private static func hostedToolAuditEntry(from object: [String: JSONValue]) -> HostedToolAuditEntry? {
        guard let type = object["type"]?.stringValue else { return nil }
        let id = object["id"]?.stringValue ?? object["provider_item_id"]?.stringValue ?? UUID().uuidString
        let kind = hostedToolKind(for: type)
        let status = object["status"]?.stringValue.flatMap(hostedToolStatus(from:))
        let requiresAgent = kind == .computerUse || kind == .mcp || kind == .textEditor || kind == .bash
        let requiresApproval = requiresAgent && object["require_approval"]?.stringValue != "never"
        return HostedToolAuditEntry(
            id: id,
            providerItemID: object["provider_item_id"]?.stringValue ?? id,
            type: type,
            kind: kind,
            status: status,
            name: object["name"]?.stringValue,
            action: object["action"],
            containerID: object["container_id"]?.stringValue,
            serverLabel: object["server_label"]?.stringValue,
            serverURL: object["server_url"]?.stringValue,
            requiresAgentExecution: requiresAgent,
            requiresApproval: requiresApproval,
            raw: .object(object)
        )
    }

    private static func providerArtifact(from object: [String: JSONValue]) -> ProviderArtifactMaterialization? {
        guard let type = object["type"]?.stringValue else { return nil }
        let providerItemID = object["provider_item_id"]?.stringValue
        let fileID = object["file_id"]?.stringValue
        let id = object["id"]?.stringValue ?? fileID ?? providerItemID ?? UUID().uuidString
        return ProviderArtifactMaterialization(
            id: id,
            providerItemID: providerItemID,
            kind: artifactKind(for: type),
            type: type,
            hostedToolCallID: providerItemID.map(OpenAIHostedToolCallID.init(rawValue:)),
            providerFileID: fileID.map(OpenAIProviderFileID.init(rawValue:)),
            containerID: object["container_id"]?.stringValue,
            fileName: object["filename"]?.stringValue ?? object["file_name"]?.stringValue,
            contentType: object["mimeType"]?.stringValue ?? object["content_type"]?.stringValue,
            byteCount: object["byte_hint"]?.intValue.map(Int64.init),
            encoding: object["encoding"]?.stringValue,
            text: object["logs"]?.stringValue ?? object["text"]?.stringValue,
            raw: .object(object)
        )
    }

    private static func decodedJSONArray(_ raw: String?) -> [[String: JSONValue]] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .array(items) = value
        else { return [] }
        return items.compactMap(\.objectValue)
    }

    private static func hostedToolKind(for type: String) -> OpenAIHostedToolKind {
        switch type {
        case "web_search_call", "web_search_tool_result":
            return .webSearch
        case "web_fetch_call", "web_fetch_tool_result", "web_fetch":
            return .webFetch
        case "file_search_call":
            return .fileSearch
        case "code_interpreter_call", "server_tool_use", "code_execution", "code_execution_tool_result":
            return .codeInterpreter
        case "image_generation_call":
            return .imageGeneration
        case "computer_call", "computer_call_output":
            return .computerUse
        case "mcp_call", "mcp_list_tools", "mcp_tool_result":
            return .mcp
        case "text_editor_call", "text_editor":
            return .textEditor
        case "bash_call", "bash":
            return .bash
        case "tool_search_call":
            return .toolSearch
        default:
            return .custom
        }
    }

    private static func hostedToolStatus(from rawValue: String) -> OpenAIHostedToolCallStatus {
        switch rawValue {
        case "in_progress":
            return .inProgress
        case "requires_action":
            return .requiresAction
        default:
            return OpenAIHostedToolCallStatus(rawValue: rawValue) ?? .queued
        }
    }

    private static func artifactKind(for type: String) -> OpenAIArtifactKind {
        switch type {
        case "image", "partial_image":
            return .image
        case "container_file", "file_reference", "server_tool_use":
            return .file
        case "code_interpreter", "code_execution", "code_execution_tool_result":
            return .code
        case "code_interpreter_logs":
            return .toolOutput
        case "output_text":
            return .outputText
        default:
            return .toolOutput
        }
    }
}
