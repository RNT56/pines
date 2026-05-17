import Foundation
import OSLog
import PinesCore

#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision) && canImport(UIKit)
import UIKit
import Vision
#endif

struct VaultIngestionService {
    let vaultRepository: any VaultRepository
    let settingsRepository: (any SettingsRepository)?
    let inferenceProvider: any InferenceProvider
    let embeddingService: VaultEmbeddingService?
    let auditRepository: (any AuditEventRepository)?
    let chunker = VaultChunker()
    private let deviceMonitor = DeviceRuntimeMonitor()
    private static let logger = Logger(subsystem: "com.schtack.pines", category: "vault-ingestion")

    func importFile(url sourceURL: URL) async throws -> VaultDocumentRecord {
        let storedURL = try Self.copyIntoVault(sourceURL)
        try Task.checkCancellation()
        let text = try await Self.extractText(from: storedURL)
        try Task.checkCancellation()
        let document = VaultDocumentRecord(
            title: storedURL.deletingPathExtension().lastPathComponent,
            sourceType: Self.sourceType(for: storedURL),
            updatedAt: Date(),
            chunkCount: 0
        )
        let checksum = StableFileHash.hexDigest(for: text)
        try await vaultRepository.upsertDocument(document, localURL: storedURL, checksum: checksum)

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
                let jobID = job.id
                let jobCreatedAt = job.createdAt
                let chunkEmbeddings = try await embeddingService?.embed(
                    chunks: chunks,
                    documentID: document.id,
                    profile: embeddingProfile,
                    progress: { processed in
                        try await vaultRepository.upsertEmbeddingJob(
                            VaultEmbeddingJob(
                                id: jobID,
                                profileID: embeddingProfile.id,
                                documentID: document.id,
                                status: .running,
                                processedChunks: processed,
                                totalChunks: chunks.count,
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
                job.lastError = error.localizedDescription
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
            AuditEvent(category: .vaultImport, summary: "Imported \(storedURL.lastPathComponent)")
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

    private static func copyIntoVault(_ sourceURL: URL) throws -> URL {
        let didStart = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let directory = try vaultFilesDirectory()
        let destination = directory.appending(path: "\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func extractText(from url: URL) async throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try extractPDFText(from: url)
        case "png", "jpg", "jpeg", "heic", "tiff":
            return try await extractImageText(from: url)
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    private static func extractPDFText(from url: URL) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            return try String(contentsOf: url, encoding: .utf8)
        }
        var pages = [String]()
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string {
                pages.append(text)
            }
        }
        return pages.joined(separator: "\n\n")
        #else
        return try String(contentsOf: url, encoding: .utf8)
        #endif
    }

    private static func extractImageText(from url: URL) async throws -> String {
        #if canImport(Vision) && canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else {
            return ""
        }
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
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
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

    private static func vaultFilesDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "Pines/VaultFiles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
