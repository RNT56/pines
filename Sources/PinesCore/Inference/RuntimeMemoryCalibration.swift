import Foundation

public enum RuntimeMemoryCalibrationOutcome: String, Codable, Sendable, CaseIterable {
    case admittedSucceeded
    case rejectedBeforeRun
    case cancelledMemoryWarning
    case fallbackBudgetExceeded
    case runtimeFailed
    case jetsamSuspected
}

public struct RuntimeMemoryCalibrationSample: Hashable, Codable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var compatibilityPairID: String?
    public var runOutcome: String
    public var rejectionReason: String?
    public var modelID: String
    public var modelRevision: String?
    public var deviceClass: DevicePerformanceClass
    public var userMode: TurboQuantUserMode
    public var attentionPath: TurboQuantAttentionPath?
    public var requestedContextTokens: Int
    public var admittedContextTokens: Int
    public var estimatedCompressedKVBytes: Int64
    public var actualCompressedKVBytes: Int64?
    public var estimatedFallbackBytes: Int64
    public var actualFallbackBytes: Int64?
    public var estimatedScratchBytes: Int64
    public var observedPeakMemoryBytes: Int64?
    public var availableMemoryAtAdmission: Int64
    public var availableMemoryAtPrefillEnd: Int64?
    public var availableMemoryAtDecodeEnd: Int64?
    public var memoryWarningsSeen: Int
    public var createdAt: Date

    public init(
        schemaVersion: Int = Self.schemaVersion,
        id: UUID = UUID(),
        compatibilityPairID: String? = nil,
        runOutcome: String,
        rejectionReason: String? = nil,
        modelID: String,
        modelRevision: String? = nil,
        deviceClass: DevicePerformanceClass,
        userMode: TurboQuantUserMode,
        attentionPath: TurboQuantAttentionPath? = nil,
        requestedContextTokens: Int,
        admittedContextTokens: Int,
        estimatedCompressedKVBytes: Int64,
        actualCompressedKVBytes: Int64? = nil,
        estimatedFallbackBytes: Int64,
        actualFallbackBytes: Int64? = nil,
        estimatedScratchBytes: Int64,
        observedPeakMemoryBytes: Int64? = nil,
        availableMemoryAtAdmission: Int64,
        availableMemoryAtPrefillEnd: Int64? = nil,
        availableMemoryAtDecodeEnd: Int64? = nil,
        memoryWarningsSeen: Int,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.compatibilityPairID = compatibilityPairID
        self.runOutcome = runOutcome
        self.rejectionReason = rejectionReason
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.deviceClass = deviceClass
        self.userMode = userMode
        self.attentionPath = attentionPath
        self.requestedContextTokens = max(0, requestedContextTokens)
        self.admittedContextTokens = max(0, admittedContextTokens)
        self.estimatedCompressedKVBytes = max(0, estimatedCompressedKVBytes)
        self.actualCompressedKVBytes = actualCompressedKVBytes.map { max(0, $0) }
        self.estimatedFallbackBytes = max(0, estimatedFallbackBytes)
        self.actualFallbackBytes = actualFallbackBytes.map { max(0, $0) }
        self.estimatedScratchBytes = max(0, estimatedScratchBytes)
        self.observedPeakMemoryBytes = observedPeakMemoryBytes.map { max(0, $0) }
        self.availableMemoryAtAdmission = max(0, availableMemoryAtAdmission)
        self.availableMemoryAtPrefillEnd = availableMemoryAtPrefillEnd.map { max(0, $0) }
        self.availableMemoryAtDecodeEnd = availableMemoryAtDecodeEnd.map { max(0, $0) }
        self.memoryWarningsSeen = max(0, memoryWarningsSeen)
        self.createdAt = createdAt
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        id: UUID = UUID(),
        compatibilityPairID: String? = nil,
        runOutcome: RuntimeMemoryCalibrationOutcome,
        rejectionReason: String? = nil,
        modelID: String,
        modelRevision: String? = nil,
        deviceClass: DevicePerformanceClass,
        userMode: TurboQuantUserMode,
        attentionPath: TurboQuantAttentionPath? = nil,
        requestedContextTokens: Int,
        admittedContextTokens: Int,
        estimatedCompressedKVBytes: Int64,
        actualCompressedKVBytes: Int64? = nil,
        estimatedFallbackBytes: Int64,
        actualFallbackBytes: Int64? = nil,
        estimatedScratchBytes: Int64,
        observedPeakMemoryBytes: Int64? = nil,
        availableMemoryAtAdmission: Int64,
        availableMemoryAtPrefillEnd: Int64? = nil,
        availableMemoryAtDecodeEnd: Int64? = nil,
        memoryWarningsSeen: Int,
        createdAt: Date = Date()
    ) {
        self.init(
            schemaVersion: schemaVersion,
            id: id,
            compatibilityPairID: compatibilityPairID,
            runOutcome: runOutcome.rawValue,
            rejectionReason: rejectionReason,
            modelID: modelID,
            modelRevision: modelRevision,
            deviceClass: deviceClass,
            userMode: userMode,
            attentionPath: attentionPath,
            requestedContextTokens: requestedContextTokens,
            admittedContextTokens: admittedContextTokens,
            estimatedCompressedKVBytes: estimatedCompressedKVBytes,
            actualCompressedKVBytes: actualCompressedKVBytes,
            estimatedFallbackBytes: estimatedFallbackBytes,
            actualFallbackBytes: actualFallbackBytes,
            estimatedScratchBytes: estimatedScratchBytes,
            observedPeakMemoryBytes: observedPeakMemoryBytes,
            availableMemoryAtAdmission: availableMemoryAtAdmission,
            availableMemoryAtPrefillEnd: availableMemoryAtPrefillEnd,
            availableMemoryAtDecodeEnd: availableMemoryAtDecodeEnd,
            memoryWarningsSeen: memoryWarningsSeen,
            createdAt: createdAt
        )
    }
}

public struct RuntimeMemoryCalibration: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var deviceClass: DevicePerformanceClass
    public var modelFamily: String
    public var attentionPath: TurboQuantAttentionPath
    public var sampleCount: Int
    public var estimatedToActualPeakRatioP95: Double
    public var scratchMultiplier: Double
    public var fallbackMultiplier: Double
    public var safetyReserveBytes: Int64
    public var staleAfter: Date?
    public var updatedAt: Date

    public var admissionMultiplier: Double {
        max(1, estimatedToActualPeakRatioP95)
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        deviceClass: DevicePerformanceClass,
        modelFamily: String,
        attentionPath: TurboQuantAttentionPath,
        sampleCount: Int,
        estimatedToActualPeakRatioP95: Double,
        scratchMultiplier: Double,
        fallbackMultiplier: Double,
        safetyReserveBytes: Int64,
        staleAfter: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.deviceClass = deviceClass
        self.modelFamily = modelFamily
        self.attentionPath = attentionPath
        self.sampleCount = max(0, sampleCount)
        self.estimatedToActualPeakRatioP95 = max(1, estimatedToActualPeakRatioP95)
        self.scratchMultiplier = max(1, scratchMultiplier)
        self.fallbackMultiplier = max(1, fallbackMultiplier)
        self.safetyReserveBytes = max(0, safetyReserveBytes)
        self.staleAfter = staleAfter
        self.updatedAt = updatedAt
    }

    public func isStale(at date: Date = Date()) -> Bool {
        guard let staleAfter else {
            return false
        }
        return date >= staleAfter
    }
}

public struct RuntimeMemoryCalibrationSummary: Hashable, Codable, Sendable {
    public var sampleCount: Int
    public var estimatedToActualPeakRatioP95: Double
    public var scratchMultiplier: Double
    public var fallbackMultiplier: Double
    public var safetyReserveBytes: Int64
    public var updatedAt: Date

    public init(calibration: RuntimeMemoryCalibration) {
        self.sampleCount = calibration.sampleCount
        self.estimatedToActualPeakRatioP95 = calibration.estimatedToActualPeakRatioP95
        self.scratchMultiplier = calibration.scratchMultiplier
        self.fallbackMultiplier = calibration.fallbackMultiplier
        self.safetyReserveBytes = calibration.safetyReserveBytes
        self.updatedAt = calibration.updatedAt
    }
}
