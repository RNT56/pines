import Foundation
import OSLog
import PinesCore
import UniformTypeIdentifiers

#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision)
import Vision
#endif

struct VaultIngestionService {
    static let allowedContentTypes: [UTType] = {
        var types: [UTType] = [.plainText, .utf8PlainText, .text, .pdf, .image, .json, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        if let markdown = UTType(filenameExtension: "markdown") {
            types.append(markdown)
        }
        return types
    }()

    let vaultRepository: any VaultRepository
    let settingsRepository: (any SettingsRepository)?
    let inferenceProvider: any InferenceProvider
    let embeddingService: VaultEmbeddingService?
    let encryptedBlobStore: EncryptedBlobStore
    let auditRepository: (any AuditEventRepository)?
    let chunker = VaultChunker()
    private let deviceMonitor = DeviceRuntimeMonitor()
    private static let logger = Logger(subsystem: "com.schtack.pines", category: "vault-ingestion")
    private static let maximumSourceFileBytes: Int64 = 50 * 1024 * 1024
    private static let maximumExtractedTextCharacters = 1_000_000
    private static let supportedExtensions: Set<String> = [
        "csv",
        "heic",
        "jpeg",
        "jpg",
        "json",
        "markdown",
        "md",
        "pdf",
        "png",
        "text",
        "tif",
        "tiff",
        "txt"
    ]

    func importFile(url sourceURL: URL) async throws -> VaultDocumentRecord {
        let didStart = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try Self.validateSourceFile(sourceURL)
        try Task.checkCancellation()
        let text = try await Self.extractText(from: sourceURL)
        try Task.checkCancellation()
        let encryptedMetadata = try await encryptedBlobStore.write(
            try Self.readLimitedFileData(from: sourceURL),
            contentType: Self.sourceType(for: sourceURL)
        )
        let encryptedURL = try encryptedBlobStore.fileURL(for: encryptedMetadata)
        let document = VaultDocumentRecord(
            title: sourceURL.deletingPathExtension().lastPathComponent,
            sourceType: Self.sourceType(for: sourceURL),
            updatedAt: Date(),
            chunkCount: 0,
            checksum: encryptedMetadata.sha256,
            localURL: encryptedURL
        )
        let checksum = encryptedMetadata.sha256
        try await vaultRepository.upsertDocument(document, localURL: encryptedURL, checksum: checksum)

        let chunks = chunker.chunks(for: text, sourceID: document.id.uuidString)
        try Task.checkCancellation()
        if let embeddingProfile = try await embeddingService?.activeUsableProfile(), !chunks.isEmpty {
            var job = VaultEmbeddingJob(
                profileID: embeddingProfile.id,
                documentID: document.id,
                status: .running,
                totalChunks: chunks.count,
                attemptCount: 1
            )
            try await vaultRepository.upsertEmbeddingJob(job)
            do {
                let progressRepository = vaultRepository
                let progressDocumentID = document.id
                let progressProfileID = embeddingProfile.id
                let totalChunks = chunks.count
                let jobID = job.id
                let jobCreatedAt = job.createdAt
                let chunkEmbeddings = try await embeddingService?.embed(
                    chunks: chunks,
                    documentID: document.id,
                    profile: embeddingProfile,
                    progress: { processed in
                        try await progressRepository.upsertEmbeddingJob(
                            VaultEmbeddingJob(
                                id: jobID,
                                profileID: progressProfileID,
                                documentID: progressDocumentID,
                                status: .running,
                                processedChunks: processed,
                                totalChunks: totalChunks,
                                attemptCount: 1,
                                createdAt: jobCreatedAt,
                                updatedAt: Date()
                            )
                        )
                    }
                ) ?? []
                if chunkEmbeddings.count == chunks.count {
                    try await vaultRepository.replaceChunks(
                        chunks,
                        embeddings: VaultEmbeddingBatch(modelID: embeddingProfile.modelID, embeddings: chunkEmbeddings),
                        documentID: document.id,
                        embeddingProfile: embeddingProfile
                    )
                    job.status = .complete
                    job.processedChunks = chunkEmbeddings.count
                    job.updatedAt = Date()
                    try await vaultRepository.upsertEmbeddingJob(job)
                } else {
                    try await vaultRepository.replaceChunks(chunks, documentID: document.id, embeddingModelID: nil)
                    job.status = .failed
                    job.processedChunks = chunkEmbeddings.count
                    job.lastError = "Embedding provider returned \(chunkEmbeddings.count) vectors for \(chunks.count) chunks."
                    job.updatedAt = Date()
                    try await vaultRepository.upsertEmbeddingJob(job)
                }
            } catch is CancellationError {
                job.status = .cancelled
                job.updatedAt = Date()
                do {
                    try await vaultRepository.upsertEmbeddingJob(job)
                } catch {
                    Self.logger.error("vault_ingestion_cancel_job_persist_failed document=\(document.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                }
                throw CancellationError()
            } catch {
                try await vaultRepository.replaceChunks(chunks, documentID: document.id, embeddingModelID: nil)
                job.status = .failed
                job.lastError = Redactor().redact(error.localizedDescription)
                job.updatedAt = Date()
                do {
                    try await vaultRepository.upsertEmbeddingJob(job)
                } catch {
                    Self.logger.error("vault_ingestion_failed_job_persist_failed document=\(document.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                }
            }
        } else if let embeddingModelID = try await settingsRepository?.loadSettings().embeddingModelID, !chunks.isEmpty {
            do {
                if let chunkEmbeddings = try await embed(chunks: chunks, documentID: document.id, modelID: embeddingModelID) {
                    let embeddings = VaultEmbeddingBatch(
                        modelID: embeddingModelID,
                        embeddings: chunkEmbeddings
                    )
                    try await vaultRepository.replaceChunks(
                        chunks,
                        embeddings: embeddings,
                        documentID: document.id,
                        embeddingModelID: embeddingModelID
                    )
                } else {
                    try await vaultRepository.replaceChunks(chunks, documentID: document.id, embeddingModelID: nil)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try await vaultRepository.replaceChunks(chunks, documentID: document.id, embeddingModelID: nil)
            }
        } else {
            try await vaultRepository.replaceChunks(chunks, documentID: document.id, embeddingModelID: nil)
        }

        try await auditRepository?.append(
            AuditEvent(category: .vaultImport, summary: "Imported encrypted source \(sourceURL.lastPathComponent)")
        )
        return VaultDocumentRecord(
            id: document.id,
            title: document.title,
            sourceType: document.sourceType,
            updatedAt: document.updatedAt,
            chunkCount: chunks.count
        )
    }

    private func embed(
        chunks: [VaultChunk],
        documentID: UUID,
        modelID: ModelID
    ) async throws -> [VaultChunkEmbedding]? {
        let batchSize = max(1, deviceMonitor.currentProfile().recommendedEmbeddingBatchSize)
        var allEmbeddings = [VaultChunkEmbedding]()
        allEmbeddings.reserveCapacity(chunks.count)

        for startIndex in stride(from: 0, to: chunks.count, by: batchSize) {
            try Task.checkCancellation()
            let endIndex = min(startIndex + batchSize, chunks.count)
            let batch = Array(chunks[startIndex..<endIndex])
            let result = try await inferenceProvider.embed(
                EmbeddingRequest(modelID: modelID, inputs: batch.map(\.text))
            )
            guard result.vectors.count == batch.count else {
                return nil
            }
            allEmbeddings.append(contentsOf: zip(batch, result.vectors).map { chunk, vector in
                VaultChunkEmbedding(
                    chunkID: chunk.id,
                    documentID: documentID,
                    modelID: modelID,
                    vector: vector
                )
            })
        }

        return allEmbeddings
    }

    private static func validateSourceFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey])
        if values.isRegularFile == false {
            throw VaultIngestionError.unsupportedFileType(url.pathExtension)
        }

        let extensionIsSupported = supportedExtensions.contains(url.pathExtension.lowercased())
        let typeIsSupported = values.contentType.map { type in
            allowedContentTypes.contains { allowedType in
                type.conforms(to: allowedType)
            }
        } ?? false
        guard extensionIsSupported || typeIsSupported else {
            throw VaultIngestionError.unsupportedFileType(url.pathExtension)
        }

        guard let fileSize = values.fileSize else {
            throw VaultIngestionError.unavailableFileSize
        }
        let byteCount = Int64(fileSize)
        guard byteCount <= maximumSourceFileBytes else {
            throw VaultIngestionError.fileTooLarge(actualBytes: byteCount, maximumBytes: maximumSourceFileBytes)
        }
    }

    private static func readLimitedFileData(from url: URL) throws -> Data {
        guard let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw VaultIngestionError.unavailableFileSize
        }
        let byteCount = Int64(fileSize)
        guard byteCount <= maximumSourceFileBytes else {
            throw VaultIngestionError.fileTooLarge(actualBytes: byteCount, maximumBytes: maximumSourceFileBytes)
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func extractText(from url: URL) async throws -> String {
        let text: String
        switch url.pathExtension.lowercased() {
        case "pdf":
            text = try extractPDFText(from: url)
        case "png", "jpg", "jpeg", "heic", "tif", "tiff":
            text = try await extractImageText(from: url)
        default:
            let data = try readLimitedFileData(from: url)
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw VaultIngestionError.unsupportedTextEncoding
            }
            text = decoded
        }
        try validateExtractedText(text)
        return text
    }

    private static func extractPDFText(from url: URL) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            let data = try readLimitedFileData(from: url)
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw VaultIngestionError.unsupportedTextEncoding
            }
            return decoded
        }
        var extracted = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string {
                try appendExtractedText(text, to: &extracted)
            }
        }
        return extracted
        #else
        let data = try readLimitedFileData(from: url)
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw VaultIngestionError.unsupportedTextEncoding
        }
        return decoded
        #endif
    }

    private static func extractImageText(from url: URL) async throws -> String {
        #if canImport(Vision)
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            do {
                try VNImageRequestHandler(url: url).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #else
        return ""
        #endif
    }

    private static func sourceType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "tiff":
            "image"
        case "md", "markdown", "txt":
            "note"
        default:
            "document"
        }
    }

    private static func appendExtractedText(_ next: String, to extracted: inout String) throws {
        let separator = extracted.isEmpty ? "" : "\n\n"
        guard extracted.count + separator.count + next.count <= maximumExtractedTextCharacters else {
            throw VaultIngestionError.extractedTextTooLarge(maximumCharacters: maximumExtractedTextCharacters)
        }
        extracted += separator
        extracted += next
    }

    private static func validateExtractedText(_ text: String) throws {
        guard text.count <= maximumExtractedTextCharacters else {
            throw VaultIngestionError.extractedTextTooLarge(maximumCharacters: maximumExtractedTextCharacters)
        }
    }
}

private enum VaultIngestionError: LocalizedError {
    case unsupportedFileType(String)
    case unsupportedTextEncoding
    case unavailableFileSize
    case fileTooLarge(actualBytes: Int64, maximumBytes: Int64)
    case extractedTextTooLarge(maximumCharacters: Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFileType(fileExtension):
            let suffix = fileExtension.isEmpty ? "" : " .\(fileExtension)"
            return "Vault imports support PDF, text, Markdown, CSV, JSON, and image files. This\(suffix) file is not supported."
        case .unsupportedTextEncoding:
            return "Vault text imports must use UTF-8 encoding."
        case .unavailableFileSize:
            return "Vault could not determine the file size before import."
        case let .fileTooLarge(actualBytes, maximumBytes):
            return "Vault imports are limited to \(Self.megabytes(maximumBytes)) MB. This file is \(Self.megabytes(actualBytes)) MB."
        case let .extractedTextTooLarge(maximumCharacters):
            return "Vault imports are limited to \(maximumCharacters.formatted()) extracted text characters."
        }
    }

    private static func megabytes(_ bytes: Int64) -> Int64 {
        max(1, (bytes + 1_048_575) / 1_048_576)
    }
}

private enum StableFileHash {
    static func hexDigest(for text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
