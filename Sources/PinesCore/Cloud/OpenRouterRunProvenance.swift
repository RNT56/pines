import Foundation

public struct OpenRouterRunProvenance: Hashable, Sendable {
    public struct RouteAttempt: Hashable, Codable, Sendable {
        public var provider: String?
        public var model: String?
        public var status: Int?

        public init(provider: String? = nil, model: String? = nil, status: Int? = nil) {
            self.provider = provider
            self.model = model
            self.status = status
        }
    }

    public var generationID: String?
    public var requestedModel: String?
    public var resolvedModel: String?
    public var selectedProvider: String?
    public var selectedModel: String?
    public var strategy: String?
    public var region: String?
    public var routeSummary: String?
    public var attempt: Int?
    public var attemptCount: Int?
    public var isBYOK: Bool?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var costCredits: Double?
    public var upstreamInferenceCost: Double?
    public var nativeFinishReason: String?
    public var serviceTier: String?
    public var routeAttempts: [RouteAttempt]

    public init?(metadata: [String: String]) {
        guard metadata[CloudProviderMetadataKeys.openRouterGenerationID] != nil
            || metadata[CloudProviderMetadataKeys.openRouterMetadataJSON] != nil
            || metadata[CloudProviderMetadataKeys.openRouterUsageJSON] != nil
        else { return nil }
        generationID = Self.clean(metadata[CloudProviderMetadataKeys.openRouterGenerationID])
        requestedModel = Self.clean(metadata[CloudProviderMetadataKeys.openRouterRequestedModel])
        resolvedModel = Self.clean(metadata[CloudProviderMetadataKeys.openRouterResolvedModel])
            ?? Self.clean(metadata[CloudProviderMetadataKeys.openAIModel])
        selectedProvider = Self.clean(metadata[CloudProviderMetadataKeys.openRouterSelectedProvider])
            ?? Self.clean(metadata[CloudProviderMetadataKeys.openRouterProvider])
        selectedModel = Self.clean(metadata[CloudProviderMetadataKeys.openRouterSelectedModel])
        strategy = Self.clean(metadata[CloudProviderMetadataKeys.openRouterStrategy])
        region = Self.clean(metadata[CloudProviderMetadataKeys.openRouterRegion])
        routeSummary = Self.clean(metadata[CloudProviderMetadataKeys.openRouterSummary])
        attempt = Self.nonnegativeInt(metadata[CloudProviderMetadataKeys.openRouterAttempt])
        attemptCount = Self.nonnegativeInt(metadata[CloudProviderMetadataKeys.openRouterAttemptCount])
        isBYOK = Self.bool(metadata[CloudProviderMetadataKeys.openRouterIsBYOK])
        promptTokens = Self.nonnegativeInt(metadata[CloudProviderMetadataKeys.openRouterPromptTokens])
        completionTokens = Self.nonnegativeInt(metadata[CloudProviderMetadataKeys.openRouterCompletionTokens])
        totalTokens = Self.nonnegativeInt(metadata[CloudProviderMetadataKeys.openRouterTotalTokens])
        costCredits = Self.nonnegativeDouble(metadata[CloudProviderMetadataKeys.openRouterCostCredits])
        upstreamInferenceCost = Self.nonnegativeDouble(
            metadata[CloudProviderMetadataKeys.openRouterUpstreamInferenceCost]
        )
        nativeFinishReason = Self.clean(metadata[CloudProviderMetadataKeys.openRouterNativeFinishReason])
        serviceTier = Self.clean(metadata[CloudProviderMetadataKeys.openRouterServiceTier])
        routeAttempts = Self.routeAttempts(metadata[CloudProviderMetadataKeys.openRouterAttemptsJSON])

        guard generationID != nil
            || requestedModel != nil
            || resolvedModel != nil
            || selectedProvider != nil
            || costCredits != nil
            || totalTokens != nil
        else { return nil }
    }

    public var model: String? {
        selectedModel ?? resolvedModel ?? requestedModel
    }

    public var effectiveAttemptCount: Int? {
        if let attemptCount, attemptCount > 0 { return attemptCount }
        return attempt
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonnegativeInt(_ value: String?) -> Int? {
        guard let value, let number = Int(value), number >= 0 else { return nil }
        return number
    }

    private static func nonnegativeDouble(_ value: String?) -> Double? {
        guard let value, let number = Double(value), number.isFinite, number >= 0 else { return nil }
        return number
    }

    private static func bool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }

    private static func routeAttempts(_ value: String?) -> [RouteAttempt] {
        guard let value, let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([RouteAttempt].self, from: data)) ?? []
    }
}
