import Foundation

public struct RuntimeMemoryZones: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var modelWeightsBytes: Int64
    public var compressedKVBytes: Int64
    public var rawShadowBytes: Int64
    public var packedFallbackBytes: Int64
    public var decodedFallbackScratchBytes: Int64
    public var vaultIndexBytes: Int64
    public var promptBufferBytes: Int64
    public var speculativeDraftModelBytes: Int64?
    public var speculativeDraftKVBytes: Int64?
    public var speculativeRollbackReserveBytes: Int64?
  public var adaptivePrecisionMetadataBytes: Int64?
  public var semanticMemoryBytes: Int64?
  public var multimodalMemoryBytes: Int64?
  public var agentWorkingMemoryBytes: Int64?
  public var openKVFormatMetadataBytes: Int64?
  public var deviceMeshSyncBytes: Int64?
  public var personalizationAdapterBytes: Int64?
    public var metalScratchReserveBytes: Int64
    public var uiReserveBytes: Int64
    public var safetyReserveBytes: Int64
    public var totalPlannedBytes: Int64

    public var computedTotalPlannedBytes: Int64 {
        modelWeightsBytes
            + compressedKVBytes
            + rawShadowBytes
            + packedFallbackBytes
            + decodedFallbackScratchBytes
            + vaultIndexBytes
            + promptBufferBytes
            + (speculativeDraftModelBytes ?? 0)
            + (speculativeDraftKVBytes ?? 0)
            + (speculativeRollbackReserveBytes ?? 0)
      + (adaptivePrecisionMetadataBytes ?? 0)
      + (semanticMemoryBytes ?? 0)
      + (multimodalMemoryBytes ?? 0)
      + (agentWorkingMemoryBytes ?? 0)
      + (openKVFormatMetadataBytes ?? 0)
      + (deviceMeshSyncBytes ?? 0)
      + (personalizationAdapterBytes ?? 0)
            + metalScratchReserveBytes
            + uiReserveBytes
            + safetyReserveBytes
    }

    public var totalMatchesZones: Bool {
        totalPlannedBytes == computedTotalPlannedBytes
    }

    public var allZonesAreNonNegative: Bool {
        [
            modelWeightsBytes,
            compressedKVBytes,
            rawShadowBytes,
            packedFallbackBytes,
            decodedFallbackScratchBytes,
            vaultIndexBytes,
            promptBufferBytes,
            speculativeDraftModelBytes ?? 0,
            speculativeDraftKVBytes ?? 0,
            speculativeRollbackReserveBytes ?? 0,
      adaptivePrecisionMetadataBytes ?? 0,
      semanticMemoryBytes ?? 0,
      multimodalMemoryBytes ?? 0,
      agentWorkingMemoryBytes ?? 0,
      openKVFormatMetadataBytes ?? 0,
      deviceMeshSyncBytes ?? 0,
      personalizationAdapterBytes ?? 0,
            metalScratchReserveBytes,
            uiReserveBytes,
            safetyReserveBytes,
            totalPlannedBytes,
        ].allSatisfy { $0 >= 0 }
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        modelWeightsBytes: Int64,
        compressedKVBytes: Int64,
        rawShadowBytes: Int64,
        packedFallbackBytes: Int64,
        decodedFallbackScratchBytes: Int64,
        vaultIndexBytes: Int64,
        promptBufferBytes: Int64,
        speculativeDraftModelBytes: Int64? = nil,
        speculativeDraftKVBytes: Int64? = nil,
        speculativeRollbackReserveBytes: Int64? = nil,
    adaptivePrecisionMetadataBytes: Int64? = nil,
    semanticMemoryBytes: Int64? = nil,
    multimodalMemoryBytes: Int64? = nil,
    agentWorkingMemoryBytes: Int64? = nil,
    openKVFormatMetadataBytes: Int64? = nil,
    deviceMeshSyncBytes: Int64? = nil,
    personalizationAdapterBytes: Int64? = nil,
        metalScratchReserveBytes: Int64,
        uiReserveBytes: Int64,
        safetyReserveBytes: Int64,
        totalPlannedBytes: Int64? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.modelWeightsBytes = max(0, modelWeightsBytes)
        self.compressedKVBytes = max(0, compressedKVBytes)
        self.rawShadowBytes = max(0, rawShadowBytes)
        self.packedFallbackBytes = max(0, packedFallbackBytes)
        self.decodedFallbackScratchBytes = max(0, decodedFallbackScratchBytes)
        self.vaultIndexBytes = max(0, vaultIndexBytes)
        self.promptBufferBytes = max(0, promptBufferBytes)
        self.speculativeDraftModelBytes = speculativeDraftModelBytes.map { max(0, $0) }
        self.speculativeDraftKVBytes = speculativeDraftKVBytes.map { max(0, $0) }
        self.speculativeRollbackReserveBytes = speculativeRollbackReserveBytes.map { max(0, $0) }
    self.adaptivePrecisionMetadataBytes = adaptivePrecisionMetadataBytes.map { max(0, $0) }
    self.semanticMemoryBytes = semanticMemoryBytes.map { max(0, $0) }
    self.multimodalMemoryBytes = multimodalMemoryBytes.map { max(0, $0) }
    self.agentWorkingMemoryBytes = agentWorkingMemoryBytes.map { max(0, $0) }
    self.openKVFormatMetadataBytes = openKVFormatMetadataBytes.map { max(0, $0) }
    self.deviceMeshSyncBytes = deviceMeshSyncBytes.map { max(0, $0) }
    self.personalizationAdapterBytes = personalizationAdapterBytes.map { max(0, $0) }
        self.metalScratchReserveBytes = max(0, metalScratchReserveBytes)
        self.uiReserveBytes = max(0, uiReserveBytes)
        self.safetyReserveBytes = max(0, safetyReserveBytes)

        let computedTotal =
            self.modelWeightsBytes
            + self.compressedKVBytes
            + self.rawShadowBytes
            + self.packedFallbackBytes
            + self.decodedFallbackScratchBytes
            + self.vaultIndexBytes
            + self.promptBufferBytes
            + (self.speculativeDraftModelBytes ?? 0)
            + (self.speculativeDraftKVBytes ?? 0)
            + (self.speculativeRollbackReserveBytes ?? 0)
      + (self.adaptivePrecisionMetadataBytes ?? 0)
      + (self.semanticMemoryBytes ?? 0)
      + (self.multimodalMemoryBytes ?? 0)
      + (self.agentWorkingMemoryBytes ?? 0)
      + (self.openKVFormatMetadataBytes ?? 0)
      + (self.deviceMeshSyncBytes ?? 0)
      + (self.personalizationAdapterBytes ?? 0)
            + self.metalScratchReserveBytes
            + self.uiReserveBytes
            + self.safetyReserveBytes
        self.totalPlannedBytes = max(0, totalPlannedBytes ?? computedTotal)
    }
}
