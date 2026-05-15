import Foundation
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
    let auditRepository: (any AuditEventRepository)?
    let chunker = VaultChunker()

    func importFile(url sourceURL: URL) async throws -> VaultDocumentRecord {
        let storedURL = try Self.copyIntoVault(sourceURL)
        let text = try await Self.extractText(from: storedURL)
        let document = VaultDocumentRecord(
            title: storedURL.deletingPathExtension().lastPathComponent,
            sourceType: Self.sourceType(for: storedURL),
            updatedAt: Date(),
            chunkCount: 0
        )
        let checksum = StableFileHash.hexDigest(for: text)
        try await vaultRepository.upsertDocument(document, localURL: storedURL, checksum: checksum)

        let chunks = chunker.chunks(for: text, sourceID: document.id.uuidString)
        if let embeddingModelID = try await settingsRepository?.loadSettings().embeddingModelID, !chunks.isEmpty {
            _ = try? await inferenceProvider.embed(
                EmbeddingRequest(modelID: embeddingModelID, inputs: chunks.map(\.text))
            )
            try await vaultRepository.replaceChunks(chunks, documentID: document.id, embeddingModelID: embeddingModelID)
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
