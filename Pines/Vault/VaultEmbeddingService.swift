import Foundation
import PinesCore

struct VaultEmbeddingService {
    let vaultRepository: any VaultRepository
    let modelInstallRepository: (any ModelInstallRepository)?
    let cloudProviderRepository: (any CloudProviderRepository)?
    let secretStore: any SecretStore
    let mlxRuntime: MLXRuntimeBridge
    let auditRepository: (any AuditEventRepository)?
    private let deviceMonitor = DeviceRuntimeMonitor()

    func refreshProfiles() async throws -> [VaultEmbeddingProfile] {
        let existing = try await vaultRepository.listEmbeddingProfiles()
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let candidates = try await candidateProfiles(existingByID: existingByID)
        let candidateIDs = Set(candidates.map(\.id))
        let hadActiveProfile = existing.contains(where: \.isActive)

        for candidate in candidates {
            var merged = candidate
            if let existing = existingByID[candidate.id] {
                merged.cloudConsentGranted = existing.cloudConsentGranted || candidate.cloudConsentGranted
                merged.isActive = existing.isActive
                merged.status = existing.status == .ready ? .ready : candidate.status
                merged.lastError = nil
                merged.embeddedChunkCount = existing.embeddedChunkCount
                merged.totalChunkCount = existing.totalChunkCount
                merged.createdAt = existing.createdAt
            }
            try await vaultRepository.upsertEmbeddingProfile(merged)
        }

        for stale in existing where !candidateIDs.contains(stale.id) {
            var updated = stale
            updated.isActive = false
            updated.status = .failed
            updated.lastError = stale.kind == .localMLX
                ? "The local embedding model is no longer installed."
                : "The cloud embedding credential or provider configuration is no longer available."
            updated.updatedAt = Date()
            try await vaultRepository.upsertEmbeddingProfile(updated)
        }

        if let active = try await vaultRepository.activeEmbeddingProfile(),
           !candidateIDs.contains(active.id) {
            try await vaultRepository.setActiveEmbeddingProfile(id: nil)
        }

        if !hadActiveProfile,
           try await vaultRepository.activeEmbeddingProfile() == nil,
           let local = candidates.first(where: { $0.kind == .localMLX }) {
            try await vaultRepository.setActiveEmbeddingProfile(id: local.id)
        }

        return try await vaultRepository.listEmbeddingProfiles()
    }

    func candidateProfiles(existingByID: [String: VaultEmbeddingProfile] = [:]) async throws -> [VaultEmbeddingProfile] {
        var profiles = [VaultEmbeddingProfile]()
        let installs = try await modelInstallRepository?.listInstalledAndCuratedModels() ?? []
        for install in installs where install.state == .installed && install.modalities.contains(.embeddings) {
            profiles.append(
                VaultEmbeddingProfile.local(
                    modelID: install.modelID,
                    displayName: install.displayName,
                    isActive: existingByID[VaultEmbeddingProfile.local(modelID: install.modelID, displayName: install.displayName).id]?.isActive ?? false
                )
            )
        }

        let providers = try await cloudProviderRepository?.listProviders() ?? []
        for provider in providers where provider.kind.supportsVaultEmbeddings {
            guard try await hasCredential(for: provider),
                  let profile = VaultEmbeddingProfile.cloud(
                    provider: provider,
                    consentGranted: existingByID[VaultEmbeddingProfile.cloud(provider: provider)?.id ?? ""]?.cloudConsentGranted ?? false
                  )
            else {
                continue
            }
            profiles.append(profile)
        }

        return profiles.sorted { lhs, rhs in
            if lhs.kind == .localMLX, rhs.kind != .localMLX { return true }
            if lhs.kind != .localMLX, rhs.kind == .localMLX { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func activeUsableProfile() async throws -> VaultEmbeddingProfile? {
        _ = try await refreshProfiles()
        guard let profile = try await vaultRepository.activeEmbeddingProfile(),
              profile.canUseWithoutPrompt
        else {
            return nil
        }
        return profile
    }

    func setActiveProfile(_ profile: VaultEmbeddingProfile, grantConsent: Bool = false) async throws -> VaultEmbeddingProfile {
        var updated = profile
        if grantConsent {
            updated.cloudConsentGranted = true
            updated.status = .available
        }
        updated.isActive = true
        updated.updatedAt = Date()
        try await vaultRepository.upsertEmbeddingProfile(updated)
        try await vaultRepository.setActiveEmbeddingProfile(id: updated.id)
        if grantConsent {
            try await vaultRepository.updateEmbeddingProfileConsent(id: updated.id, granted: true)
            try await auditRepository?.append(
                AuditEvent(
                    category: .security,
                    summary: "Enabled cloud vault embeddings for \(updated.displayName).",
                    providerID: updated.providerID,
                    modelID: updated.modelID
                )
            )
        }
        return try await vaultRepository.activeEmbeddingProfile() ?? updated
    }

    func embed(
        chunks: [VaultChunk],
        documentID: UUID,
        profile: VaultEmbeddingProfile,
        progress: (@Sendable (Int) async throws -> Void)? = nil
    ) async throws -> [VaultChunkEmbedding] {
        try await embed(inputs: chunks.map(\.text), profile: profile, inputType: .document, progress: progress)
            .enumerated()
            .map { index, vector in
                VaultChunkEmbedding(
                    chunkID: chunks[index].id,
                    documentID: documentID,
                    modelID: profile.modelID,
                    vector: vector
                )
            }
    }

    func embedQuery(_ query: String, profile: VaultEmbeddingProfile) async throws -> [Float]? {
        try await embed(inputs: [query], profile: profile, inputType: .query).first
    }

    private func embed(
        inputs: [String],
        profile: VaultEmbeddingProfile,
        inputType: EmbeddingInputType,
        progress: (@Sendable (Int) async throws -> Void)? = nil
    ) async throws -> [[Float]] {
        guard !inputs.isEmpty else { return [] }
        let batchSize = batchSize(for: profile)
        var vectors = [[Float]]()
        vectors.reserveCapacity(inputs.count)
        for startIndex in stride(from: 0, to: inputs.count, by: batchSize) {
            try Task.checkCancellation()
            let endIndex = min(startIndex + batchSize, inputs.count)
            let batch = Array(inputs[startIndex..<endIndex])
            let result = try await embedBatchWithRetry(batch, profile: profile, inputType: inputType)
            vectors.append(contentsOf: result.vectors)
            try await progress?(vectors.count)
        }
        return vectors
    }

    private func embedBatchWithRetry(
        _ batch: [String],
        profile: VaultEmbeddingProfile,
        inputType: EmbeddingInputType
    ) async throws -> EmbeddingResult {
        let request = EmbeddingRequest(
            modelID: profile.modelID,
            inputs: batch,
            normalize: profile.normalized,
            dimensions: profile.dimensions > 0 ? profile.dimensions : nil,
            inputType: inputType
        )
        var lastError: Error?
        let maxAttempts = profile.kind.isCloud ? 3 : 1
        for attempt in 1...maxAttempts {
            do {
                return try await provider(for: profile).embed(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < maxAttempts else { break }
                try await Task.sleep(nanoseconds: UInt64(attempt * attempt) * 350_000_000)
            }
        }
        throw lastError ?? InferenceError.invalidRequest("Embedding provider failed without an error.")
    }

    private func provider(for profile: VaultEmbeddingProfile) async throws -> any InferenceProvider {
        switch profile.kind {
        case .localMLX:
            return mlxRuntime
        case .openAI, .openAICompatible, .gemini, .openRouter, .voyageAI, .custom:
            guard let providerID = profile.providerID else {
                throw InferenceError.providerUnavailable(profile.providerID ?? ProviderID(rawValue: "cloud-embedding"))
            }
            let providers = try await cloudProviderRepository?.listProviders() ?? []
            guard let configuration = providers.first(where: { $0.id == providerID }) else {
                throw InferenceError.providerUnavailable(providerID)
            }
            return BYOKCloudInferenceProvider(configuration: configuration, secretStore: secretStore)
        }
    }

    private func batchSize(for profile: VaultEmbeddingProfile) -> Int {
        if profile.kind == .localMLX {
            return max(1, deviceMonitor.currentProfile().recommendedEmbeddingBatchSize)
        }
        switch profile.kind {
        case .gemini:
            return 100
        case .voyageAI:
            return 128
        case .openAI, .openAICompatible, .openRouter, .custom:
            return 128
        case .localMLX:
            return max(1, deviceMonitor.currentProfile().recommendedEmbeddingBatchSize)
        }
    }

    private func hasCredential(for provider: CloudProviderConfiguration) async throws -> Bool {
        let key = try await secretStore.read(service: provider.keychainService, account: provider.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false
    }
}

struct VaultRetrievalService {
    let vaultRepository: any VaultRepository
    let embeddingService: VaultEmbeddingService?
    let runtimeMetrics: PinesRuntimeMetrics

    func contextMessage(for query: String, limit: Int = 4) async -> (message: ChatMessage, documentIDs: [UUID])? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let startedAt = Date()
        var profile: VaultEmbeddingProfile?
        var queryEmbedding: [Float]?

        if let embeddingService,
           let activeProfile = try? await embeddingService.activeUsableProfile() {
            profile = activeProfile
            queryEmbedding = try? await embeddingService.embedQuery(query, profile: activeProfile)
        }

        guard let results = try? await vaultRepository.search(
            query: query,
            embedding: queryEmbedding,
            embeddingModelID: profile?.modelID,
            profileID: queryEmbedding == nil ? nil : profile?.id,
            limit: limit
        ) else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        runtimeMetrics.recordVaultRetrieval(resultCount: results.count, elapsedSeconds: elapsed)
        try? await vaultRepository.recordRetrievalEvent(
            VaultRetrievalEvent(
                profileID: queryEmbedding == nil ? nil : profile?.id,
                providerID: profile?.providerID,
                queryHash: StableVaultRetrievalHash.hexDigest(for: query),
                usedVectorSearch: queryEmbedding != nil,
                resultCount: results.count,
                elapsedSeconds: elapsed
            )
        )
        guard !results.isEmpty else { return nil }

        let context = results.enumerated().map { index, result in
            "[\(index + 1)] \(result.document.title): \(result.snippet)"
        }.joined(separator: "\n")
        return (
            ChatMessage(
                role: .system,
                content: """
                Use this private local vault context when it is relevant. Cite entries by bracket number.
                \(context)
                """
            ),
            results.map(\.document.id).uniqued()
        )
    }
}

private enum StableVaultRetrievalHash {
    static func hexDigest(for text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
