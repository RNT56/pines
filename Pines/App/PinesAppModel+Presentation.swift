import Foundation
import PinesCore

@MainActor
extension PinesAppModel {
    static func threadPreview(
        from record: ConversationRecord,
        messages: [ChatMessage],
        status: PinesThreadStatus? = nil,
        updatedAt: Date? = nil
    ) -> PinesThreadPreview {
        let messages = messages.filter { !$0.isContextOnly }
        let lastMessage = previewText(for: messages.last)
        return PinesThreadPreview(
            id: record.id,
            projectID: record.projectID,
            title: ConversationTitleDeriver.title(forStoredTitle: record.title, messages: messages),
            modelName: record.defaultModelID.map { friendlyModelName($0.rawValue) } ?? "No model selected",
            modelID: record.defaultModelID ?? ModelID(rawValue: "unselected-local-model"),
            providerID: record.defaultProviderID,
            lastMessage: lastMessage ?? "No messages yet.",
            messages: messages,
            status: record.archived ? .archived : (status ?? .local),
            isPinned: record.pinned,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: updatedAt ?? record.updatedAt),
            tokenCount: threadTokenCount(messages)
        )
    }

    static func localModelDisplayName(_ install: ModelInstall) -> String {
        friendlyModelName(install.displayName.isEmpty ? install.repository : install.displayName)
    }

    static func friendlyModelName(_ rawValue: String) -> String {
        var name = rawValue
            .replacingOccurrences(of: "mlx-community/", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "mlx-community", with: "", options: [.caseInsensitive])
        if name.contains("/") {
            name = name.split(separator: "/").last.map(String.init) ?? name
        }
        return name
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-/ ").union(.whitespacesAndNewlines))
    }

    static func threadPreview(from record: ConversationPreviewRecord) -> PinesThreadPreview {
        let lastMessage = record.lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let status: PinesThreadStatus = record.archived ? .archived : .local
        return PinesThreadPreview(
            id: record.id,
            projectID: record.projectID,
            title: ConversationTitleDeriver.title(forStoredTitle: record.title, titleSource: record.titleSourceMessage),
            modelName: record.defaultModelID.map { friendlyModelName($0.rawValue) } ?? "No model selected",
            modelID: record.defaultModelID ?? ModelID(rawValue: "unselected-local-model"),
            providerID: record.defaultProviderID,
            lastMessage: lastMessage?.isEmpty == false ? lastMessage! : "No messages yet.",
            messages: [],
            status: status,
            isPinned: record.pinned,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt),
            tokenCount: record.tokenCount
        )
    }

    static func threadPreview(
        from existing: PinesThreadPreview,
        messages: [ChatMessage],
        status: PinesThreadStatus? = nil,
        updatedAt: Date = Date()
    ) -> PinesThreadPreview {
        let messages = messages.filter { !$0.isContextOnly }
        let lastMessage = previewText(for: messages.last)
        let resolvedStatus = existing.status == .archived ? PinesThreadStatus.archived : (status ?? existing.status)
        return PinesThreadPreview(
            id: existing.id,
            projectID: existing.projectID,
            title: ConversationTitleDeriver.title(forStoredTitle: existing.title, messages: messages),
            modelName: existing.modelName,
            modelID: existing.modelID,
            providerID: existing.providerID,
            lastMessage: lastMessage ?? "No messages yet.",
            messages: messages,
            status: resolvedStatus,
            isPinned: existing.isPinned,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: updatedAt),
            tokenCount: resolvedStatus == .streaming ? existing.tokenCount : threadTokenCount(messages)
        )
    }

    static func projectPreview(from record: ProjectRecord) -> PinesProjectPreview {
        PinesProjectPreview(
            id: record.id,
            name: record.name,
            vaultEnabled: record.vaultEnabled,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt)
        )
    }

    static func threadTokenCount(_ messages: [ChatMessage]) -> Int {
        messages.lazy.filter { !$0.isContextOnly }.reduce(0) { $0 + max(1, $1.content.split(separator: " ").count) }
    }

    static func previewText(for message: ChatMessage?) -> String? {
        guard let message else { return nil }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        guard !message.attachments.isEmpty else { return nil }
        return message.attachments.count == 1
            ? "1 attachment"
            : "\(message.attachments.count) attachments"
    }

    nonisolated static func install(from summary: RemoteModelSummary, preflight: ModelPreflightResult) -> ModelInstall {
        return ModelInstall(
            modelID: ModelID(rawValue: summary.repository),
            displayName: summary.repository.components(separatedBy: "/").last ?? summary.repository,
            repository: summary.repository,
            modalities: preflight.modalities.isEmpty ? Self.modalities(from: summary) : preflight.modalities,
            verification: preflight.verification,
            state: preflight.verification == .unsupported ? .unsupported : .remote,
            parameterCount: preflight.parameterCount,
            estimatedBytes: preflight.estimatedBytes > 0 ? preflight.estimatedBytes : nil,
            license: preflight.license,
            modelType: preflight.modelType,
            textConfigModelType: preflight.textConfigModelType,
            processorClass: preflight.processorClass,
            keyHeadDimension: preflight.keyHeadDimension,
            valueHeadDimension: preflight.valueHeadDimension,
            routedExperts: preflight.routedExperts,
            expertsPerToken: preflight.expertsPerToken,
            cacheTopology: preflight.cacheTopology,
            turboQuantFamilySupport: preflight.turboQuantFamilySupport
        )
    }

    nonisolated static func modalities(from summary: RemoteModelSummary) -> Set<ModelModality> {
        if summary.tags.contains(where: { $0 == "feature-extraction" || $0 == "sentence-similarity" || $0 == "sentence-transformers" }) {
            return [.embeddings]
        }
        switch summary.task {
        case .imageTextToText:
            return [.text, .vision]
        case .featureExtraction, .sentenceSimilarity:
            return [.embeddings]
        case .textGeneration, .none:
            return [.text]
        }
    }

    nonisolated static func modelPreview(
        from install: ModelInstall,
        runtime: MLXRuntimeBridge,
        download: ModelDownloadProgress? = nil,
        profileEvidence: [RuntimeProfileEvidence] = [],
        enrichRuntime: Bool = true
    ) -> PinesModelPreview {
        let status: PinesModelStatus
        switch download?.status {
        case .queued, .downloading, .verifying, .installing:
            status = .indexing
        case .failed:
            status = .failed
        case .cancelled, .installed, .none:
            switch install.state {
            case .installed:
                status = .ready
            case .downloading:
                status = .indexing
            case .failed:
                status = .failed
            case .unsupported:
                status = .unsupported
            case .remote:
                status = .available
            }
        }

        let readiness: Double
        if download?.status == .cancelled {
            readiness = install.state == .installed ? 1 : 0
        } else if download?.status == .installed || install.state == .installed {
            readiness = 1
        } else if let download {
            if let total = download.totalBytes, total > 0 {
                readiness = min(0.98, max(0, Double(download.bytesReceived) / Double(total)))
            } else {
                readiness = status == .ready ? 1 : 0.1
            }
        } else {
            readiness = install.state == .installed ? 1 : (install.state == .downloading ? 0.5 : 0)
        }

        var compatibilityWarnings: [String]
        switch install.verification {
        case .unsupported:
            compatibilityWarnings = ["This repository is not compatible with the current MLX runtime profile."]
        case .experimental:
            compatibilityWarnings = ["This repository looks compatible but needs device verification before production use."]
        case .installable:
            compatibilityWarnings = install.state == .remote ? ["Compatibility is based on Hugging Face metadata until preflight completes."] : []
        case .verified:
            compatibilityWarnings = []
        }

        let runtimeProfile = enrichRuntime
            ? runtime.defaultRuntimeProfile(for: install)
            : RuntimeProfile(
                name: "Pending",
                quantization: QuantizationProfile(
                    algorithm: .none,
                    kvCacheStrategy: .none,
                    preset: nil,
                    requestedBackend: nil,
                    activeBackend: nil,
                    activeAttentionPath: nil,
                    activeFallbackReason: "Runtime diagnostics load after startup."
                ),
                promptCacheIdentifier: install.repository
            )
        let matchingProfileEvidence = matchingTurboQuantProfileEvidence(
            from: profileEvidence,
            install: install,
            runtimeProfile: runtimeProfile
        )
        let runtimeCompatibilityState = RuntimeCompatibilityState.resolve(
            installVerification: install.verification,
            evidence: matchingProfileEvidence,
            admission: runtimeProfile.quantization.turboQuantAdmission,
            requestedContextTokens: runtimeProfile.quantization.turboQuantAdmission?.requestedContextLength
        )
        switch runtimeCompatibilityState {
        case .verified:
            break
        case .conservative:
            compatibilityWarnings.append("Runs with conservative defaults until matching benchmark evidence is imported.")
        case .unverified:
            compatibilityWarnings.append("No trusted local benchmark evidence is available for this model/device/mode tuple.")
        case .unsupported:
            if compatibilityWarnings.isEmpty {
                compatibilityWarnings.append("This tuple is unsupported by the current runtime profile.")
            }
        case .degraded:
            compatibilityWarnings.append("Runtime will use a reduced context or fallback path for this tuple.")
        case .benchmarkRequired:
            compatibilityWarnings.append("Benchmark evidence is required before this tuple can make a support claim.")
        case .revoked:
            compatibilityWarnings.append("Previous benchmark evidence was revoked and cannot support this tuple.")
        }
        let compatibilityExplanation = runtimeCompatibilityExplanation(
            state: runtimeCompatibilityState,
            install: install,
            profile: runtimeProfile,
            evidence: matchingProfileEvidence
        )
        let contextWindow: String
        if enrichRuntime,
           let admittedContext = runtimeProfile.quantization.turboQuantAdmission?.admittedContextLength,
           admittedContext > 0 {
            contextWindow = "\(admittedContext.formatted()) tokens"
        } else {
            contextWindow = enrichRuntime
                ? (runtime.capabilities.maxContextTokens.map { "\($0 / 1000)K" } ?? "Unknown")
                : "Pending"
        }

        return PinesModelPreview(
            install: install,
            runtimeProfile: runtimeProfile,
            name: install.displayName,
            family: install.modelType ?? install.modalities.map(\.rawValue).sorted().joined(separator: ", "),
            footprint: install.estimatedBytes.map(Self.byteLabel) ?? download?.totalBytes.map(Self.byteLabel) ?? "Size unavailable",
            contextWindow: contextWindow,
            runtime: install.modalities.contains(.embeddings) ? "MLX Embedders" : (install.modalities.contains(.vision) ? "MLX VLM" : "MLX"),
            status: status,
            capabilities: install.modalities.map(\.rawValue).sorted(),
            readiness: readiness,
            downloadProgress: download,
            compatibilityWarnings: compatibilityWarnings,
            runtimeProfileEvidence: matchingProfileEvidence,
            runtimeCompatibilityState: runtimeCompatibilityState,
            compatibilityExplanation: compatibilityExplanation
        )
    }

    nonisolated private static func runtimeCompatibilityExplanation(
        state: RuntimeCompatibilityState,
        install: ModelInstall,
        profile: RuntimeProfile,
        evidence: RuntimeProfileEvidence?
    ) -> PinesRuntimeCompatibilityExplanation {
        let admission = profile.quantization.turboQuantAdmission
        let headline: String
        let summary: String
        let nextAction: String?
        switch state {
        case .verified:
            headline = "Verified for this exact runtime tuple"
            summary = "Trusted benchmark evidence matches the model, runtime pair, device class, mode, backend, and fallback contract shown below."
            nextAction = nil
        case .conservative:
            headline = "Installable; running conservatively"
            summary = "The model is supported by the installer, but no matching benchmark may be used as a product-level performance claim. Pines keeps conservative defaults."
            nextAction = "Import or run a matching trusted device benchmark to verify this tuple."
        case .unverified:
            headline = "Installable metadata, unverified runtime tuple"
            summary = "Repository metadata passed basic checks. That is not proof for this device, context, runtime pair, or backend."
            nextAction = install.state == .remote ? "Run preflight, install the model, then capture device evidence." : "Capture matching on-device evidence before relying on performance claims."
        case .degraded:
            headline = "Supported with a runtime downgrade"
            summary = admission?.userMessage ?? "Pines reduced context or selected a fallback path to stay within the current device budget."
            nextAction = "Use the admitted context below or choose a smaller model/profile."
        case .unsupported:
            headline = "Unsupported by the current runtime profile"
            summary = admission?.userMessage ?? "This model or requested tuple cannot be admitted safely on the current runtime profile."
            nextAction = "Choose a supported model, reduce context, or change the runtime mode."
        case .benchmarkRequired:
            headline = "Benchmark required before support can be claimed"
            summary = "The repository is experimental and needs a trusted benchmark for the exact tuple shown below."
            nextAction = "Run and import the required on-device benchmark."
        case .revoked:
            headline = "Previous evidence was revoked"
            summary = evidence?.revokedReason ?? "The prior evidence no longer supports this runtime tuple. Pines will not use it for a compatibility claim."
            nextAction = "Capture replacement evidence with the current runtime and fallback contract."
        }

        var facts = [PinesRuntimeCompatibilityExplanation.Fact]()
        facts.append(.init(label: "Install check", value: install.verification.rawValue))
        facts.append(.init(label: "Profile", value: profile.name))
        if let evidence {
            facts.append(.init(label: "Evidence", value: "\(evidence.evidenceLevel.rawValue) - \(evidence.createdAt.formatted(date: .abbreviated, time: .omitted))"))
            facts.append(.init(label: "Compatibility pair", value: evidence.compatibilityPairID))
            facts.append(.init(label: "Device class", value: evidence.deviceClass.rawValue))
            facts.append(.init(label: "Mode", value: evidence.userMode.rawValue))
            if let mode = evidence.resolvedRuntimeMode { facts.append(.init(label: "Runtime mode", value: mode.rawValue)) }
            if let backend = evidence.effectiveBackend { facts.append(.init(label: "Backend", value: backend.rawValue)) }
            facts.append(.init(label: "Fallback contract", value: String(evidence.fallbackContractHash.prefix(16))))
        } else {
            facts.append(.init(label: "Evidence", value: "No matching trusted evidence"))
            if let deviceClass = profile.quantization.devicePerformanceClass {
                facts.append(.init(label: "Device class", value: deviceClass.rawValue))
            }
            facts.append(.init(label: "Mode", value: profile.quantization.turboQuantUserMode.rawValue))
            if let mode = profile.quantization.turboQuantResolvedRuntimeMode {
                facts.append(.init(label: "Runtime mode", value: mode.rawValue))
            }
            if let backend = profile.quantization.turboQuantEffectiveBackend {
                facts.append(.init(label: "Backend", value: backend.rawValue))
            }
        }
        if let admission {
            facts.append(.init(
                label: "Context admission",
                value: "\(admission.requestedContextLength.formatted()) requested -> \(admission.admittedContextLength.formatted()) admitted"
            ))
        }
        if let fallback = profile.quantization.activeFallbackReason, !fallback.isEmpty {
            facts.append(.init(label: "Fallback", value: fallback))
        }
        return PinesRuntimeCompatibilityExplanation(
            headline: headline,
            summary: summary,
            claimBasis: state.allowsProductClaim ? "Exact-tuple claim backed by trusted evidence" : "No verified product claim for this exact tuple",
            facts: facts,
            nextAction: nextAction
        )
    }

    nonisolated static func latestDownloadByRepository(_ downloads: [ModelDownloadProgress]) -> [String: ModelDownloadProgress] {
        Dictionary(grouping: downloads, by: { $0.repository.lowercased() }).mapValues { values in
            values.sorted { $0.updatedAt > $1.updatedAt }.first!
        }
    }

    nonisolated static func modelPreviews(
        installs: [ModelInstall],
        downloads: [ModelDownloadProgress],
        runtime: MLXRuntimeBridge,
        profileEvidenceByModelID: [String: [RuntimeProfileEvidence]] = [:],
        enrichRuntime: Bool = true
    ) -> [PinesModelPreview] {
        let downloadByRepository = latestDownloadByRepository(downloads)
        let installKeys = Set(installs.map { $0.repository.lowercased() })
        var previews = installs.map { install in
            modelPreview(
                from: install,
                runtime: runtime,
                download: downloadByRepository[install.repository.lowercased()],
                profileEvidence: profileEvidenceByModelID[profileEvidenceKey(for: install)] ?? [],
                enrichRuntime: enrichRuntime
            )
        }

        let orphanPreviews = downloadByRepository.values
            .filter { download in
                !installKeys.contains(download.repository.lowercased())
                    && shouldRepresentDownloadWithoutInstall(download)
            }
            .map { download in
                modelPreview(
                    from: recoverableInstall(from: download),
                    runtime: runtime,
                    download: download,
                    profileEvidence: [],
                    enrichRuntime: enrichRuntime
                )
            }
        previews.append(contentsOf: orphanPreviews)
        return downloadingFirst(previews)
    }

    nonisolated static func profileEvidenceKey(for install: ModelInstall) -> String {
        install.modelID.rawValue.lowercased()
    }

    nonisolated static func matchingTurboQuantProfileEvidence(
        from records: [RuntimeProfileEvidence]?,
        install: ModelInstall,
        runtimeProfile: RuntimeProfile
    ) -> RuntimeProfileEvidence? {
        let records = records ?? []
        let quantization = runtimeProfile.quantization
        let admission = quantization.turboQuantAdmission
        let mode = admission?.selectedMode ?? quantization.turboQuantUserMode
        let requiredContext = admission?.admittedContextLength ?? quantization.maxKVSize ?? 0
        let requestedSpeculativeDimensions = speculativeEvidenceDimensions(for: runtimeProfile)
        let acceptedCompatibilityPairIDs = Set([MLXRuntimeBridge.turboQuantCompatibilityPairID])

        return records
            .filter { evidence in
                guard evidence.modelID.lowercased() == install.modelID.rawValue.lowercased() else {
                    return false
                }
                if evidence.evidenceLevel.canMakeProductCompatibilityClaim {
                    guard acceptedCompatibilityPairIDs.contains(evidence.compatibilityPairID) else {
                        return false
                    }
                    guard let evidenceRevision = evidence.modelRevision,
                          let installRevision = install.revision,
                          evidenceRevision == installRevision else {
                        return false
                    }
                    guard let deviceClass = quantization.devicePerformanceClass,
                          evidence.deviceClass == deviceClass else {
                        return false
                    }
                    guard let runtimeLayoutVersion = quantization.turboQuantLayoutVersion,
                          evidence.layoutVersion == runtimeLayoutVersion else {
                        return false
                    }
                    guard let admission else {
                        return false
                    }
                    let fallbackReserve = Int64(
                        admission.memoryPlan?.runtimeZones.fallbackReserveBytes
                            ?? Int(TurboQuantFallbackContract.defaultReserveBytes(for: mode))
                    )
                    let fallbackHash = TurboQuantFallbackContract.productDefault(
                        for: mode,
                        allowCloudRetry: false,
                        reserveBytes: fallbackReserve
                    ).contractHash
                    guard evidence.fallbackContractHash == fallbackHash else {
                        return false
                    }
                    if let attentionPath = quantization.activeAttentionPath,
                       evidence.activeAttentionPath != attentionPath {
                        return false
                    }
                    if let preset = quantization.preset,
                       evidence.turboQuantPreset != preset.rawValue {
                        return false
                    }
                    if let valueBits = quantization.turboQuantValueBits,
                       evidence.valueBits != valueBits {
                        return false
                    }
                    guard let resolvedRuntimeMode = quantization.turboQuantResolvedRuntimeMode,
                          evidence.resolvedRuntimeMode == resolvedRuntimeMode else {
                        return false
                    }
                    guard evidence.requestedRuntimeMode == quantization.turboQuantRuntimeMode else {
                        return false
                    }
                    if let precisionPolicy = quantization.turboQuantPrecisionPolicy,
                       evidence.precisionPolicy != precisionPolicy {
                        return false
                    }
                    if let keyPrecision = quantization.turboQuantKeyPrecision,
                       evidence.keyPrecision != keyPrecision {
                        return false
                    }
                    if let valuePrecision = quantization.turboQuantValuePrecision,
                       evidence.valuePrecision != valuePrecision {
                        return false
                    }
                    let sparseValuePolicy = quantization.turboQuantSparseValuePolicy ?? .off
                    guard (evidence.sparseValuePolicy ?? .off) == sparseValuePolicy else {
                        return false
                    }
                    guard let effectiveBackend = quantization.turboQuantEffectiveBackend,
                          evidence.effectiveBackend == effectiveBackend else {
                        return false
                    }
                    if effectiveBackend == .nativeMLX,
                       evidence.nativeBackendVersion != quantization.turboQuantNativeBackendVersion {
                        return false
                    }
                    if evidence.groupSize != quantization.kvGroupSize {
                        return false
                    }
                } else if let evidenceRevision = evidence.modelRevision,
                          let installRevision = install.revision,
                          evidenceRevision != installRevision {
                    return false
                }
                if let deviceClass = quantization.devicePerformanceClass,
                   evidence.deviceClass != deviceClass {
                    return false
                }
                guard evidence.userMode == mode else {
                    return false
                }
                guard (evidence.speculativeDimensions ?? .disabled).matches(requestedSpeculativeDimensions) else {
                    return false
                }
                guard evidence.admittedContextTokens >= requiredContext else {
                    return false
                }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    nonisolated static func speculativeEvidenceDimensions(for runtimeProfile: RuntimeProfile) -> TurboQuantSpeculativeEvidenceDimensions {
        let quantization = runtimeProfile.quantization
        if let telemetry = quantization.turboQuantSpeculativeTelemetry {
            return telemetry.dimensions
        }
        if let settings = runtimeProfile.speculativeSettings ?? quantization.turboQuantSpeculativeSettings,
           settings.enabled {
            return TurboQuantSpeculativeEvidenceDimensions(
                enabled: true,
                draftModelID: settings.draftModelID ?? runtimeProfile.speculativeDraftModelID?.rawValue,
                draftModelRevision: settings.draftModelRevision,
                maxDraftTokens: settings.maxDraftTokens
            )
        }
        if runtimeProfile.speculativeDecodingEnabled {
            return TurboQuantSpeculativeEvidenceDimensions(
                enabled: true,
                draftModelID: runtimeProfile.speculativeDraftModelID?.rawValue
            )
        }
        return .disabled
    }

    nonisolated static func downloadingFirst(_ previews: [PinesModelPreview]) -> [PinesModelPreview] {
        previews.enumerated()
            .sorted { lhs, rhs in
                let lhsActive = lhs.element.isDownloadActive
                let rhsActive = rhs.element.isDownloadActive
                if lhsActive != rhsActive {
                    return lhsActive
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    nonisolated static func shouldRepresentDownloadWithoutInstall(_ download: ModelDownloadProgress) -> Bool {
        switch download.status {
        case .queued, .downloading, .verifying, .installing, .installed, .failed:
            true
        case .cancelled:
            false
        }
    }

    nonisolated static func recoverableInstall(from download: ModelDownloadProgress) -> ModelInstall {
        let curatedEntry = CuratedModelManifest.default.entries.first {
            $0.repository.caseInsensitiveCompare(download.repository) == .orderedSame
        }
        let state: ModelInstallState = download.isPinesDownloadActive ? .downloading : .failed
        return ModelInstall(
            modelID: ModelID(rawValue: download.repository),
            displayName: curatedEntry?.displayName ?? download.repository.components(separatedBy: "/").last ?? download.repository,
            repository: download.repository,
            revision: download.revision,
            localURL: download.localURL,
            modalities: curatedEntry?.modalities ?? [.text],
            verification: curatedEntry == nil ? .installable : .verified,
            state: state,
            estimatedBytes: download.totalBytes
        )
    }

    static func vaultPreview(from record: VaultDocumentRecord) -> PinesVaultItemPreview {
        let kind: PinesVaultKind
        switch record.sourceType.lowercased() {
        case "image", "photo":
            kind = .image
        case "key":
            kind = .key
        case "note":
            kind = .note
        default:
            kind = .document
        }

        return PinesVaultItemPreview(
            id: record.id,
            projectID: record.projectID,
            title: record.title,
            kind: kind,
            detail: "\(record.chunkCount) indexed chunks",
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt),
            sensitivity: .local,
            linkedThreads: 0,
            activeProfileEmbeddedChunks: 0,
            activeProfileTotalChunks: record.chunkCount,
            sourceContentType: record.sourceType,
            sourceRevision: record.checksum ?? String(record.updatedAt.timeIntervalSinceReferenceDate)
        )
    }

    nonisolated static func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
