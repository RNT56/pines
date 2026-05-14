import Foundation

public enum AuditCategory: String, Codable, Sendable, CaseIterable {
    case inference
    case tool
    case consent
    case modelDownload
    case vaultImport
    case cloudProvider
    case security
}

public struct AuditEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var category: AuditCategory
    public var summary: String
    public var redactedPayload: String?
    public var providerID: ProviderID?
    public var modelID: ModelID?
    public var toolName: String?
    public var networkDomains: [String]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        category: AuditCategory,
        summary: String,
        redactedPayload: String? = nil,
        providerID: ProviderID? = nil,
        modelID: ModelID? = nil,
        toolName: String? = nil,
        networkDomains: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.category = category
        self.summary = summary
        self.redactedPayload = redactedPayload
        self.providerID = providerID
        self.modelID = modelID
        self.toolName = toolName
        self.networkDomains = networkDomains
    }
}
