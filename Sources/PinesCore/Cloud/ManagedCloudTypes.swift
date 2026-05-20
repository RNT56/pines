import Foundation

public enum CloudAccessMode: String, Hashable, Codable, Sendable, CaseIterable {
    case localOnly
    case byok
    case managedPro
    case managedProWithBYOKOverride

    public var usesManagedCloud: Bool {
        switch self {
        case .managedPro, .managedProWithBYOKOverride:
            return true
        case .localOnly, .byok:
            return false
        }
    }

    public var allowsBYOK: Bool {
        switch self {
        case .byok, .managedProWithBYOKOverride:
            return true
        case .localOnly, .managedPro:
            return false
        }
    }
}

public enum ProEntitlementStatus: String, Hashable, Codable, Sendable, CaseIterable {
    case inactive
    case active
    case expired
    case billingRetry
    case revoked

    public var enablesManagedCloud: Bool {
        self == .active || self == .billingRetry
    }
}

public enum ManagedCloudConsent: String, Hashable, Codable, Sendable, CaseIterable {
    case notAsked
    case optedIn
    case optedOut
    case revoked

    public var allowsManagedCloud: Bool {
        self == .optedIn
    }
}

public enum ManagedCloudFeature: String, Hashable, Codable, Sendable, CaseIterable {
    case chat
    case webSearch
    case tokenPreflight
    case embeddings
    case rerank
    case structuredExtraction
    case fileAnalysis
    case generatedMedia
    case transcription
    case deepResearch
    case backgroundJobs
    case cloudCopies
}

public struct ManagedCloudAvailability: Hashable, Codable, Sendable {
    public var entitlement: ProEntitlementStatus
    public var consent: ManagedCloudConsent
    public var gatewayConfigured: Bool
    public var supportedFeatures: Set<ManagedCloudFeature>

    public var isUsable: Bool {
        entitlement.enablesManagedCloud && consent.allowsManagedCloud && gatewayConfigured
    }

    public init(
        entitlement: ProEntitlementStatus = .inactive,
        consent: ManagedCloudConsent = .notAsked,
        gatewayConfigured: Bool = false,
        supportedFeatures: Set<ManagedCloudFeature> = []
    ) {
        self.entitlement = entitlement
        self.consent = consent
        self.gatewayConfigured = gatewayConfigured
        self.supportedFeatures = supportedFeatures
    }

    public func supports(_ feature: ManagedCloudFeature) -> Bool {
        isUsable && supportedFeatures.contains(feature)
    }
}

public enum ManagedCloudPolicy {
    public static let providerID = ProviderID(rawValue: "pines-managed-pro")
    public static let defaultModelID = ModelID(rawValue: "pines-pro-router")

    public static let defaultSupportedFeatures: Set<ManagedCloudFeature> = [
        .chat,
        .webSearch,
        .tokenPreflight,
        .embeddings,
        .rerank,
        .structuredExtraction,
        .fileAnalysis,
        .generatedMedia,
        .transcription,
        .deepResearch,
        .backgroundJobs,
        .cloudCopies,
    ]

    public static let defaultCapabilities = ProviderCapabilities(
        local: false,
        streaming: true,
        textGeneration: true,
        vision: true,
        imageInputs: true,
        audioInputs: true,
        audioOutputs: true,
        videoInputs: true,
        pdfInputs: true,
        textDocumentInputs: true,
        files: true,
        embeddings: true,
        toolCalling: true,
        hostedTools: true,
        jsonMode: true,
        structuredOutputs: true,
        contextCache: true,
        generatedImages: true,
        generatedAudio: true,
        generatedVideo: true,
        batch: true,
        tokenCounting: true,
        maxContextTokens: 1_000_000,
        maxOutputTokens: AppSettingsSnapshot.maxCompletionTokens
    )

    public static func managedCloudCanRun(
        entitlement: ProEntitlementStatus,
        consent: ManagedCloudConsent,
        gatewayConfigured: Bool
    ) -> Bool {
        ManagedCloudAvailability(
            entitlement: entitlement,
            consent: consent,
            gatewayConfigured: gatewayConfigured,
            supportedFeatures: defaultSupportedFeatures
        ).isUsable
    }

    public static func effectiveAccessMode(
        preferredMode: CloudAccessMode,
        entitlement: ProEntitlementStatus,
        consent: ManagedCloudConsent,
        gatewayConfigured: Bool
    ) -> CloudAccessMode {
        switch preferredMode {
        case .managedPro where !managedCloudCanRun(entitlement: entitlement, consent: consent, gatewayConfigured: gatewayConfigured),
             .managedProWithBYOKOverride where !managedCloudCanRun(entitlement: entitlement, consent: consent, gatewayConfigured: gatewayConfigured):
            return preferredMode.allowsBYOK ? .byok : .localOnly
        default:
            return preferredMode
        }
    }
}
