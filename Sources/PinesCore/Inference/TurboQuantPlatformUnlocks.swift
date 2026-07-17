import Foundation

public enum TurboQuantPrecisionSegmentRole: String, Codable, Sendable, CaseIterable {
  case defaultContext
  case pinnedPrompt
  case liveRecent
  case retrievedEvidence
  case summary
  case toolState
  case agentScratch
  case audioTranscript
  case imageMemory
  case kvSnapshotReference

  public var displayName: String {
    switch self {
    case .defaultContext:
      "Default context"
    case .pinnedPrompt:
      "Pinned prompt"
    case .liveRecent:
      "Live recent"
    case .retrievedEvidence:
      "Retrieved evidence"
    case .summary:
      "Summary"
    case .toolState:
      "Tool state"
    case .agentScratch:
      "Agent scratch"
    case .audioTranscript:
      "Audio transcript"
    case .imageMemory:
      "Image memory"
    case .kvSnapshotReference:
      "KV snapshot reference"
    }
  }
}

public struct TurboQuantPrecisionSegment: Hashable, Codable, Sendable, Identifiable {
  public var id: UUID
  public var role: TurboQuantPrecisionSegmentRole
  public var tokenStart: Int
  public var tokenCount: Int
  public var keyBits: Int
  public var valueBits: Int
  public var priority: Double
  public var reason: String

  public var tokenEnd: Int {
    tokenStart + tokenCount
  }

  public var validationErrors: [String] {
    var errors: [String] = []
    if tokenStart < 0 {
      errors.append("precision segment tokenStart must be nonnegative")
    }
    if tokenCount <= 0 {
      errors.append("precision segment tokenCount must be positive")
    }
    if keyBits <= 0 || valueBits <= 0 {
      errors.append("precision segment bits must be positive")
    }
    if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.append("precision segment requires reason")
    }
    return errors
  }

  public init(
    id: UUID = UUID(),
    role: TurboQuantPrecisionSegmentRole,
    tokenStart: Int,
    tokenCount: Int,
    keyBits: Int,
    valueBits: Int,
    priority: Double = 0,
    reason: String
  ) {
    self.id = id
    self.role = role
    self.tokenStart = max(0, tokenStart)
    self.tokenCount = max(0, tokenCount)
    self.keyBits = max(0, keyBits)
    self.valueBits = max(0, valueBits)
    self.priority = min(1, max(0, priority))
    self.reason = reason
  }
}

public struct TurboQuantLayerSensitivity: Hashable, Codable, Sendable, Identifiable {
  public var id: String { "\(layerIndex):\(role.rawValue)" }
  public var layerIndex: Int
  public var role: TurboQuantPrecisionSegmentRole
  public var sensitivityScore: Double
  public var recommendedKeyBits: Int
  public var recommendedValueBits: Int

  public init(
    layerIndex: Int,
    role: TurboQuantPrecisionSegmentRole,
    sensitivityScore: Double,
    recommendedKeyBits: Int,
    recommendedValueBits: Int
  ) {
    self.layerIndex = max(0, layerIndex)
    self.role = role
    self.sensitivityScore = min(1, max(0, sensitivityScore))
    self.recommendedKeyBits = max(0, recommendedKeyBits)
    self.recommendedValueBits = max(0, recommendedValueBits)
  }
}

public struct TurboQuantHeadSensitivity: Hashable, Codable, Sendable, Identifiable {
  public var id: String { "\(layerIndex):\(headIndex):\(role.rawValue)" }
  public var layerIndex: Int
  public var headIndex: Int
  public var role: TurboQuantPrecisionSegmentRole
  public var sensitivityScore: Double
  public var recommendedKeyBits: Int
  public var recommendedValueBits: Int

  public init(
    layerIndex: Int,
    headIndex: Int,
    role: TurboQuantPrecisionSegmentRole,
    sensitivityScore: Double,
    recommendedKeyBits: Int,
    recommendedValueBits: Int
  ) {
    self.layerIndex = max(0, layerIndex)
    self.headIndex = max(0, headIndex)
    self.role = role
    self.sensitivityScore = min(1, max(0, sensitivityScore))
    self.recommendedKeyBits = max(0, recommendedKeyBits)
    self.recommendedValueBits = max(0, recommendedValueBits)
  }
}

public struct TurboQuantAdaptivePrecisionPolicy: Hashable, Codable, Sendable {
  public static let schemaVersion = 1

  public var schemaVersion: Int
  public var enabled: Bool
  public var killSwitchEnabled: Bool
  public var evidenceRequired: Bool
  public var policyID: String?
  public var compatibilityPairID: String?
  public var baseKeyBits: Int
  public var baseValueBits: Int
  public var highPrecisionKeyBits: Int
  public var highPrecisionValueBits: Int
  public var deterministicSelectionSeed: UInt64
  public var segmentPolicy: [TurboQuantPrecisionSegment]
  public var layerSensitivity: [TurboQuantLayerSensitivity]
  public var headSensitivity: [TurboQuantHeadSensitivity]

  public var isProductActive: Bool {
    enabled && !killSwitchEnabled && !evidenceRequired
  }

  public var validationErrors: [String] {
    var errors: [String] = []
    if isProductActive, compatibilityPairID?.isEmpty != false {
      errors.append("active adaptive precision requires compatibilityPairID")
    }
    if baseKeyBits <= 0 || baseValueBits <= 0 {
      errors.append("adaptive precision base bits must be positive")
    }
    if highPrecisionKeyBits < baseKeyBits || highPrecisionValueBits < baseValueBits {
      errors.append("adaptive high precision bits must be >= base bits")
    }
    for segment in segmentPolicy {
      errors.append(contentsOf: segment.validationErrors)
    }
    return errors
  }

  public init(
    schemaVersion: Int = Self.schemaVersion,
    enabled: Bool = false,
    killSwitchEnabled: Bool = true,
    evidenceRequired: Bool = true,
    policyID: String? = nil,
    compatibilityPairID: String? = nil,
    baseKeyBits: Int = 4,
    baseValueBits: Int = 4,
    highPrecisionKeyBits: Int = 8,
    highPrecisionValueBits: Int = 8,
    deterministicSelectionSeed: UInt64 = 0,
    segmentPolicy: [TurboQuantPrecisionSegment] = [],
    layerSensitivity: [TurboQuantLayerSensitivity] = [],
    headSensitivity: [TurboQuantHeadSensitivity] = []
  ) {
    self.schemaVersion = schemaVersion
    self.enabled = enabled
    self.killSwitchEnabled = killSwitchEnabled
    self.evidenceRequired = evidenceRequired
    self.policyID = policyID
    self.compatibilityPairID = compatibilityPairID
    self.baseKeyBits = max(0, baseKeyBits)
    self.baseValueBits = max(0, baseValueBits)
    self.highPrecisionKeyBits = max(0, highPrecisionKeyBits)
    self.highPrecisionValueBits = max(0, highPrecisionValueBits)
    self.deterministicSelectionSeed = deterministicSelectionSeed
    self.segmentPolicy = segmentPolicy
    self.layerSensitivity = layerSensitivity
    self.headSensitivity = headSensitivity
  }

  public static let disabled = Self()
}

public enum TurboQuantOpenKVContainer: String, Codable, Sendable, CaseIterable {
  case inMemory
  case encryptedLocalBlob
  case safetensors
  case externalConverter
}

public struct TurboQuantOpenKVIdentityPolicy: Hashable, Codable, Sendable {
  public var requireModelID: Bool
  public var requireModelRevision: Bool
  public var requireTokenizerHash: Bool
  public var requireProfileHash: Bool
  public var requireRopeHash: Bool
  public var requirePrefixHash: Bool
  public var requireFallbackContractHash: Bool

  public init(
    requireModelID: Bool = true,
    requireModelRevision: Bool = true,
    requireTokenizerHash: Bool = true,
    requireProfileHash: Bool = true,
    requireRopeHash: Bool = true,
    requirePrefixHash: Bool = true,
    requireFallbackContractHash: Bool = true
  ) {
    self.requireModelID = requireModelID
    self.requireModelRevision = requireModelRevision
    self.requireTokenizerHash = requireTokenizerHash
    self.requireProfileHash = requireProfileHash
    self.requireRopeHash = requireRopeHash
    self.requirePrefixHash = requirePrefixHash
    self.requireFallbackContractHash = requireFallbackContractHash
  }

  public static let failClosed = Self()
}

public struct TurboQuantOpenKVFormatDescriptor: Hashable, Codable, Sendable {
  public static let schemaVersion = 1

  public var schemaVersion: Int
  public var enabled: Bool
  public var killSwitchEnabled: Bool
  public var evidenceRequired: Bool
  public var formatName: String
  public var formatVersion: Int
  public var container: TurboQuantOpenKVContainer
  public var turboQuantLayoutVersion: Int?
  public var tensorEncoding: String
  public var metadataSchemaVersion: Int
  public var identityPolicy: TurboQuantOpenKVIdentityPolicy
  public var localOnlyByDefault: Bool
  public var encryptionRequired: Bool
  public var supportExportIncludesBlobs: Bool
  public var externalConverterID: String?

  public var isProductActive: Bool {
    enabled && !killSwitchEnabled && !evidenceRequired
  }

  public var validationErrors: [String] {
    var errors: [String] = []
    if isProductActive, turboQuantLayoutVersion == nil {
      errors.append("active open KV format requires turboQuantLayoutVersion")
    }
    if isProductActive, !encryptionRequired {
      errors.append("active open KV format requires encryption")
    }
    if isProductActive, !localOnlyByDefault {
      errors.append("active open KV format must remain local-only by default")
    }
    if container == .externalConverter, externalConverterID?.isEmpty != false {
      errors.append("external converter open KV format requires externalConverterID")
    }
    if supportExportIncludesBlobs {
      errors.append("support export must not include KV blobs by default")
    }
    return errors
  }

  public init(
    schemaVersion: Int = Self.schemaVersion,
    enabled: Bool = false,
    killSwitchEnabled: Bool = true,
    evidenceRequired: Bool = true,
    formatName: String = "pines.turboquant.open-kv",
    formatVersion: Int = 1,
    container: TurboQuantOpenKVContainer = .encryptedLocalBlob,
    turboQuantLayoutVersion: Int? = nil,
    tensorEncoding: String = "compressed-pages",
    metadataSchemaVersion: Int = 1,
    identityPolicy: TurboQuantOpenKVIdentityPolicy = .failClosed,
    localOnlyByDefault: Bool = true,
    encryptionRequired: Bool = true,
    supportExportIncludesBlobs: Bool = false,
    externalConverterID: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.enabled = enabled
    self.killSwitchEnabled = killSwitchEnabled
    self.evidenceRequired = evidenceRequired
    self.formatName = formatName
    self.formatVersion = max(1, formatVersion)
    self.container = container
    self.turboQuantLayoutVersion = turboQuantLayoutVersion
    self.tensorEncoding = tensorEncoding
    self.metadataSchemaVersion = max(1, metadataSchemaVersion)
    self.identityPolicy = identityPolicy
    self.localOnlyByDefault = localOnlyByDefault
    self.encryptionRequired = encryptionRequired
    self.supportExportIncludesBlobs = supportExportIncludesBlobs
    self.externalConverterID = externalConverterID
  }

  public static let disabled = Self()
}

public struct TurboQuantMemoryPlanePolicy: Hashable, Codable, Sendable {
  public static let schemaVersion = 1

  public var schemaVersion: Int
  public var semanticMemoryEnabled: Bool
  public var userFactStoreEnabled: Bool
  public var multimodalMemoryEnabled: Bool
  public var audioTranscriptMemoryEnabled: Bool
  public var imageMemoryEnabled: Bool
  public var localAgentMemoryEnabled: Bool
  public var toolStatePinningEnabled: Bool
  public var killSwitchEnabled: Bool
  public var evidenceRequired: Bool
  public var localOnlyByDefault: Bool
  public var cloudExportRequiresApproval: Bool
  public var semanticMemoryBytes: Int64
  public var multimodalMemoryBytes: Int64
  public var agentWorkingMemoryBytes: Int64

  public var hasEnabledFeature: Bool {
    semanticMemoryEnabled
      || userFactStoreEnabled
      || multimodalMemoryEnabled
      || audioTranscriptMemoryEnabled
      || imageMemoryEnabled
      || localAgentMemoryEnabled
      || toolStatePinningEnabled
  }

  public var isProductActive: Bool {
    hasEnabledFeature && !killSwitchEnabled && !evidenceRequired
  }

  public var validationErrors: [String] {
    var errors: [String] = []
    if isProductActive, !localOnlyByDefault {
      errors.append("memory plane must be local-only by default")
    }
    if isProductActive, !cloudExportRequiresApproval {
      errors.append("memory plane cloud export requires approval")
    }
    return errors
  }

  public init(
    schemaVersion: Int = Self.schemaVersion,
    semanticMemoryEnabled: Bool = false,
    userFactStoreEnabled: Bool = false,
    multimodalMemoryEnabled: Bool = false,
    audioTranscriptMemoryEnabled: Bool = false,
    imageMemoryEnabled: Bool = false,
    localAgentMemoryEnabled: Bool = false,
    toolStatePinningEnabled: Bool = false,
    killSwitchEnabled: Bool = true,
    evidenceRequired: Bool = true,
    localOnlyByDefault: Bool = true,
    cloudExportRequiresApproval: Bool = true,
    semanticMemoryBytes: Int64 = 0,
    multimodalMemoryBytes: Int64 = 0,
    agentWorkingMemoryBytes: Int64 = 0
  ) {
    self.schemaVersion = schemaVersion
    self.semanticMemoryEnabled = semanticMemoryEnabled
    self.userFactStoreEnabled = userFactStoreEnabled
    self.multimodalMemoryEnabled = multimodalMemoryEnabled
    self.audioTranscriptMemoryEnabled = audioTranscriptMemoryEnabled
    self.imageMemoryEnabled = imageMemoryEnabled
    self.localAgentMemoryEnabled = localAgentMemoryEnabled
    self.toolStatePinningEnabled = toolStatePinningEnabled
    self.killSwitchEnabled = killSwitchEnabled
    self.evidenceRequired = evidenceRequired
    self.localOnlyByDefault = localOnlyByDefault
    self.cloudExportRequiresApproval = cloudExportRequiresApproval
    self.semanticMemoryBytes = max(0, semanticMemoryBytes)
    self.multimodalMemoryBytes = max(0, multimodalMemoryBytes)
    self.agentWorkingMemoryBytes = max(0, agentWorkingMemoryBytes)
  }

  public static let disabled = Self()
}

public struct TurboQuantDeviceMeshPolicy: Hashable, Codable, Sendable {
  public static let schemaVersion = 1

  public var schemaVersion: Int
  public var enabled: Bool
  public var encryptedLANSyncEnabled: Bool
  public var killSwitchEnabled: Bool
  public var evidenceRequired: Bool
  public var localNetworkOnly: Bool
  public var peerIdentityRequired: Bool
  public var shareKVBlobs: Bool
  public var syncReserveBytes: Int64

  public var isProductActive: Bool {
    enabled && !killSwitchEnabled && !evidenceRequired
  }

  public var validationErrors: [String] {
    var errors: [String] = []
    if isProductActive, !encryptedLANSyncEnabled {
      errors.append("active device mesh requires encrypted LAN sync")
    }
    if isProductActive, !localNetworkOnly {
      errors.append("active device mesh must be local-network only")
    }
    if isProductActive, !peerIdentityRequired {
      errors.append("active device mesh requires peer identity")
    }
    if shareKVBlobs {
      errors.append("device mesh must not share KV blobs in Wave 7")
    }
    return errors
  }

  public init(
    schemaVersion: Int = Self.schemaVersion,
    enabled: Bool = false,
    encryptedLANSyncEnabled: Bool = false,
    killSwitchEnabled: Bool = true,
    evidenceRequired: Bool = true,
    localNetworkOnly: Bool = true,
    peerIdentityRequired: Bool = true,
    shareKVBlobs: Bool = false,
    syncReserveBytes: Int64 = 0
  ) {
    self.schemaVersion = schemaVersion
    self.enabled = enabled
    self.encryptedLANSyncEnabled = encryptedLANSyncEnabled
    self.killSwitchEnabled = killSwitchEnabled
    self.evidenceRequired = evidenceRequired
    self.localNetworkOnly = localNetworkOnly
    self.peerIdentityRequired = peerIdentityRequired
    self.shareKVBlobs = shareKVBlobs
    self.syncReserveBytes = max(0, syncReserveBytes)
  }

  public static let disabled = Self()
}

public struct TurboQuantPersonalizationPolicy: Hashable, Codable, Sendable {
  public static let schemaVersion = 1

  public var schemaVersion: Int
  public var personalizationEnabled: Bool
  public var localAdaptersEnabled: Bool
  public var killSwitchEnabled: Bool
  public var evidenceRequired: Bool
  public var adapterStateBytes: Int64
  public var deleteOnDataErasure: Bool

  public var isProductActive: Bool {
    (personalizationEnabled || localAdaptersEnabled) && !killSwitchEnabled && !evidenceRequired
  }

  public var validationErrors: [String] {
    var errors: [String] = []
    if isProductActive, !deleteOnDataErasure {
      errors.append("active personalization must delete state on data erasure")
    }
    return errors
  }

  public init(
    schemaVersion: Int = Self.schemaVersion,
    personalizationEnabled: Bool = false,
    localAdaptersEnabled: Bool = false,
    killSwitchEnabled: Bool = true,
    evidenceRequired: Bool = true,
    adapterStateBytes: Int64 = 0,
    deleteOnDataErasure: Bool = true
  ) {
    self.schemaVersion = schemaVersion
    self.personalizationEnabled = personalizationEnabled
    self.localAdaptersEnabled = localAdaptersEnabled
    self.killSwitchEnabled = killSwitchEnabled
    self.evidenceRequired = evidenceRequired
    self.adapterStateBytes = max(0, adapterStateBytes)
    self.deleteOnDataErasure = deleteOnDataErasure
  }

  public static let disabled = Self()
}

public struct TurboQuantPlatformUnlockAdmissionBudget: Hashable, Codable, Sendable {
  public static let schemaVersion = 1

  public var schemaVersion: Int
  public var enabled: Bool
  public var adaptivePrecisionMetadataBytes: Int64
  public var semanticMemoryBytes: Int64
  public var multimodalMemoryBytes: Int64
  public var agentWorkingMemoryBytes: Int64
  public var openKVFormatMetadataBytes: Int64
  public var deviceMeshSyncBytes: Int64
  public var personalizationAdapterBytes: Int64

  public var totalReserveBytes: Int64 {
    guard enabled else { return 0 }
    return adaptivePrecisionMetadataBytes
      + semanticMemoryBytes
      + multimodalMemoryBytes
      + agentWorkingMemoryBytes
      + openKVFormatMetadataBytes
      + deviceMeshSyncBytes
      + personalizationAdapterBytes
  }

  public init(
    schemaVersion: Int = Self.schemaVersion,
    enabled: Bool = false,
    adaptivePrecisionMetadataBytes: Int64 = 0,
    semanticMemoryBytes: Int64 = 0,
    multimodalMemoryBytes: Int64 = 0,
    agentWorkingMemoryBytes: Int64 = 0,
    openKVFormatMetadataBytes: Int64 = 0,
    deviceMeshSyncBytes: Int64 = 0,
    personalizationAdapterBytes: Int64 = 0
  ) {
    self.schemaVersion = schemaVersion
    self.enabled = enabled
    self.adaptivePrecisionMetadataBytes = max(0, adaptivePrecisionMetadataBytes)
    self.semanticMemoryBytes = max(0, semanticMemoryBytes)
    self.multimodalMemoryBytes = max(0, multimodalMemoryBytes)
    self.agentWorkingMemoryBytes = max(0, agentWorkingMemoryBytes)
    self.openKVFormatMetadataBytes = max(0, openKVFormatMetadataBytes)
    self.deviceMeshSyncBytes = max(0, deviceMeshSyncBytes)
    self.personalizationAdapterBytes = max(0, personalizationAdapterBytes)
  }

  public static let disabled = Self()
}

public struct TurboQuantPlatformEvidenceDimensions: Hashable, Codable, Sendable {
  public static let schemaVersion = 1

  public var schemaVersion: Int
  public var activeFeatureIDs: [TurboQuantPlatformFeatureID]
  public var adaptivePrecisionPolicyID: String?
  public var adaptivePrecisionPolicyHash: String?
  public var openKVFormatName: String?
  public var openKVFormatVersion: Int?
  public var openKVFormatHash: String?
  public var semanticMemoryPolicyHash: String?
  public var multimodalMemoryPolicyHash: String?
  public var agentMemoryPolicyHash: String?
  public var deviceMeshPolicyHash: String?
  public var personalizationPolicyHash: String?

  public var isDisabled: Bool {
    activeFeatureIDs.isEmpty
      && adaptivePrecisionPolicyID == nil
      && adaptivePrecisionPolicyHash == nil
      && openKVFormatHash == nil
      && semanticMemoryPolicyHash == nil
      && multimodalMemoryPolicyHash == nil
      && agentMemoryPolicyHash == nil
      && deviceMeshPolicyHash == nil
      && personalizationPolicyHash == nil
  }

  public init(
    schemaVersion: Int = Self.schemaVersion,
    activeFeatureIDs: [TurboQuantPlatformFeatureID] = [],
    adaptivePrecisionPolicyID: String? = nil,
    adaptivePrecisionPolicyHash: String? = nil,
    openKVFormatName: String? = nil,
    openKVFormatVersion: Int? = nil,
    openKVFormatHash: String? = nil,
    semanticMemoryPolicyHash: String? = nil,
    multimodalMemoryPolicyHash: String? = nil,
    agentMemoryPolicyHash: String? = nil,
    deviceMeshPolicyHash: String? = nil,
    personalizationPolicyHash: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.activeFeatureIDs = Array(Set(activeFeatureIDs)).sorted { $0.rawValue < $1.rawValue }
    self.adaptivePrecisionPolicyID = adaptivePrecisionPolicyID
    self.adaptivePrecisionPolicyHash = adaptivePrecisionPolicyHash
    self.openKVFormatName = openKVFormatName
    self.openKVFormatVersion = openKVFormatVersion
    self.openKVFormatHash = openKVFormatHash
    self.semanticMemoryPolicyHash = semanticMemoryPolicyHash
    self.multimodalMemoryPolicyHash = multimodalMemoryPolicyHash
    self.agentMemoryPolicyHash = agentMemoryPolicyHash
    self.deviceMeshPolicyHash = deviceMeshPolicyHash
    self.personalizationPolicyHash = personalizationPolicyHash
  }

  public static let disabled = Self()

  public func matches(_ requested: TurboQuantPlatformEvidenceDimensions?) -> Bool {
    let requested = requested ?? .disabled
    return self == requested
  }
}

public struct TurboQuantPlatformUnlockPolicy: Hashable, Codable, Sendable {
  public static let schemaVersion = 1

  public var schemaVersion: Int
  public var adaptivePrecision: TurboQuantAdaptivePrecisionPolicy
  public var memoryPlane: TurboQuantMemoryPlanePolicy
  public var openKVFormat: TurboQuantOpenKVFormatDescriptor
  public var deviceMesh: TurboQuantDeviceMeshPolicy
  public var personalization: TurboQuantPersonalizationPolicy
  public var featureGates: [TurboQuantPlatformFeatureGate]

  public var activeFeatureIDs: [TurboQuantPlatformFeatureID] {
    featureGates.filter(\.isProductActive).map(\.featureID)
  }

  public var validationErrors: [String] {
    var errors: [String] = []
    errors.append(contentsOf: adaptivePrecision.validationErrors)
    errors.append(contentsOf: memoryPlane.validationErrors)
    errors.append(contentsOf: openKVFormat.validationErrors)
    errors.append(contentsOf: deviceMesh.validationErrors)
    errors.append(contentsOf: personalization.validationErrors)

    let gatesByID = Dictionary(uniqueKeysWithValues: featureGates.map { ($0.featureID, $0) })
    func requireGate(_ featureID: TurboQuantPlatformFeatureID, when active: Bool) {
      guard active else { return }
      if gatesByID[featureID]?.isProductActive != true {
        errors.append("active \(featureID.rawValue) requires product-active feature gate")
      }
    }

    requireGate(.adaptivePrecision, when: adaptivePrecision.isProductActive)
    requireGate(
      .semanticMemory, when: memoryPlane.semanticMemoryEnabled && memoryPlane.isProductActive)
    requireGate(
      .userFactStore, when: memoryPlane.userFactStoreEnabled && memoryPlane.isProductActive)
    requireGate(
      .multimodalMemory, when: memoryPlane.multimodalMemoryEnabled && memoryPlane.isProductActive)
    requireGate(
      .audioTranscriptMemory,
      when: memoryPlane.audioTranscriptMemoryEnabled && memoryPlane.isProductActive)
    requireGate(.imageMemory, when: memoryPlane.imageMemoryEnabled && memoryPlane.isProductActive)
    requireGate(
      .agentWorkingMemory, when: memoryPlane.localAgentMemoryEnabled && memoryPlane.isProductActive)
    requireGate(
      .toolStatePinning, when: memoryPlane.toolStatePinningEnabled && memoryPlane.isProductActive)
    requireGate(.openKVFormat, when: openKVFormat.isProductActive)
    requireGate(.deviceMesh, when: deviceMesh.isProductActive)
    requireGate(
      .encryptedLANSync, when: deviceMesh.encryptedLANSyncEnabled && deviceMesh.isProductActive)
    requireGate(
      .personalizationAdapters,
      when: personalization.personalizationEnabled && personalization.isProductActive)
    requireGate(
      .localAdapters, when: personalization.localAdaptersEnabled && personalization.isProductActive)

    return errors
  }

  public init(
    schemaVersion: Int = Self.schemaVersion,
    adaptivePrecision: TurboQuantAdaptivePrecisionPolicy = .disabled,
    memoryPlane: TurboQuantMemoryPlanePolicy = .disabled,
    openKVFormat: TurboQuantOpenKVFormatDescriptor = .disabled,
    deviceMesh: TurboQuantDeviceMeshPolicy = .disabled,
    personalization: TurboQuantPersonalizationPolicy = .disabled,
    featureGates: [TurboQuantPlatformFeatureGate] = TurboQuantPlatformFeatureGate
      .wave7DisabledDefaults
  ) {
    self.schemaVersion = schemaVersion
    self.adaptivePrecision = adaptivePrecision
    self.memoryPlane = memoryPlane
    self.openKVFormat = openKVFormat
    self.deviceMesh = deviceMesh
    self.personalization = personalization
    self.featureGates = featureGates
  }

  public static let disabled = Self()
}
