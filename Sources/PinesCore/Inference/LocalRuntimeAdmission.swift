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
    /// Per-token KV bytes if the cache were kept in plain FP16 (summed across all layers).
    /// When > 0, admission tries FP16 first and only falls to TurboQuant if the FP16 cache
    /// would not fit the live memory budget. 0 means "FP16 cost unknown" → FP16 is skipped.
    public var fp16KVBytesPerToken: Int64
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
        fp16KVBytesPerToken: Int64 = 0,
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
        self.fp16KVBytesPerToken = max(0, fp16KVBytesPerToken)
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

/// The KV representation a candidate admission plan would run with.
/// `plainFP16` maps to `KVCacheStrategy.none` (uncompressed, fastest, highest quality);
/// `turboQuant` maps to the compressed codec used only when FP16 will not fit.
private enum CandidateKVScheme: Sendable, Equatable {
    case plainFP16
    case turboQuant

    var kvStrategy: KVCacheStrategy { self == .plainFP16 ? .none : .turboQuant }
}

public struct LocalRuntimeAdmissionService: Sendable {
    public init() {}

    /// Chooses the KV representation by a memory-feasibility ladder rather than a static
    /// token threshold. FP16 is strictly faster and higher-quality whenever it fits, so it
    /// leads; TurboQuant is only selected when the FP16 cache would exceed the live budget.
    ///
    /// Order of candidates (first that fits wins):
    ///   1. FP16 @ full requested context                 — fastest, full length
    ///   2. (.fastest only) FP16 @ a shorter window        — never compress; cap length instead
    ///   3. TurboQuant @ full requested context            — keep length, accept slower decode
    ///   4. TurboQuant @ downgraded context (existing path) — last resort
    public func admit(_ request: LocalRuntimeAdmissionRequest) -> LocalRuntimeAdmissionPlan {
        let availableMemory = max(0, request.memoryCounters.availableMemoryBytes ?? 0)
        let calibration = request.calibration?.isStale() == false ? request.calibration : nil
        let calibrationMultiplier = calibration?.admissionMultiplier ?? 1
        let calibrationSummary = calibration.map(RuntimeMemoryCalibrationSummary.init)

        struct Candidate {
            var scheme: CandidateKVScheme
            var mode: TurboQuantUserMode
            var contextTokens: Int
            var fallbackContract: TurboQuantFallbackContract
            var downgradeReason: String?
        }
        var candidates: [Candidate] = []

        // FP16 is only a candidate when its per-token cost is known. It leads for every mode
        // except .maxContext, where the user has explicitly asked to reach as far as possible
        // (compression is the point) — there FP16 is still tried, but after compressed full.
        let fp16Known = request.fp16KVBytesPerToken > 0
        if fp16Known, request.userMode != .maxContext {
            candidates.append(Candidate(
                scheme: .plainFP16, mode: request.userMode,
                contextTokens: request.requestedContextTokens,
                fallbackContract: request.fallbackContract, downgradeReason: nil))
        }
        if fp16Known, request.userMode == .fastest {
            // .fastest never compresses: prefer a shorter FP16 window over switching to TurboQuant.
            candidates.append(Candidate(
                scheme: .plainFP16, mode: .fastest,
                contextTokens: downgradedContextTokens(request.requestedContextTokens, for: .fastest),
                fallbackContract: request.fallbackContract,
                downgradeReason: "fp16_context_capped_to_fit"))
        }

        // TurboQuant @ full requested context — the primary compressed option (and the canonical
        // rejection plan if nothing fits, preserving prior semantics).
        let primary = candidatePlan(
            request: request, scheme: .turboQuant, mode: request.userMode,
            contextTokens: request.requestedContextTokens,
            fallbackContract: request.fallbackContract, availableMemory: availableMemory,
            calibrationMultiplier: calibrationMultiplier, calibrationSummary: calibrationSummary,
            downgradeReason: nil)

        for candidate in candidates {
            let plan = candidatePlan(
                request: request, scheme: candidate.scheme, mode: candidate.mode,
                contextTokens: candidate.contextTokens,
                fallbackContract: candidate.fallbackContract, availableMemory: availableMemory,
                calibrationMultiplier: calibrationMultiplier, calibrationSummary: calibrationSummary,
                downgradeReason: candidate.downgradeReason)
            if plan.admitted { return plan }
        }
        if primary.admitted { return primary }

        for downgrade in request.fallbackContract.shorterContextDowngradePath() {
            let context = downgradedContextTokens(request.requestedContextTokens, for: downgrade.mode)
            let fallback = TurboQuantFallbackContract.productDefault(
                for: downgrade.mode,
                allowCloudRetry: request.fallbackContract.allowCloudRetry
            )
            let plan = candidatePlan(
                request: request,
                scheme: .turboQuant,
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
        scheme: CandidateKVScheme,
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
            scheme: scheme,
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
            selectedKVStrategy: admitted ? scheme.kvStrategy : .none,
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
        scheme: CandidateKVScheme,
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
        // FP16 keeps the KV cache uncompressed (fp16 bytes/token) and carries none of the
        // codec's shadow / packed-fallback / decoded-scratch overhead zones. TurboQuant uses
        // the compressed bytes/token and all of its fallback reserves.
        let isCompressed = scheme == .turboQuant
        let kvBytesPerToken =
            isCompressed ? request.compressedKVBytesPerToken : request.fp16KVBytesPerToken
        let compressedKV = Int64(contextTokens) * kvBytesPerToken
        let packedFallback =
            isCompressed && fallbackContract.allowPackedFallback
      ? max(
        fallbackContract.reserveBytes, Int64(contextTokens) * request.packedFallbackBytesPerToken)
            : 0
        let decodedScratch =
            isCompressed
                && (fallbackContract.allowDecodedLayerLocalFallback
                    || fallbackContract.allowFullDecodedFallback)
      ? max(
        request.decodedFallbackScratchBytes,
        Int64(
          Double(request.decodedFallbackScratchBytes) * (calibrationSummary?.scratchMultiplier ?? 1)
        ))
            : 0

        return RuntimeMemoryZones(
            modelWeightsBytes: modelWeights,
            compressedKVBytes: compressedKV,
            rawShadowBytes: isCompressed ? request.rawShadowBytes : 0,
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
