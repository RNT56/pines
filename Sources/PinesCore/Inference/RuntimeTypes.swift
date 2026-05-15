import Foundation

public enum ModelModality: String, Codable, Sendable, CaseIterable {
    case text
    case vision
    case embeddings
}

public enum ModelInstallState: String, Codable, Sendable, CaseIterable {
    case remote
    case downloading
    case installed
    case failed
    case unsupported
}

public enum ModelVerificationState: String, Codable, Sendable, CaseIterable {
    case verified
    case installable
    case experimental
    case unsupported
}

public struct QuantizationProfile: Hashable, Codable, Sendable {
    public var weightBits: Int?
    public var kvBits: Int?
    public var kvGroupSize: Int
    public var quantizedKVStart: Int
    public var maxKVSize: Int?

    public init(
        weightBits: Int? = nil,
        kvBits: Int? = nil,
        kvGroupSize: Int = 64,
        quantizedKVStart: Int = 0,
        maxKVSize: Int? = nil
    ) {
        self.weightBits = weightBits
        self.kvBits = kvBits
        self.kvGroupSize = kvGroupSize
        self.quantizedKVStart = quantizedKVStart
        self.maxKVSize = maxKVSize
    }
}

public struct RuntimeProfile: Hashable, Codable, Sendable {
    public var name: String
    public var quantization: QuantizationProfile
    public var prefillStepSize: Int
    public var promptCacheEnabled: Bool
    public var promptCacheIdentifier: String?
    public var speculativeDraftModelID: ModelID?
    public var speculativeDecodingEnabled: Bool
    public var unloadOnMemoryPressure: Bool
    public var repetitionContextSize: Int
    public var maxConcurrentSessions: Int

    public init(
        name: String = "Balanced",
        quantization: QuantizationProfile = .init(kvBits: 8),
        prefillStepSize: Int = 512,
        promptCacheEnabled: Bool = true,
        promptCacheIdentifier: String? = nil,
        speculativeDraftModelID: ModelID? = nil,
        speculativeDecodingEnabled: Bool = false,
        unloadOnMemoryPressure: Bool = true,
        repetitionContextSize: Int = 20,
        maxConcurrentSessions: Int = 1
    ) {
        self.name = name
        self.quantization = quantization
        self.prefillStepSize = prefillStepSize
        self.promptCacheEnabled = promptCacheEnabled
        self.promptCacheIdentifier = promptCacheIdentifier
        self.speculativeDraftModelID = speculativeDraftModelID
        self.speculativeDecodingEnabled = speculativeDecodingEnabled
        self.unloadOnMemoryPressure = unloadOnMemoryPressure
        self.repetitionContextSize = repetitionContextSize
        self.maxConcurrentSessions = maxConcurrentSessions
    }
}

public struct ModelInstall: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var modelID: ModelID
    public var displayName: String
    public var repository: String
    public var revision: String?
    public var localURL: URL?
    public var modalities: Set<ModelModality>
    public var verification: ModelVerificationState
    public var state: ModelInstallState
    public var parameterCount: Int64?
    public var estimatedBytes: Int64?
    public var license: String?
    public var modelType: String?
    public var processorClass: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        modelID: ModelID,
        displayName: String,
        repository: String,
        revision: String? = nil,
        localURL: URL? = nil,
        modalities: Set<ModelModality>,
        verification: ModelVerificationState,
        state: ModelInstallState = .remote,
        parameterCount: Int64? = nil,
        estimatedBytes: Int64? = nil,
        license: String? = nil,
        modelType: String? = nil,
        processorClass: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.modelID = modelID
        self.displayName = displayName
        self.repository = repository
        self.revision = revision
        self.localURL = localURL
        self.modalities = modalities
        self.verification = verification
        self.state = state
        self.parameterCount = parameterCount
        self.estimatedBytes = estimatedBytes
        self.license = license
        self.modelType = modelType
        self.processorClass = processorClass
        self.createdAt = createdAt
    }
}

public protocol LocalModelRunner: Sendable {
    func load(_ install: ModelInstall, profile: RuntimeProfile) async throws
    func unload() async
    func generate(_ request: ChatRequest) async throws -> AsyncThrowingStream<TokenDelta, Error>
}

public enum DeviceMemoryTier: String, Codable, Sendable, CaseIterable {
    case compact
    case balanced
    case pro
    case max
}

public struct DeviceProfile: Hashable, Codable, Sendable {
    public var memoryTier: DeviceMemoryTier
    public var recommendedMaxModelBytes: Int64
    public var recommendedContextTokens: Int
    public var allowsVisionModels: Bool

    public init(
        memoryTier: DeviceMemoryTier,
        recommendedMaxModelBytes: Int64,
        recommendedContextTokens: Int,
        allowsVisionModels: Bool
    ) {
        self.memoryTier = memoryTier
        self.recommendedMaxModelBytes = recommendedMaxModelBytes
        self.recommendedContextTokens = recommendedContextTokens
        self.allowsVisionModels = allowsVisionModels
    }

    public static let balancedPhone = DeviceProfile(
        memoryTier: .balanced,
        recommendedMaxModelBytes: 3_500_000_000,
        recommendedContextTokens: 8192,
        allowsVisionModels: true
    )
}
