import Foundation

public struct LocalRuntimeAdmissionRequest: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var modelID: String
    public var modelRevision: String?
    public var parameterCount: Int64?
    public var requestedContextTokens: Int
    public var reservedCompletionTokens: Int
    public var userMode: TurboQuantUserMode
    public var fallbackContract: TurboQuantFallbackContract
    public var deviceClass: DevicePerformanceClass
    public var hardwareModel: String?
    public var osBuild: String
    public var memoryCounters: RuntimeMemoryCounters
    public var quantizationDiagnostics: RuntimeQuantizationDiagnostics?
    public var profileEvidence: RuntimeProfileEvidence?
    public var calibration: RuntimeMemoryCalibration?
    public var estimatedModelWeightsBytes: Int64?
    public var compressedKVBytesPerToken: Int64
    public var rawShadowBytes: Int64
    public var packedFallbackBytesPerToken: Int64
    public var decodedFallbackScratchBytes: Int64
    public var vaultIndexBytes: Int64
    public var promptBufferBytes: Int64
    public var metalScratchReserveBytes: Int64
    public var uiReserveBytes: Int64
    public var contextAssemblyPlanID: String?
    public var speculativeBudget: TurboQuantSpeculativeAdmissionBudget?
  public var platformUnlockBudget: TurboQuantPlatformUnlockAdmissionBudget?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        modelID: String,
        modelRevision: String? = nil,
        parameterCount: Int64? = nil,
        requestedContextTokens: Int,
        reservedCompletionTokens: Int,
        userMode: TurboQuantUserMode,
        fallbackContract: TurboQuantFallbackContract,
        deviceClass: DevicePerformanceClass,
        hardwareModel: String? = nil,
        osBuild: String,
        memoryCounters: RuntimeMemoryCounters,
        quantizationDiagnostics: RuntimeQuantizationDiagnostics? = nil,
        profileEvidence: RuntimeProfileEvidence? = nil,
        calibration: RuntimeMemoryCalibration? = nil,
        estimatedModelWeightsBytes: Int64? = nil,
        compressedKVBytesPerToken: Int64,
        rawShadowBytes: Int64 = 0,
        packedFallbackBytesPerToken: Int64 = 0,
        decodedFallbackScratchBytes: Int64 = 0,
        vaultIndexBytes: Int64 = 0,
        promptBufferBytes: Int64 = 0,
        metalScratchReserveBytes: Int64 = 0,
        uiReserveBytes: Int64 = 0,
        contextAssemblyPlanID: String? = nil,
    speculativeBudget: TurboQuantSpeculativeAdmissionBudget? = nil,
    platformUnlockBudget: TurboQuantPlatformUnlockAdmissionBudget? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.parameterCount = parameterCount
        self.requestedContextTokens = max(0, requestedContextTokens)
        self.reservedCompletionTokens = max(0, reservedCompletionTokens)
        self.userMode = userMode
        self.fallbackContract = fallbackContract
        self.deviceClass = deviceClass
        self.hardwareModel = hardwareModel
        self.osBuild = osBuild
        self.memoryCounters = memoryCounters
        self.quantizationDiagnostics = quantizationDiagnostics
        self.profileEvidence = profileEvidence
        self.calibration = calibration
        self.estimatedModelWeightsBytes = estimatedModelWeightsBytes.map { max(0, $0) }
        self.compressedKVBytesPerToken = max(0, compressedKVBytesPerToken)
        self.rawShadowBytes = max(0, rawShadowBytes)
        self.packedFallbackBytesPerToken = max(0, packedFallbackBytesPerToken)
        self.decodedFallbackScratchBytes = max(0, decodedFallbackScratchBytes)
        self.vaultIndexBytes = max(0, vaultIndexBytes)
        self.promptBufferBytes = max(0, promptBufferBytes)
        self.metalScratchReserveBytes = max(0, metalScratchReserveBytes)
        self.uiReserveBytes = max(0, uiReserveBytes)
        self.contextAssemblyPlanID = contextAssemblyPlanID
        self.speculativeBudget = speculativeBudget
    self.platformUnlockBudget = platformUnlockBudget
    }
}

public struct LocalRuntimeAdmissionPlan: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var admitted: Bool
    public var requestedContextTokens: Int
    public var admittedContextTokens: Int
    public var reservedCompletionTokens: Int
    public var selectedMode: TurboQuantUserMode
    public var selectedKVStrategy: KVCacheStrategy
    public var selectedAttentionPath: TurboQuantAttentionPath?
    public var fallbackContract: TurboQuantFallbackContract
    public var memoryZones: RuntimeMemoryZones
    public var memoryCushionBytes: Int64
    public var calibrationApplied: RuntimeMemoryCalibrationSummary?
    public var downgradeReason: String?
    public var rejectionReason: String?
    public var speculativeBudget: TurboQuantSpeculativeAdmissionBudget?
  public var platformUnlockBudget: TurboQuantPlatformUnlockAdmissionBudget?
    public var userFacingMessage: String

    public init(
        schemaVersion: Int = Self.schemaVersion,
        admitted: Bool,
        requestedContextTokens: Int,
        admittedContextTokens: Int,
        reservedCompletionTokens: Int,
        selectedMode: TurboQuantUserMode,
        selectedKVStrategy: KVCacheStrategy,
        selectedAttentionPath: TurboQuantAttentionPath?,
        fallbackContract: TurboQuantFallbackContract,
        memoryZones: RuntimeMemoryZones,
        memoryCushionBytes: Int64,
        calibrationApplied: RuntimeMemoryCalibrationSummary? = nil,
        downgradeReason: String? = nil,
        rejectionReason: String? = nil,
        speculativeBudget: TurboQuantSpeculativeAdmissionBudget? = nil,
    platformUnlockBudget: TurboQuantPlatformUnlockAdmissionBudget? = nil,
        userFacingMessage: String
    ) {
        self.schemaVersion = schemaVersion
        self.admitted = admitted
        self.requestedContextTokens = max(0, requestedContextTokens)
        self.admittedContextTokens = max(0, admittedContextTokens)
        self.reservedCompletionTokens = max(0, reservedCompletionTokens)
        self.selectedMode = selectedMode
        self.selectedKVStrategy = selectedKVStrategy
        self.selectedAttentionPath = selectedAttentionPath
        self.fallbackContract = fallbackContract
        self.memoryZones = memoryZones
        self.memoryCushionBytes = memoryCushionBytes
        self.calibrationApplied = calibrationApplied
        self.downgradeReason = downgradeReason
        self.rejectionReason = rejectionReason
        self.speculativeBudget = speculativeBudget
    self.platformUnlockBudget = platformUnlockBudget
        self.userFacingMessage = userFacingMessage
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if !admitted, rejectionReason?.isEmpty != false {
            errors.append("rejected admission plan requires rejectionReason")
        }
        if admittedContextTokens > requestedContextTokens {
            errors.append("admittedContextTokens cannot exceed requestedContextTokens")
        }
        if fallbackContract.reserveBytes == 0
            && (fallbackContract.allowPackedFallback
                || fallbackContract.allowDecodedLayerLocalFallback
                || fallbackContract.allowFullDecodedFallback)
        {
            errors.append("fallback-enabled admission plan requires nonzero reserve")
        }
        if !memoryZones.totalMatchesZones {
            errors.append("memory zone total must equal zone sum")
        }
        return errors
    }
}

public struct LocalRuntimeAdmissionService: Sendable {
    public init() {}

    public func admit(_ request: LocalRuntimeAdmissionRequest) -> LocalRuntimeAdmissionPlan {
        let availableMemory = max(0, request.memoryCounters.availableMemoryBytes ?? 0)
        let calibration = request.calibration?.isStale() == false ? request.calibration : nil
        let calibrationMultiplier = calibration?.admissionMultiplier ?? 1
        let calibrationSummary = calibration.map(RuntimeMemoryCalibrationSummary.init)

        let primary = candidatePlan(
            request: request,
            mode: request.userMode,
            contextTokens: request.requestedContextTokens,
            fallbackContract: request.fallbackContract,
            availableMemory: availableMemory,
            calibrationMultiplier: calibrationMultiplier,
            calibrationSummary: calibrationSummary,
            downgradeReason: nil
        )
        if primary.admitted {
            return primary
        }

        for downgrade in request.fallbackContract.shorterContextDowngradePath() {
            let context = downgradedContextTokens(request.requestedContextTokens, for: downgrade.mode)
            let fallback = TurboQuantFallbackContract.productDefault(
                for: downgrade.mode,
                allowCloudRetry: request.fallbackContract.allowCloudRetry
            )
            let plan = candidatePlan(
                request: request,
                mode: downgrade.mode,
                contextTokens: context,
                fallbackContract: fallback,
                availableMemory: availableMemory,
                calibrationMultiplier: calibrationMultiplier,
                calibrationSummary: calibrationSummary,
                downgradeReason: downgrade.downgradeReason
            )
            if plan.admitted {
                return plan
            }
        }

        return primary
    }

    private func candidatePlan(
        request: LocalRuntimeAdmissionRequest,
        mode: TurboQuantUserMode,
        contextTokens: Int,
        fallbackContract: TurboQuantFallbackContract,
        availableMemory: Int64,
        calibrationMultiplier: Double,
        calibrationSummary: RuntimeMemoryCalibrationSummary?,
        downgradeReason: String?
    ) -> LocalRuntimeAdmissionPlan {
        let zones = memoryZones(
            request: request,
            contextTokens: contextTokens,
            fallbackContract: fallbackContract,
            availableMemory: availableMemory,
            calibrationSummary: calibrationSummary
        )
        let plannedWithoutSafety = max(0, zones.totalPlannedBytes - zones.safetyReserveBytes)
    let required =
      Int64((Double(plannedWithoutSafety) * calibrationMultiplier).rounded(.up))
            + zones.safetyReserveBytes
        let cushion = availableMemory - required
        let admitted = availableMemory > 0 && cushion >= 0
        let rejectionReason = admitted ? nil : LocalInferenceFailureKind.memoryAdmissionFailed.rawValue
        let selectedPath =
            request.quantizationDiagnostics?.activeAttentionPath
            ?? request.profileEvidence?.activeAttentionPath

        return LocalRuntimeAdmissionPlan(
            admitted: admitted,
            requestedContextTokens: request.requestedContextTokens,
            admittedContextTokens: admitted ? contextTokens : 0,
            reservedCompletionTokens: request.reservedCompletionTokens,
            selectedMode: mode,
            selectedKVStrategy: admitted ? .turboQuant : .none,
            selectedAttentionPath: selectedPath,
            fallbackContract: fallbackContract,
            memoryZones: zones,
            memoryCushionBytes: cushion,
            calibrationApplied: calibrationSummary,
            downgradeReason: admitted ? downgradeReason : nil,
            rejectionReason: rejectionReason,
            speculativeBudget: request.speculativeBudget,
      platformUnlockBudget: request.platformUnlockBudget,
            userFacingMessage: admitted
                ? "Local context admitted for \(mode.displayName)."
                : LocalInferenceFailureMatrix.rulesByKind[.memoryAdmissionFailed]?.productMessage
                    ?? "This context needs more memory than is safely available."
        )
    }

    private func memoryZones(
        request: LocalRuntimeAdmissionRequest,
        contextTokens: Int,
        fallbackContract: TurboQuantFallbackContract,
        availableMemory: Int64,
        calibrationSummary: RuntimeMemoryCalibrationSummary?
    ) -> RuntimeMemoryZones {
        let safetyReserve = max(512 * 1_024 * 1_024, availableMemory / 5)
    let modelWeights =
      request.estimatedModelWeightsBytes
            ?? request.memoryCounters.processResidentMemoryBytes
            ?? request.memoryCounters.processPhysicalFootprintBytes
            ?? 0
        let compressedKV = Int64(contextTokens) * request.compressedKVBytesPerToken
        let packedFallback =
            fallbackContract.allowPackedFallback
      ? max(
        fallbackContract.reserveBytes, Int64(contextTokens) * request.packedFallbackBytesPerToken)
            : 0
        let decodedScratch =
            (fallbackContract.allowDecodedLayerLocalFallback || fallbackContract.allowFullDecodedFallback)
      ? max(
        request.decodedFallbackScratchBytes,
        Int64(
          Double(request.decodedFallbackScratchBytes) * (calibrationSummary?.scratchMultiplier ?? 1)
        ))
            : 0

        return RuntimeMemoryZones(
            modelWeightsBytes: modelWeights,
            compressedKVBytes: compressedKV,
            rawShadowBytes: request.rawShadowBytes,
            packedFallbackBytes: packedFallback,
            decodedFallbackScratchBytes: decodedScratch,
            vaultIndexBytes: request.vaultIndexBytes,
            promptBufferBytes: request.promptBufferBytes,
            speculativeDraftModelBytes: request.speculativeBudget?.enabled == true
                ? request.speculativeBudget?.draftModelBytes
                : nil,
            speculativeDraftKVBytes: request.speculativeBudget?.enabled == true
                ? request.speculativeBudget?.draftKVBytes
                : nil,
            speculativeRollbackReserveBytes: request.speculativeBudget?.enabled == true
                ? request.speculativeBudget?.rollbackReserveBytes
                : nil,
      adaptivePrecisionMetadataBytes: request.platformUnlockBudget?.enabled == true
        ? request.platformUnlockBudget?.adaptivePrecisionMetadataBytes
        : nil,
      semanticMemoryBytes: request.platformUnlockBudget?.enabled == true
        ? request.platformUnlockBudget?.semanticMemoryBytes
        : nil,
      multimodalMemoryBytes: request.platformUnlockBudget?.enabled == true
        ? request.platformUnlockBudget?.multimodalMemoryBytes
        : nil,
      agentWorkingMemoryBytes: request.platformUnlockBudget?.enabled == true
        ? request.platformUnlockBudget?.agentWorkingMemoryBytes
        : nil,
      openKVFormatMetadataBytes: request.platformUnlockBudget?.enabled == true
        ? request.platformUnlockBudget?.openKVFormatMetadataBytes
        : nil,
      deviceMeshSyncBytes: request.platformUnlockBudget?.enabled == true
        ? request.platformUnlockBudget?.deviceMeshSyncBytes
        : nil,
      personalizationAdapterBytes: request.platformUnlockBudget?.enabled == true
        ? request.platformUnlockBudget?.personalizationAdapterBytes
        : nil,
            metalScratchReserveBytes: request.metalScratchReserveBytes,
            uiReserveBytes: request.uiReserveBytes,
            safetyReserveBytes: safetyReserve
        )
    }

    private func downgradedContextTokens(_ requested: Int, for mode: TurboQuantUserMode) -> Int {
        let divisor: Int
        switch mode {
        case .maxContext:
            divisor = 2
        case .balanced:
            divisor = 3
        case .fastest, .batterySaver:
            divisor = 4
        }
        return max(128, requested / divisor)
    }
}
