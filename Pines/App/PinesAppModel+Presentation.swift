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
            title: record.title,
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
            title: record.title,
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
            title: existing.title,
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

    static func install(from summary: RemoteModelSummary, preflight: ModelPreflightResult) -> ModelInstall {
        return ModelInstall(
            modelID: ModelID(rawValue: summary.repository),
            displayName: summary.repository.components(separatedBy: "/").last ?? summary.repository,
            repository: summary.repository,
            modalities: preflight.modalities.isEmpty ? Self.modalities(from: summary) : preflight.modalities,
            verification: preflight.verification,
            state: preflight.verification == .unsupported ? .unsupported : .remote,
            estimatedBytes: preflight.estimatedBytes > 0 ? preflight.estimatedBytes : nil,
            license: preflight.license,
            modelType: preflight.modelType,
            processorClass: preflight.processorClass
        )
    }

    static func modalities(from summary: RemoteModelSummary) -> Set<ModelModality> {
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

    static func modelPreview(
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
            id: install.id,
            install: install,
            runtimeProfile: runtimeProfile,
            name: install.displayName,
            family: install.modelType ?? install.modalities.map(\.rawValue).sorted().joined(separator: ", "),
            footprint: install.estimatedBytes.map(Self.byteLabel) ?? download?.totalBytes.map(Self.byteLabel) ?? "Remote",
            contextWindow: contextWindow,
            runtime: install.modalities.contains(.embeddings) ? "MLX Embedders" : (install.modalities.contains(.vision) ? "MLX VLM" : "MLX"),
            status: status,
            capabilities: install.modalities.map(\.rawValue).sorted(),
            readiness: readiness,
            downloadProgress: download,
            compatibilityWarnings: compatibilityWarnings
        )
    }

    static func latestDownloadByRepository(_ downloads: [ModelDownloadProgress]) -> [String: ModelDownloadProgress] {
        Dictionary(grouping: downloads, by: { $0.repository.lowercased() }).mapValues { values in
            values.sorted { $0.updatedAt > $1.updatedAt }.first!
        }
    }

    static func downloadingFirst(_ previews: [PinesModelPreview]) -> [PinesModelPreview] {
        previews.enumerated()
            .sorted { lhs, rhs in
                let lhsActive = lhs.element.isDownloadActive
                let rhsActive = rhs.element.isDownloadActive
                if lhsActive != rhsActive {
                    return lhsActive
                }
                if lhsActive,
                   let lhsUpdated = lhs.element.downloadProgress?.updatedAt,
                   let rhsUpdated = rhs.element.downloadProgress?.updatedAt,
                   lhsUpdated != rhsUpdated {
                    return lhsUpdated > rhsUpdated
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
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
            title: record.title,
            kind: kind,
            detail: "\(record.chunkCount) indexed chunks",
            chunks: [],
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt),
            sensitivity: .local,
            linkedThreads: 0,
            activeProfileEmbeddedChunks: 0,
            activeProfileTotalChunks: record.chunkCount
        )
    }

    static func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
