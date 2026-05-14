import Foundation

public struct CuratedModelManifest: Sendable {
    public struct Entry: Identifiable, Hashable, Codable, Sendable {
        public var id: String { repository }
        public var repository: String
        public var displayName: String
        public var modalities: Set<ModelModality>
        public var memoryTier: DeviceMemoryTier
        public var notes: String

        public init(
            repository: String,
            displayName: String,
            modalities: Set<ModelModality>,
            memoryTier: DeviceMemoryTier,
            notes: String
        ) {
            self.repository = repository
            self.displayName = displayName
            self.modalities = modalities
            self.memoryTier = memoryTier
            self.notes = notes
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public func contains(repository: String) -> Bool {
        entries.contains { $0.repository.caseInsensitiveCompare(repository) == .orderedSame }
    }

    public static let `default` = CuratedModelManifest(entries: [
        Entry(
            repository: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            displayName: "Llama 3.2 1B 4-bit",
            modalities: [.text],
            memoryTier: .compact,
            notes: "Default small chat model for first launch."
        ),
        Entry(
            repository: "mlx-community/Qwen3-4B-4bit",
            displayName: "Qwen3 4B 4-bit",
            modalities: [.text],
            memoryTier: .balanced,
            notes: "General chat and reasoning candidate with thinking-mode caveats."
        ),
        Entry(
            repository: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit",
            displayName: "Qwen2.5 VL 3B 4-bit",
            modalities: [.text, .vision],
            memoryTier: .pro,
            notes: "Primary verified VLM lane for image prompts."
        ),
        Entry(
            repository: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
            displayName: "Qwen3 Embedding 0.6B 4-bit",
            modalities: [.embeddings],
            memoryTier: .balanced,
            notes: "Default knowledge-vault embedding model."
        ),
        Entry(
            repository: "mlx-community/bitnet-b1.58-2B-4T-4bit",
            displayName: "BitNet b1.58 2B 4T",
            modalities: [.text],
            memoryTier: .balanced,
            notes: "Experimental 1-bit-aware lane; keep disabled until device verification passes."
        ),
    ])
}
