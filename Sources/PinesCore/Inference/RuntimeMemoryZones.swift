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
            + self.metalScratchReserveBytes
            + self.uiReserveBytes
            + self.safetyReserveBytes
        self.totalPlannedBytes = max(0, totalPlannedBytes ?? computedTotal)
    }
}
