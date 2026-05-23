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
        messages.reduce(0) { $0 + max(1, $1.content.split(separator: " ").count) }
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

        let compatibilityWarnings: [String]
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
        let contextWindow = enrichRuntime
            ? (runtime.capabilities.maxContextTokens.map { "\($0 / 1000)K" } ?? "Unknown")
            : "Pending"

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
            compatibilityWarnings: compatibilityWarnings
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
        enrichRuntime: Bool = true
    ) -> [PinesModelPreview] {
        let downloadByRepository = latestDownloadByRepository(downloads)
        let installKeys = Set(installs.map { $0.repository.lowercased() })
        var previews = installs.map { install in
            modelPreview(
                from: install,
                runtime: runtime,
                download: downloadByRepository[install.repository.lowercased()],
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
                    enrichRuntime: enrichRuntime
                )
            }
        previews.append(contentsOf: orphanPreviews)
        return downloadingFirst(previews)
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
            chunks: [],
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt),
            sensitivity: .local,
            linkedThreads: 0,
            activeProfileEmbeddedChunks: 0,
            activeProfileTotalChunks: record.chunkCount,
            sourceContentType: record.sourceType,
            sourceData: nil
        )
    }

    nonisolated static func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
