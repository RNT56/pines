import Foundation

// MARK: - Provider transfers

public enum ProviderTransferSource: String, Codable, CaseIterable, Sendable {
    case localFile
    case vaultDocument
}

public enum ProviderTransferStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case preparing
    case transferring
    case verifying
    case completed
    case failed
    case cancelled
    case interrupted

    public var isActive: Bool {
        switch self {
        case .queued, .preparing, .transferring, .verifying: true
        case .completed, .failed, .cancelled, .interrupted: false
        }
    }

    public var canRetry: Bool {
        switch self {
        case .failed, .cancelled, .interrupted: true
        default: false
        }
    }
}

public struct ProviderTransferRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var providerID: ProviderID
    public var providerKind: CloudProviderKind
    public var source: ProviderTransferSource
    public var sourceReference: String
    public var stagedLocalURL: URL?
    public var fileName: String
    public var contentType: String?
    public var purpose: String?
    public var status: ProviderTransferStatus
    public var completedBytes: Int64
    public var totalBytes: Int64?
    public var retryCount: Int
    public var providerObjectID: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        providerKind: CloudProviderKind,
        source: ProviderTransferSource,
        sourceReference: String,
        stagedLocalURL: URL? = nil,
        fileName: String,
        contentType: String? = nil,
        purpose: String? = nil,
        status: ProviderTransferStatus = .queued,
        completedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        retryCount: Int = 0,
        providerObjectID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.providerKind = providerKind
        self.source = source
        self.sourceReference = sourceReference
        self.stagedLocalURL = stagedLocalURL
        self.fileName = fileName
        self.contentType = contentType
        self.purpose = purpose
        self.status = status
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.retryCount = retryCount
        self.providerObjectID = providerObjectID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.lastError = lastError
    }

    public var progressFraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

public protocol ProviderTransferRepository: Sendable {
    func listProviderTransfers(providerID: ProviderID?) async throws -> [ProviderTransferRecord]
    func upsertProviderTransfer(_ transfer: ProviderTransferRecord) async throws
    func deleteProviderTransfer(id: UUID) async throws
    func markActiveProviderTransfersInterrupted(at date: Date) async throws
}

// MARK: - Hosted-tool consent

public struct HostedToolApprovalDescriptor: Identifiable, Hashable, Codable, Sendable {
    public var id: String {
        ([providerToolName, environment] + networkDestinations).joined(separator: "::")
    }
    public var providerToolName: String
    public var displayName: String
    public var environment: String
    public var dataLeavingDevice: [String]
    public var sideEffects: [String]
    public var networkDestinations: [String]
    public var retentionNotice: String

    public init(
        providerToolName: String,
        displayName: String,
        environment: String,
        dataLeavingDevice: [String],
        sideEffects: [String],
        networkDestinations: [String],
        retentionNotice: String
    ) {
        self.providerToolName = providerToolName
        self.displayName = displayName
        self.environment = environment
        self.dataLeavingDevice = dataLeavingDevice
        self.sideEffects = sideEffects
        self.networkDestinations = networkDestinations
        self.retentionNotice = retentionNotice
    }
}

public struct HostedToolApprovalRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var providerID: ProviderID
    public var providerName: String
    public var modelID: ModelID
    public var descriptors: [HostedToolApprovalDescriptor]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        providerID: ProviderID,
        providerName: String,
        modelID: ModelID,
        descriptors: [HostedToolApprovalDescriptor],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
        self.descriptors = descriptors
        self.createdAt = createdAt
    }
}

public extension ChatRequest {
    func hostedToolApprovalDescriptors(providerName: String) -> [HostedToolApprovalDescriptor] {
        let generic = (hostedTools + (anthropicOptions?.hostedTools ?? []))
            .filter(\.requiresApproval)
            .map { $0.approvalDescriptor(providerName: providerName) }
        let openAI = (openAIResponseOptions?.hostedTools ?? [])
            .filter(\.requiresApproval)
            .map { $0.approvalDescriptor(providerName: providerName) }
        return (generic + openAI).reduce(into: []) { result, descriptor in
            if !result.contains(where: { $0.id == descriptor.id }) { result.append(descriptor) }
        }
    }
}

public extension HostedToolConfiguration {
    func approvalDescriptor(providerName: String) -> HostedToolApprovalDescriptor {
        switch self {
        case let .computerUse(width, height):
            return .init(
                providerToolName: "computer_use",
                displayName: "Computer use",
                environment: "\(providerName) hosted computer\(width.map { " (\($0)x\(height ?? 0))" } ?? "")",
                dataLeavingDevice: ["Your instructions", "screenshots and interaction state returned by the hosted computer"],
                sideEffects: ["Can click, type, navigate, and change data in the hosted environment"],
                networkDestinations: [providerName],
                retentionNotice: "The provider may retain tool inputs and outputs under its account and API retention policy."
            )
        case let .remoteMCP(label, serverURL, _):
            return .init(
                providerToolName: "remote_mcp",
                displayName: "Remote MCP - \(label)",
                environment: "Third-party MCP server called by \(providerName)",
                dataLeavingDevice: ["Relevant prompt and tool arguments", "Provider-generated tool context"],
                sideEffects: ["The MCP server may read or change external data according to the selected tool"],
                networkDestinations: [serverURL],
                retentionNotice: "Both the model provider and MCP server may process or retain the request."
            )
        case .textEditor:
            return .init(
                providerToolName: "text_editor",
                displayName: "Hosted text editor",
                environment: "\(providerName) hosted container",
                dataLeavingDevice: ["Text and files supplied to the model"],
                sideEffects: ["Can create and edit files inside the provider-hosted container"],
                networkDestinations: [providerName],
                retentionNotice: "Container files are processed under the provider's API retention policy."
            )
        case .bash:
            return .init(
                providerToolName: "bash",
                displayName: "Hosted shell",
                environment: "\(providerName) hosted container",
                dataLeavingDevice: ["Commands, prompt context, and files supplied to the model"],
                sideEffects: ["Can execute commands and create, modify, or delete container files"],
                networkDestinations: [providerName],
                retentionNotice: "Commands and results are processed under the provider's API retention policy."
            )
        default:
            return .init(
                providerToolName: approvalToolName,
                displayName: approvalToolName.replacingOccurrences(of: "_", with: " ").capitalized,
                environment: "\(providerName) hosted service",
                dataLeavingDevice: ["Relevant prompt context and tool arguments"],
                sideEffects: ["Provider-defined hosted tool execution"],
                networkDestinations: [providerName],
                retentionNotice: "Inputs and outputs are processed under the provider's API retention policy."
            )
        }
    }

    private var approvalToolName: String {
        switch self {
        case .webSearch: "web_search"
        case .webFetch: "web_fetch"
        case .fileSearch: "file_search"
        case .codeInterpreter: "code_interpreter"
        case .imageGeneration: "image_generation"
        case .computerUse: "computer_use"
        case .remoteMCP: "remote_mcp"
        case .textEditor: "text_editor"
        case .bash: "bash"
        case .toolSearch: "tool_search"
        }
    }
}

public extension OpenAIHostedToolRequest {
    func approvalDescriptor(providerName: String) -> HostedToolApprovalDescriptor {
        let hosted: HostedToolConfiguration = switch kind {
        case .computerUse: .computerUse(displayWidth: nil, displayHeight: nil)
        case .mcp:
            .remoteMCP(
                serverLabel: name ?? "MCP server",
                serverURL: configuration?.objectValue?["server_url"]?.stringValue ?? "Configured MCP server",
                requireApproval: configuration?.objectValue?["require_approval"]?.stringValue ?? "always"
            )
        case .textEditor: .textEditor
        case .bash: .bash
        default: .toolSearch
        }
        var descriptor = hosted.approvalDescriptor(providerName: providerName)
        descriptor.providerToolName = name ?? kind.rawValue
        return descriptor
    }
}

// MARK: - CloudKit conflict review

public enum CloudKitConflictEntity: String, Codable, CaseIterable, Sendable {
    case conversation
    case vaultDocument
}

public enum CloudKitConflictResolution: String, Codable, CaseIterable, Sendable {
    case unresolved
    case keepDevice
    case useICloud
}

public struct CloudKitConflictRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var entity: CloudKitConflictEntity
    public var entityID: UUID
    public var title: String
    public var deviceSummary: String
    public var iCloudSummary: String
    public var devicePayloadJSON: String
    public var iCloudPayloadJSON: String
    public var deviceUpdatedAt: Date
    public var iCloudUpdatedAt: Date
    public var resolution: CloudKitConflictResolution
    public var detectedAt: Date
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        entity: CloudKitConflictEntity,
        entityID: UUID,
        title: String,
        deviceSummary: String,
        iCloudSummary: String,
        devicePayloadJSON: String,
        iCloudPayloadJSON: String,
        deviceUpdatedAt: Date,
        iCloudUpdatedAt: Date,
        resolution: CloudKitConflictResolution = .unresolved,
        detectedAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.entity = entity
        self.entityID = entityID
        self.title = title
        self.deviceSummary = deviceSummary
        self.iCloudSummary = iCloudSummary
        self.devicePayloadJSON = devicePayloadJSON
        self.iCloudPayloadJSON = iCloudPayloadJSON
        self.deviceUpdatedAt = deviceUpdatedAt
        self.iCloudUpdatedAt = iCloudUpdatedAt
        self.resolution = resolution
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
    }
}

public protocol CloudKitConflictRepository: Sendable {
    func listCloudKitConflicts(unresolvedOnly: Bool) async throws -> [CloudKitConflictRecord]
    func upsertCloudKitConflict(_ conflict: CloudKitConflictRecord) async throws
    func resolveCloudKitConflict(id: UUID, resolution: CloudKitConflictResolution, at date: Date) async throws
}

// MARK: - OpenRouter spend reconciliation

public enum OpenRouterSpendWindow: String, Codable, CaseIterable, Sendable {
    case day
    case week
    case month
    case all

    public func startDate(relativeTo date: Date = Date()) -> Date? {
        let seconds: TimeInterval? = switch self {
        case .day: 86_400
        case .week: 604_800
        case .month: 2_592_000
        case .all: nil
        }
        return seconds.map { date.addingTimeInterval(-$0) }
    }
}

public struct OpenRouterSpendProviderBreakdown: Identifiable, Hashable, Codable, Sendable {
    public var id: String { providerName }
    public var providerName: String
    public var runCount: Int
    public var reportedCostCredits: Double
    public var upstreamCostCredits: Double

    public init(providerName: String, runCount: Int, reportedCostCredits: Double, upstreamCostCredits: Double) {
        self.providerName = providerName
        self.runCount = runCount
        self.reportedCostCredits = reportedCostCredits
        self.upstreamCostCredits = upstreamCostCredits
    }
}

public struct OpenRouterSpendReport: Hashable, Codable, Sendable {
    public var window: OpenRouterSpendWindow
    public var generatedAt: Date
    public var runCount: Int
    public var reportedCostRunCount: Int
    public var missingCostRunCount: Int
    public var reportedCostCredits: Double
    public var upstreamCostCredits: Double
    public var promptTokens: Int
    public var completionTokens: Int
    public var webSearchRunCount: Int
    public var byUpstreamProvider: [OpenRouterSpendProviderBreakdown]

    public init(
        window: OpenRouterSpendWindow,
        generatedAt: Date = Date(),
        runCount: Int = 0,
        reportedCostRunCount: Int = 0,
        missingCostRunCount: Int = 0,
        reportedCostCredits: Double = 0,
        upstreamCostCredits: Double = 0,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        webSearchRunCount: Int = 0,
        byUpstreamProvider: [OpenRouterSpendProviderBreakdown] = []
    ) {
        self.window = window
        self.generatedAt = generatedAt
        self.runCount = runCount
        self.reportedCostRunCount = reportedCostRunCount
        self.missingCostRunCount = missingCostRunCount
        self.reportedCostCredits = reportedCostCredits
        self.upstreamCostCredits = upstreamCostCredits
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.webSearchRunCount = webSearchRunCount
        self.byUpstreamProvider = byUpstreamProvider
    }
}

public protocol CloudSpendRepository: Sendable {
    func openRouterSpendReport(window: OpenRouterSpendWindow, now: Date) async throws -> OpenRouterSpendReport
}
