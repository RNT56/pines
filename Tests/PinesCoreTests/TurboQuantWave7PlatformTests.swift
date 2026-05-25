import Foundation
import PinesCore
import Testing

@Suite("TurboQuant Wave 7 platform unlock control plane")
struct TurboQuantWave7PlatformTests {
  @Test func platformUnlockDefaultsRemainDisabledAndKillSwitched() {
    let policy = TurboQuantPlatformUnlockPolicy.disabled

    #expect(policy.activeFeatureIDs.isEmpty)
    #expect(policy.validationErrors.isEmpty)
    #expect(policy.featureGates.count == TurboQuantPlatformFeatureID.allCases.count)
    #expect(policy.featureGates.allSatisfy { !$0.isProductActive })
    #expect(policy.featureGates.allSatisfy { $0.killSwitchEnabled })
    #expect(policy.featureGates.allSatisfy { $0.evidenceRequired })
  }

  @Test func activePlatformPoliciesFailClosedWithoutRequiredSafetyState() {
    let adaptive = TurboQuantAdaptivePrecisionPolicy(
      enabled: true,
      killSwitchEnabled: false,
      evidenceRequired: false,
      compatibilityPairID: nil,
      segmentPolicy: [
        TurboQuantPrecisionSegment(
          role: .pinnedPrompt,
          tokenStart: 0,
          tokenCount: 128,
          keyBits: 8,
          valueBits: 8,
          priority: 1,
          reason: "pinned prompt"
        )
      ]
    )
    let openKV = TurboQuantOpenKVFormatDescriptor(
      enabled: true,
      killSwitchEnabled: false,
      evidenceRequired: false,
      turboQuantLayoutVersion: nil,
      localOnlyByDefault: false,
      encryptionRequired: false,
      supportExportIncludesBlobs: true
    )
    let memory = TurboQuantMemoryPlanePolicy(
      semanticMemoryEnabled: true,
      killSwitchEnabled: false,
      evidenceRequired: false,
      localOnlyByDefault: false,
      cloudExportRequiresApproval: false
    )
    let deviceMesh = TurboQuantDeviceMeshPolicy(
      enabled: true,
      encryptedLANSyncEnabled: false,
      killSwitchEnabled: false,
      evidenceRequired: false,
      localNetworkOnly: false,
      peerIdentityRequired: false,
      shareKVBlobs: true
    )
    let personalization = TurboQuantPersonalizationPolicy(
      personalizationEnabled: true,
      killSwitchEnabled: false,
      evidenceRequired: false,
      deleteOnDataErasure: false
    )
    let policy = TurboQuantPlatformUnlockPolicy(
      adaptivePrecision: adaptive,
      memoryPlane: memory,
      openKVFormat: openKV,
      deviceMesh: deviceMesh,
      personalization: personalization
    )

    #expect(
      policy.validationErrors.contains("active adaptive precision requires compatibilityPairID"))
    #expect(
      policy.validationErrors.contains("active open KV format requires turboQuantLayoutVersion"))
    #expect(policy.validationErrors.contains("active open KV format requires encryption"))
    #expect(
      policy.validationErrors.contains("active open KV format must remain local-only by default"))
    #expect(policy.validationErrors.contains("support export must not include KV blobs by default"))
    #expect(policy.validationErrors.contains("memory plane must be local-only by default"))
    #expect(policy.validationErrors.contains("memory plane cloud export requires approval"))
    #expect(policy.validationErrors.contains("active device mesh requires encrypted LAN sync"))
    #expect(policy.validationErrors.contains("active device mesh must be local-network only"))
    #expect(policy.validationErrors.contains("active device mesh requires peer identity"))
    #expect(policy.validationErrors.contains("device mesh must not share KV blobs in Wave 7"))
    #expect(
      policy.validationErrors.contains("active personalization must delete state on data erasure"))
  }

  @Test func platformAdmissionBudgetContributesToMemoryZones() {
    let budget = TurboQuantPlatformUnlockAdmissionBudget(
      enabled: true,
      adaptivePrecisionMetadataBytes: 10,
      semanticMemoryBytes: 20,
      multimodalMemoryBytes: 30,
      agentWorkingMemoryBytes: 40,
      openKVFormatMetadataBytes: 50,
      deviceMeshSyncBytes: 60,
      personalizationAdapterBytes: 70
    )
    let request = Self.admissionRequest(platformUnlockBudget: budget)

    let plan = LocalRuntimeAdmissionService().admit(request)

    #expect(plan.platformUnlockBudget == budget)
    #expect(plan.memoryZones.adaptivePrecisionMetadataBytes == 10)
    #expect(plan.memoryZones.semanticMemoryBytes == 20)
    #expect(plan.memoryZones.multimodalMemoryBytes == 30)
    #expect(plan.memoryZones.agentWorkingMemoryBytes == 40)
    #expect(plan.memoryZones.openKVFormatMetadataBytes == 50)
    #expect(plan.memoryZones.deviceMeshSyncBytes == 60)
    #expect(plan.memoryZones.personalizationAdapterBytes == 70)
    #expect(plan.memoryZones.totalPlannedBytes >= budget.totalReserveBytes)
    #expect(plan.memoryZones.totalMatchesZones)
  }

  @Test func runDecisionCarriesPlatformPolicyValidation() {
    let invalidPolicy = TurboQuantPlatformUnlockPolicy(
      adaptivePrecision: TurboQuantAdaptivePrecisionPolicy(
        enabled: true,
        killSwitchEnabled: false,
        evidenceRequired: false,
        compatibilityPairID: nil
      )
    )
    let decision = TurboQuantRunDecision(platformUnlockPolicy: invalidPolicy)

    #expect(
      decision.validationErrors.contains("active adaptive precision requires compatibilityPairID"))
  }

  @Test func verifiedEvidenceRequiresExplicitPlatformPolicyOptIn() throws {
    var report = Self.report(platformDimensions: Self.platformDimensions())

    #expect(
      throws: TurboQuantBenchmarkImportFailure.platformGateFailed(
        "Platform unlock evidence import is disabled by policy.")
    ) {
      _ = try TurboQuantBenchmarkImporter().importReport(
        report, policy: Self.verifiedPolicy(allowPlatformUnlockEvidence: false))
    }

    let imported = try TurboQuantBenchmarkImporter().importReport(
      report,
      policy: Self.verifiedPolicy(allowPlatformUnlockEvidence: true)
    )

    #expect(imported.evidence.evidenceLevel == .verified)
    #expect(imported.evidence.platformEvidenceDimensions == Self.platformDimensions())

    report.runtime.platformEvidenceDimensions = .disabled
    let disabled = try TurboQuantBenchmarkImporter().importReport(
      report,
      policy: Self.verifiedPolicy(allowPlatformUnlockEvidence: false)
    )
    #expect(disabled.evidence.platformEvidenceDimensions == .disabled)
  }

  @Test func profileEvidenceStoreMatchesPlatformTupleExactly() async throws {
    let report = Self.report(platformDimensions: Self.platformDimensions())
    let store = ProfileEvidenceStore()
    let imported = try await store.importBenchmarkReport(
      report,
      policy: Self.verifiedPolicy(allowPlatformUnlockEvidence: true)
    )

    let found = await store.evidence(
      modelID: report.model.id,
      modelRevision: report.model.revision,
      tokenizerHash: report.model.tokenizerHash,
      profileHash: report.model.profileHash,
      compatibilityPairID: report.compatibilityPairID,
      deviceClass: report.device.deviceClass,
      hardwareModel: report.device.hardwareModel,
      osBuild: report.device.osBuild,
      mode: report.runtime.userMode,
      fallbackContractHash: report.runtime.fallbackContractHash,
      layoutVersion: report.runtime.layoutVersion,
      speculativeDimensions: report.runtime.speculativeDimensions,
      platformEvidenceDimensions: Self.platformDimensions(),
      minimumContextTokens: report.runtime.admittedContextTokens
    )
    let disabledPlatform = await store.evidence(
      modelID: report.model.id,
      modelRevision: report.model.revision,
      tokenizerHash: report.model.tokenizerHash,
      profileHash: report.model.profileHash,
      compatibilityPairID: report.compatibilityPairID,
      deviceClass: report.device.deviceClass,
      hardwareModel: report.device.hardwareModel,
      osBuild: report.device.osBuild,
      mode: report.runtime.userMode,
      fallbackContractHash: report.runtime.fallbackContractHash,
      layoutVersion: report.runtime.layoutVersion,
      speculativeDimensions: report.runtime.speculativeDimensions,
      platformEvidenceDimensions: .disabled,
      minimumContextTokens: report.runtime.admittedContextTokens
    )

    #expect(found?.id == imported.evidence.id)
    #expect(disabledPlatform == nil)
  }

  private static func platformDimensions() -> TurboQuantPlatformEvidenceDimensions {
    TurboQuantPlatformEvidenceDimensions(
      activeFeatureIDs: [.adaptivePrecision, .openKVFormat],
      adaptivePrecisionPolicyID: "adaptive-v1",
      adaptivePrecisionPolicyHash: "adaptive-hash",
      openKVFormatName: "pines.turboquant.open-kv",
      openKVFormatVersion: 1,
      openKVFormatHash: "open-kv-hash"
    )
  }

  private static func report(platformDimensions: TurboQuantPlatformEvidenceDimensions)
    -> TurboQuantBenchmarkReport
  {
    let fallbackContract = TurboQuantFallbackContract.productDefault(for: .balanced)
    return TurboQuantBenchmarkReport(
      compatibilityPairID: "pair-wave7",
      producer: SchemaProducer(repo: "pines-tests", commit: "test"),
      device: TurboQuantBenchmarkDevice(
        deviceClass: .a17Pro,
        hardwareModel: "iPhone16,2",
        osBuild: "23F",
        availableMemoryBytesAtStart: 3_000_000_000,
        metalDeviceName: "Apple GPU",
        thermalState: "nominal"
      ),
      model: TurboQuantBenchmarkModel(
        id: "model",
        revision: "rev",
        tokenizerHash: "tok",
        profileHash: "profile",
        architecture: "qwen",
        layers: 24,
        kvHeads: 8,
        headDim: 128
      ),
      runtime: TurboQuantBenchmarkRuntime(
        userMode: .balanced,
        fallbackContractHash: fallbackContract.contractHash,
        preset: "turbo4v2",
        valueBits: 4,
        groupSize: 64,
        layoutVersion: 4,
        attentionPath: .twoStageCompressed,
        kernelProfile: "fast",
        speculativeDimensions: .disabled,
        platformEvidenceDimensions: platformDimensions,
        admittedContextTokens: 4096,
        reservedCompletionTokens: 512
      ),
      metrics: TurboQuantBenchmarkMetrics(
        contextTokens: 4096,
        firstTokenLatencyMS: 70,
        prefillTokensPerSecond: 900,
        decodeTokensPerSecondP50: 24,
        decodeTokensPerSecondP95: 21,
        peakMemoryBytes: 2_100_000_000,
        compressedKVBytes: 128_000_000,
        memoryWarningsSeen: 0,
        fallbackUsed: false,
        jetsamObserved: false
      ),
      qualityGate: TurboQuantQualityGate(
        benchmarkSuiteID: .mobileMemoryAcceptanceV1,
        deterministicTop1MatchRate: 0.99,
        logitKLDivergenceMean: 0.01,
        logitMaxAbsErrorP95: 0.1,
        noNaNOrInf: true,
        fallbackEquivalent: true,
        prefillExact: true,
        passed: true
      )
    )
  }

  private static func verifiedPolicy(allowPlatformUnlockEvidence: Bool)
    -> TurboQuantBenchmarkImportPolicy
  {
    let report = Self.report(platformDimensions: Self.platformDimensions())
    return TurboQuantBenchmarkImportPolicy(
      acceptedCompatibilityPairIDs: [report.compatibilityPairID],
      acceptedFallbackContractHashes: [report.runtime.fallbackContractHash],
      acceptedLayoutVersions: [report.runtime.layoutVersion ?? 0],
      requestedEvidenceLevel: .verified,
      allowVerifiedEvidence: true,
      allowPlatformUnlockEvidence: allowPlatformUnlockEvidence
    )
  }

  private static func admissionRequest(
    platformUnlockBudget: TurboQuantPlatformUnlockAdmissionBudget
  ) -> LocalRuntimeAdmissionRequest {
    LocalRuntimeAdmissionRequest(
      modelID: "test-model",
      requestedContextTokens: 1024,
      reservedCompletionTokens: 128,
      userMode: .balanced,
      fallbackContract: .productDefault(for: .balanced),
      deviceClass: .a17Pro,
      osBuild: "test",
      memoryCounters: RuntimeMemoryCounters(
        availableMemoryBytes: 2_000 * 1_024 * 1_024,
        processResidentMemoryBytes: 128 * 1_024 * 1_024
      ),
      quantizationDiagnostics: RuntimeQuantizationDiagnostics(
        activeAttentionPath: .twoStageCompressed
      ),
      estimatedModelWeightsBytes: 100,
      compressedKVBytesPerToken: 10,
      rawShadowBytes: 0,
      packedFallbackBytesPerToken: 0,
      decodedFallbackScratchBytes: 0,
      promptBufferBytes: 0,
      metalScratchReserveBytes: 0,
      uiReserveBytes: 0,
      platformUnlockBudget: platformUnlockBudget
    )
  }
}
