import Foundation
import SwiftUI
import PinesCore

@MainActor
final class PinesAppModel: ObservableObject {
    @Published var threads: [PinesThreadPreview]
    @Published var models: [PinesModelPreview]
    @Published var vaultItems: [PinesVaultItemPreview]
    @Published var settingsSections: [PinesSettingsSection]
    @Published var executionMode: AgentExecutionMode
    @Published var storeConfiguration: LocalStoreConfiguration
    @Published var selectedThemeTemplate: PinesThemeTemplate
    @Published var interfaceMode: PinesInterfaceMode

    init(
        threads: [PinesThreadPreview] = PinesSeedData.threads,
        models: [PinesModelPreview] = PinesSeedData.models,
        vaultItems: [PinesVaultItemPreview] = PinesSeedData.vaultItems,
        settingsSections: [PinesSettingsSection] = PinesSeedData.settingsSections,
        executionMode: AgentExecutionMode = .preferLocal,
        storeConfiguration: LocalStoreConfiguration = .init(),
        selectedThemeTemplate: PinesThemeTemplate = .evergreen,
        interfaceMode: PinesInterfaceMode = .system
    ) {
        self.threads = threads
        self.models = models
        self.vaultItems = vaultItems
        self.settingsSections = settingsSections
        self.executionMode = executionMode
        self.storeConfiguration = storeConfiguration
        self.selectedThemeTemplate = selectedThemeTemplate
        self.interfaceMode = interfaceMode
    }
}

struct PinesThreadPreview: Identifiable, Hashable {
    let id: UUID
    let title: String
    let modelName: String
    let modelID: ModelID
    let lastMessage: String
    let messages: [ChatMessage]
    let status: PinesThreadStatus
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
}

enum PinesModelStatus: String, Hashable {
    case ready
    case available
    case indexing

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .available:
            "Available"
        case .indexing:
            "Indexing"
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

private enum PinesSeedData {
    static let threads: [PinesThreadPreview] = [
        PinesThreadPreview(
            id: UUID(uuidString: "0F1D46B9-7D0D-46A9-8A2D-1EFD4E132001")!,
            title: "Local agent plan",
            modelName: "Qwen3 8B MLX",
            modelID: ModelID(rawValue: "mlx-community/Qwen3-4B-4bit"),
            lastMessage: "Drafted the next tool boundary and vault lookup path.",
            messages: [
                ChatMessage(role: .user, content: "Use the local vault and draft the next steps for this workspace."),
                ChatMessage(role: .assistant, content: "Drafted the next tool boundary and vault lookup path.")
            ],
            status: .local,
            updatedLabel: "9 min",
            tokenCount: 4812
        ),
        PinesThreadPreview(
            id: UUID(uuidString: "0F1D46B9-7D0D-46A9-8A2D-1EFD4E132002")!,
            title: "Vision import pass",
            modelName: "Llama Vision 11B",
            modelID: ModelID(rawValue: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit"),
            lastMessage: "Queued screenshots for OCR and private embeddings.",
            messages: [
                ChatMessage(role: .user, content: "Prepare the screenshot imports for a local vision pass."),
                ChatMessage(role: .assistant, content: "Queued screenshots for OCR and private embeddings.")
            ],
            status: .streaming,
            updatedLabel: "24 min",
            tokenCount: 1398
        ),
        PinesThreadPreview(
            id: UUID(uuidString: "0F1D46B9-7D0D-46A9-8A2D-1EFD4E132003")!,
            title: "Prompt library cleanup",
            modelName: "Gemma 3 4B",
            modelID: ModelID(rawValue: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
            lastMessage: "Grouped saved prompts by project and trust level.",
            messages: [
                ChatMessage(role: .user, content: "Clean up the prompt library for local reuse."),
                ChatMessage(role: .assistant, content: "Grouped saved prompts by project and trust level.")
            ],
            status: .archived,
            updatedLabel: "Yesterday",
            tokenCount: 872
        )
    ]

    static let models: [PinesModelPreview] = [
        PinesModelPreview(
            id: UUID(uuidString: "4E0F8CF0-F0AE-4B44-93D3-FD280A901001")!,
            install: ModelInstall(
                modelID: ModelID(rawValue: "mlx-community/Qwen3-4B-4bit"),
                displayName: "Qwen3 8B",
                repository: "mlx-community/Qwen3-4B-4bit",
                modalities: [.text],
                verification: .verified,
                state: .installed,
                estimatedBytes: 5_100_000_000,
                modelType: "qwen3"
            ),
            runtimeProfile: RuntimeProfile(name: "Balanced"),
            name: "Qwen3 8B",
            family: "Instruct",
            footprint: "5.1 GB",
            contextWindow: "32K",
            runtime: "MLX",
            status: .ready,
            capabilities: ["Chat", "Tools", "RAG"],
            readiness: 1
        ),
        PinesModelPreview(
            id: UUID(uuidString: "4E0F8CF0-F0AE-4B44-93D3-FD280A901002")!,
            install: ModelInstall(
                modelID: ModelID(rawValue: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit"),
                displayName: "Llama Vision 11B",
                repository: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
                modalities: [.text, .vision],
                verification: .installable,
                state: .remote,
                estimatedBytes: 7_800_000_000,
                modelType: "qwen2_5_vl"
            ),
            runtimeProfile: RuntimeProfile(name: "Vision"),
            name: "Llama Vision 11B",
            family: "Vision",
            footprint: "7.8 GB",
            contextWindow: "16K",
            runtime: "MLX VLM",
            status: .available,
            capabilities: ["Images", "OCR", "Chat"],
            readiness: 0.18
        ),
        PinesModelPreview(
            id: UUID(uuidString: "4E0F8CF0-F0AE-4B44-93D3-FD280A901003")!,
            install: ModelInstall(
                modelID: ModelID(rawValue: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"),
                displayName: "Nomic Embed Text",
                repository: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
                modalities: [.embeddings],
                verification: .experimental,
                state: .downloading,
                estimatedBytes: 540_000_000,
                modelType: "embedding"
            ),
            runtimeProfile: RuntimeProfile(name: "Vault indexing"),
            name: "Nomic Embed Text",
            family: "Embeddings",
            footprint: "540 MB",
            contextWindow: "8K",
            runtime: "MLX Embedders",
            status: .indexing,
            capabilities: ["Vault", "Search"],
            readiness: 0.64
        )
    ]

    static let vaultItems: [PinesVaultItemPreview] = [
        PinesVaultItemPreview(
            id: UUID(uuidString: "64D52A73-A798-4EBE-A394-37E019460001")!,
            title: "Agent architecture notes",
            kind: .note,
            detail: "Pinned design decisions and tool boundaries.",
            chunks: [
                chunk(id: "agent-architecture-notes-0", sourceID: "agent-architecture-notes", text: "Pinned design decisions and tool boundaries.")
            ],
            updatedLabel: "Today",
            sensitivity: .local,
            linkedThreads: 2
        ),
        PinesVaultItemPreview(
            id: UUID(uuidString: "64D52A73-A798-4EBE-A394-37E019460002")!,
            title: "Model eval rubric",
            kind: .document,
            detail: "Scoring sheet for local model selection.",
            chunks: [
                chunk(id: "model-eval-rubric-0", sourceID: "model-eval-rubric", text: "Scoring sheet for local model selection.")
            ],
            updatedLabel: "Mon",
            sensitivity: .privateCloud,
            linkedThreads: 5
        ),
        PinesVaultItemPreview(
            id: UUID(uuidString: "64D52A73-A798-4EBE-A394-37E019460003")!,
            title: "API key escrow",
            kind: .key,
            detail: "BYOK handles managed by the secure vault.",
            chunks: [
                chunk(id: "api-key-escrow-0", sourceID: "api-key-escrow", text: "BYOK handles managed by the secure vault.")
            ],
            updatedLabel: "Locked",
            sensitivity: .locked,
            linkedThreads: 0
        )
    ]

    static let settingsSections: [PinesSettingsSection] = [
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20000")!,
            title: "Design",
            subtitle: "Templates, light and dark mode, density, and motion.",
            systemImage: "paintpalette",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20010")!,
                    title: "Theme template",
                    detail: "Evergreen",
                    systemImage: "swatchpalette"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20011")!,
                    title: "Mode",
                    detail: "System",
                    systemImage: "circle.lefthalf.filled"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20001")!,
            title: "Inference",
            subtitle: "Runtime, memory, and model defaults.",
            systemImage: "cpu",
            rows: [
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21001")!,
                    title: "Default model",
                    detail: "Qwen3 8B",
                    systemImage: "sparkles"
                ),
                PinesSettingsRow(
                    id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A21002")!,
                    title: "Context budget",
                    detail: "32K tokens",
                    systemImage: "text.line.first.and.arrowtriangle.forward"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20002")!,
            title: "Privacy",
            subtitle: "Vault, sync, and key isolation.",
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
                    title: "Cloud sync",
                    detail: "Private database",
                    systemImage: "icloud"
                )
            ]
        ),
        PinesSettingsSection(
            id: UUID(uuidString: "9DAB62A0-A69B-4630-9291-D0C0C0A20003")!,
            title: "Tools",
            subtitle: "Agent actions and approvals.",
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
                    title: "Workspace access",
                    detail: "Selected folders",
                    systemImage: "folder.badge.gearshape"
                )
            ]
        )
    ]

    private static func chunk(id: String, sourceID: String, text: String) -> VaultChunk {
        VaultChunk(
            id: id,
            sourceID: sourceID,
            ordinal: 0,
            text: text,
            startOffset: 0,
            endOffset: text.count,
            checksum: "seed-\(sourceID)"
        )
    }
}
