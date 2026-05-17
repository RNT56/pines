import Foundation
import SwiftUI
import PinesCore

extension ModelInstall {
    func enriched(with preflight: ModelPreflightResult) -> ModelInstall {
        var copy = self
        if !preflight.modalities.isEmpty {
            copy.modalities = preflight.modalities
        }
        copy.verification = CuratedModelManifest.default.contains(repository: repository) ? .verified : preflight.verification
        if copy.state == .remote, preflight.verification == .unsupported {
            copy.state = .unsupported
        }
        if preflight.estimatedBytes > 0 {
            copy.estimatedBytes = preflight.estimatedBytes
        }
        copy.license = preflight.license ?? copy.license
        copy.modelType = preflight.modelType ?? copy.modelType
        copy.processorClass = preflight.processorClass ?? copy.processorClass
        return copy
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension String {
    var pinesNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values = [T]()
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }

    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var values = [T]()
        values.reserveCapacity(count)
        for element in self {
            if let value = await transform(element) {
                values.append(value)
            }
        }
        return values
    }
}

extension RelativeDateTimeFormatter {
    static func shortLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PinesThreadPreview: Identifiable, Hashable {
    let id: UUID
    let title: String
    let modelName: String
    let modelID: ModelID
    let providerID: ProviderID?
    let lastMessage: String
    let messages: [ChatMessage]
    let status: PinesThreadStatus
    let isPinned: Bool
    let updatedLabel: String
    let tokenCount: Int

    var request: ChatRequest {
        ChatRequest(
            modelID: modelID,
            messages: messages,
            allowsTools: true,
            vaultContextIDs: []
        )
    }
}

struct ModelPickerSection: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let models: [ModelPickerOption]
}

struct ModelPickerOption: Identifiable, Hashable {
    var id: String { "\(providerID.rawValue)::\(modelID.rawValue)" }
    let providerID: ProviderID
    let providerName: String
    let providerKind: CloudProviderKind?
    let modelID: ModelID
    let displayName: String
    let isLocal: Bool
    let rank: Double
}

struct ChatQuickSettingsAvailability: Hashable {
    let providerID: ProviderID
    let modelID: ModelID
    let reasoningEfforts: [OpenAIReasoningEffort]
    let supportsVerbosity: Bool

    var isEmpty: Bool {
        reasoningEfforts.isEmpty && !supportsVerbosity
    }
}

enum PinesThreadStatus: String, Hashable {
    case local
    case streaming
    case archived

    var title: String {
        switch self {
        case .local:
            "Local"
        case .streaming:
            "Live"
        case .archived:
            "Archived"
        }
    }

    func tint(in theme: PinesTheme) -> Color {
        switch self {
        case .local:
            theme.colors.success
        case .streaming:
            theme.colors.info
        case .archived:
            theme.colors.tertiaryText
        }
    }
}

struct MCPSamplingResultReview: Identifiable, Hashable {
    let id = UUID()
    let serverID: MCPServerID
    let result: MCPSamplingResult
    let summary: String
}

struct CloudVaultEmbeddingApprovalRequest: Identifiable, Hashable {
    let id = UUID()
    let profile: VaultEmbeddingProfile
    let reason: String
}

struct MCPModelPreferenceProfile: Hashable {
    var hints: [String]
    var costPriority: Double
    var speedPriority: Double
    var intelligencePriority: Double

    init(json: JSONValue?) {
        let object = json?.objectValue ?? [:]
        hints = Self.hints(from: object["hints"])
        costPriority = Self.priority(from: object["costPriority"])
        speedPriority = Self.priority(from: object["speedPriority"])
        intelligencePriority = Self.priority(from: object["intelligencePriority"])
    }

    private static func hints(from value: JSONValue?) -> [String] {
        guard case let .array(items)? = value else { return [] }
        return items.compactMap { item in
            switch item {
            case let .string(name):
                return name
            case let .object(object):
                if case let .string(name)? = object["name"] {
                    return name
                }
                return nil
            default:
                return nil
            }
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private static func priority(from value: JSONValue?) -> Double {
        guard case let .number(priority)? = value else { return 0 }
        return min(max(priority, 0), 1)
    }
}

struct PinesModelPreview: Identifiable, Hashable {
    let id: UUID
    let install: ModelInstall
    let runtimeProfile: RuntimeProfile
    let name: String
    let family: String
    let footprint: String
    let contextWindow: String
    let runtime: String
    let status: PinesModelStatus
    let capabilities: [String]
    let readiness: Double
    let downloadProgress: ModelDownloadProgress?
    let compatibilityWarnings: [String]
}

extension PinesModelPreview {
    var isDownloadActive: Bool {
        downloadProgress?.isPinesDownloadActive == true || install.state == .downloading || status == .indexing
    }
}

extension ModelDownloadProgress {
    var isPinesDownloadActive: Bool {
        switch status {
        case .queued, .downloading, .verifying, .installing:
            true
        case .installed, .failed, .cancelled:
            false
        }
    }
}

enum PinesModelStatus: String, Hashable {
    case ready
    case available
    case indexing
    case failed
    case unsupported

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .available:
            "Available"
        case .indexing:
            "Downloading"
        case .failed:
            "Failed"
        case .unsupported:
            "Unsupported"
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.seal.fill"
        case .available:
            "arrow.down.circle.fill"
        case .indexing:
            "waveform.path.ecg"
        case .failed:
            "exclamationmark.triangle.fill"
        case .unsupported:
            "slash.circle.fill"
        }
    }
}

struct PinesVaultItemPreview: Identifiable, Hashable {
    let id: UUID
    let title: String
    let kind: PinesVaultKind
    let detail: String
    let chunks: [VaultChunk]
    let updatedLabel: String
    let sensitivity: PinesVaultSensitivity
    let linkedThreads: Int
    let activeProfileEmbeddedChunks: Int
    let activeProfileTotalChunks: Int
}

enum PinesVaultKind: String, Hashable {
    case note
    case document
    case image
    case key

    var title: String {
        switch self {
        case .note:
            "Note"
        case .document:
            "Document"
        case .image:
            "Image"
        case .key:
            "Key"
        }
    }

    var systemImage: String {
        switch self {
        case .note:
            "note.text"
        case .document:
            "doc.text"
        case .image:
            "photo"
        case .key:
            "key.fill"
        }
    }
}

enum PinesVaultSensitivity: String, Hashable {
    case local
    case privateCloud
    case locked

    var title: String {
        switch self {
        case .local:
            "On Device"
        case .privateCloud:
            "Private Cloud"
        case .locked:
            "Locked"
        }
    }

    var systemImage: String {
        switch self {
        case .local:
            "iphone"
        case .privateCloud:
            "icloud.fill"
        case .locked:
            "lock.fill"
        }
    }
}

struct PinesSettingsSection: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let systemImage: String
    let rows: [PinesSettingsRow]
}

struct PinesSettingsRow: Identifiable, Hashable {
    let id: UUID
    let title: String
    let detail: String
    let systemImage: String
}

enum PinesStaticSettings {
    static let sections: [PinesSettingsSection] = [
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20000")!,
            title: "Design",
            subtitle: "Theme, motion, haptics, and visual feel.",
            systemImage: "paintpalette",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20010")!,
                    title: "Theme template",
                    detail: "Color and surface system",
                    systemImage: "swatchpalette"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20011")!,
                    title: "Interaction feel",
                    detail: "Haptics and motion",
                    systemImage: "waveform.path"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20001")!,
            title: "Inference",
            subtitle: "Execution mode, local runtime, memory, and model access.",
            systemImage: "cpu",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21001")!,
                    title: "Execution policy",
                    detail: "Local or BYOK cloud",
                    systemImage: "sparkles"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21003")!,
                    title: "Generation limits",
                    detail: "Completion and context budgets",
                    systemImage: "slider.horizontal.3"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21002")!,
                    title: "Runtime diagnostics",
                    detail: "MLX and memory state",
                    systemImage: "memorychip"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20002")!,
            title: "Privacy",
            subtitle: "Storage, sync, and bring-your-own-key providers.",
            systemImage: "lock.shield",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A22001")!,
                    title: "Vault storage",
                    detail: "On device",
                    systemImage: "internaldrive"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A22002")!,
                    title: "Provider keys",
                    detail: "Stored in Keychain",
                    systemImage: "icloud"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20003")!,
            title: "Tools",
            subtitle: "Agent search keys, MCP servers, resources, and prompts.",
            systemImage: "wrench.and.screwdriver",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A23001")!,
                    title: "Tool approval",
                    detail: "Ask each time",
                    systemImage: "hand.raised"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A23002")!,
                    title: "MCP servers",
                    detail: "Tools and context",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20004")!,
            title: "System",
            subtitle: "Service health, readiness, and recent audit activity.",
            systemImage: "waveform.path.ecg",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A24001")!,
                    title: "Architecture health",
                    detail: "Service readiness",
                    systemImage: "stethoscope"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A24002")!,
                    title: "Audit trail",
                    detail: "Recent local events",
                    systemImage: "list.bullet.clipboard"
                )
            ]
        )
    ]

}
