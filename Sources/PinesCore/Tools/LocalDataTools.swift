import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

public struct VaultSearchInput: ToolInput, Equatable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

public struct VaultSearchItem: Codable, Equatable, Hashable, Sendable {
    public let documentID: String
    public let documentTitle: String
    public let sourceType: String
    public let chunkID: String
    public let ordinal: Int
    public let score: Double
    public let snippet: String

    public init(
        documentID: String,
        documentTitle: String,
        sourceType: String,
        chunkID: String,
        ordinal: Int,
        score: Double,
        snippet: String
    ) {
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.sourceType = sourceType
        self.chunkID = chunkID
        self.ordinal = ordinal
        self.score = score
        self.snippet = snippet
    }
}

public struct VaultSearchOutput: ToolOutput, Equatable {
    public let query: String
    public let searchMode: String
    public let results: [VaultSearchItem]
    public let resultsJSON: String

    public init(query: String, searchMode: String, results: [VaultSearchItem]) {
        self.query = query
        self.searchMode = searchMode
        self.results = results
        resultsJSON = Self.encode(results)
    }

    private static func encode(_ results: [VaultSearchItem]) -> String {
        (try? String(decoding: JSONEncoder().encode(results), as: UTF8.self)) ?? "[]"
    }
}

public enum VaultSearchTool {
    public static let name = "vault.search"

    public static func spec(
        search: @escaping @Sendable (_ query: String, _ limit: Int) async throws -> VaultSearchOutput
    ) throws -> ToolSpec<VaultSearchInput, VaultSearchOutput> {
        try ToolSpec(
            name: name,
            description: "Search the user's private local Vault documents and return matching document/chunk identifiers and snippets.",
            inputSchema: ToolIOSchema(
                properties: [
                    "query": .init(type: .string, description: "Search query for local Vault content."),
                    "limit": .init(type: .integer, description: "Maximum number of results, clamped to 1...12. Defaults to 6."),
                ],
                required: ["query"]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "query": .init(type: .string, description: "Search query that was executed."),
                    "searchMode": .init(type: .string, description: "semantic, lexical, or lexical-fallback."),
                    "results": .init(type: .array, description: "Structured matching Vault chunks."),
                    "resultsJSON": .init(type: .string, description: "Serialized matching Vault chunks for models that prefer a string payload."),
                ],
                required: ["query", "searchMode", "results", "resultsJSON"]
            ),
            permissions: [.files, .cloudContext],
            sideEffect: .none,
            networkPolicy: .noNetwork,
            timeoutSeconds: 15,
            explanationRequired: true
        ) { input in
            let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw AgentError.invalidToolArguments("vault.search query must not be empty.")
            }
            return try await search(query, clamp(input.limit, defaultValue: 6, range: 1...12))
        }
    }

    public static func output(query: String, searchMode: String, results: [VaultSearchResult]) -> VaultSearchOutput {
        VaultSearchOutput(
            query: query,
            searchMode: searchMode,
            results: results.map { result in
                VaultSearchItem(
                    documentID: result.document.id.uuidString,
                    documentTitle: result.document.title,
                    sourceType: result.document.sourceType,
                    chunkID: result.chunk.id,
                    ordinal: result.chunk.ordinal,
                    score: result.score,
                    snippet: truncate(result.snippet, maxCharacters: 1_200)
                )
            }
        )
    }
}

public struct VaultReadInput: ToolInput, Equatable {
    public let documentID: String?
    public let chunkID: String?
    public let startOrdinal: Int?
    public let limit: Int?
    public let maxCharacters: Int?

    public init(
        documentID: String? = nil,
        chunkID: String? = nil,
        startOrdinal: Int? = nil,
        limit: Int? = nil,
        maxCharacters: Int? = nil
    ) {
        self.documentID = documentID
        self.chunkID = chunkID
        self.startOrdinal = startOrdinal
        self.limit = limit
        self.maxCharacters = maxCharacters
    }
}

public struct VaultReadChunk: Codable, Equatable, Hashable, Sendable {
    public let chunkID: String
    public let ordinal: Int
    public let text: String
    public let truncated: Bool

    public init(chunkID: String, ordinal: Int, text: String, truncated: Bool) {
        self.chunkID = chunkID
        self.ordinal = ordinal
        self.text = text
        self.truncated = truncated
    }
}

public struct VaultReadOutput: ToolOutput, Equatable {
    public let documentID: String
    public let documentTitle: String
    public let chunks: [VaultReadChunk]
    public let text: String
    public let truncated: Bool

    public init(documentID: String, documentTitle: String, chunks: [VaultReadChunk], text: String, truncated: Bool) {
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.chunks = chunks
        self.text = text
        self.truncated = truncated
    }
}

public enum VaultReadTool {
    public static let name = "vault.read"

    public static func spec(repository: any VaultRepository) throws -> ToolSpec<VaultReadInput, VaultReadOutput> {
        try ToolSpec(
            name: name,
            description: "Read bounded text from a private local Vault document or chunk returned by vault.search.",
            inputSchema: ToolIOSchema(
                properties: [
                    "documentID": .init(type: .string, description: "Vault document UUID. Required unless chunkID is supplied."),
                    "chunkID": .init(type: .string, description: "Specific Vault chunk ID to read."),
                    "startOrdinal": .init(type: .integer, description: "First chunk ordinal to read when chunkID is not supplied. Defaults to 0."),
                    "limit": .init(type: .integer, description: "Maximum chunks to read, clamped to 1...12. Defaults to 4."),
                    "maxCharacters": .init(type: .integer, description: "Maximum characters returned, clamped to 1...20000. Defaults to 12000."),
                ]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "documentID": .init(type: .string, description: "Vault document UUID."),
                    "documentTitle": .init(type: .string, description: "Vault document title."),
                    "chunks": .init(type: .array, description: "Chunks that were read."),
                    "text": .init(type: .string, description: "Combined bounded text."),
                    "truncated": .init(type: .boolean, description: "Whether output was truncated."),
                ],
                required: ["documentID", "documentTitle", "chunks", "text", "truncated"]
            ),
            permissions: [.files, .cloudContext],
            sideEffect: .none,
            networkPolicy: .noNetwork,
            timeoutSeconds: 10,
            explanationRequired: true
        ) { input in
            try await readVault(input: input, repository: repository)
        }
    }
}

public struct AttachmentReadInput: ToolInput, Equatable {
    public let attachmentID: String
    public let offset: Int?
    public let maxCharacters: Int?

    public init(attachmentID: String, offset: Int? = nil, maxCharacters: Int? = nil) {
        self.attachmentID = attachmentID
        self.offset = offset
        self.maxCharacters = maxCharacters
    }
}

public struct AttachmentReadOutput: ToolOutput, Equatable {
    public let attachmentID: String
    public let fileName: String
    public let contentType: String
    public let byteCount: Int
    public let text: String
    public let offset: Int
    public let truncated: Bool
    public let note: String?

    public init(
        attachmentID: String,
        fileName: String,
        contentType: String,
        byteCount: Int,
        text: String,
        offset: Int,
        truncated: Bool,
        note: String? = nil
    ) {
        self.attachmentID = attachmentID
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.text = text
        self.offset = offset
        self.truncated = truncated
        self.note = note
    }
}

public enum AttachmentReadTool {
    public static let name = "attachment.read"

    public static func spec(
        attachment: @escaping @Sendable (_ attachmentID: UUID) async throws -> ChatAttachment?
    ) throws -> ToolSpec<AttachmentReadInput, AttachmentReadOutput> {
        try ToolSpec(
            name: name,
            description: "Read bounded text from a file attached to the current user message. Use attachment IDs from the current attachment manifest.",
            inputSchema: ToolIOSchema(
                properties: [
                    "attachmentID": .init(type: .string, description: "Attachment UUID from the current attachment manifest."),
                    "offset": .init(type: .integer, description: "Character offset to start reading from. Defaults to 0."),
                    "maxCharacters": .init(type: .integer, description: "Maximum characters returned, clamped to 1...20000. Defaults to 12000."),
                ],
                required: ["attachmentID"]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "attachmentID": .init(type: .string, description: "Attachment UUID."),
                    "fileName": .init(type: .string, description: "Attachment file name."),
                    "contentType": .init(type: .string, description: "Attachment MIME type."),
                    "byteCount": .init(type: .integer, description: "Attachment size in bytes."),
                    "text": .init(type: .string, description: "Extracted bounded text."),
                    "offset": .init(type: .integer, description: "Character offset used."),
                    "truncated": .init(type: .boolean, description: "Whether more text remains after this response."),
                    "note": .init(type: .string, description: "Optional note when text extraction is unavailable."),
                ],
                required: ["attachmentID", "fileName", "contentType", "byteCount", "text", "offset", "truncated"]
            ),
            permissions: [.files, .cloudContext],
            sideEffect: .none,
            networkPolicy: .noNetwork,
            timeoutSeconds: 10,
            explanationRequired: true
        ) { input in
            guard let id = UUID(uuidString: input.attachmentID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw AgentError.invalidToolArguments("attachment.read attachmentID must be a UUID from the current attachment manifest.")
            }
            guard let item = try await attachment(id) else {
                throw AgentError.permissionDenied("Attachment is not available to this agent run.")
            }
            return try await readAttachment(item, offset: input.offset, maxCharacters: input.maxCharacters)
        }
    }
}

public struct ConversationSearchInput: ToolInput, Equatable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

public struct ConversationSearchOutput: ToolOutput, Equatable {
    public let query: String
    public let results: [ConversationSearchResult]
    public let resultsJSON: String

    public init(query: String, results: [ConversationSearchResult]) {
        self.query = query
        self.results = results
        resultsJSON = (try? String(decoding: JSONEncoder().encode(results), as: UTF8.self)) ?? "[]"
    }
}

public enum ConversationSearchTool {
    public static let name = "conversation.search"

    public static func spec(repository: any ConversationRepository) throws -> ToolSpec<ConversationSearchInput, ConversationSearchOutput> {
        try ToolSpec(
            name: name,
            description: "Search the user's private local conversation history and return matching message snippets.",
            inputSchema: ToolIOSchema(
                properties: [
                    "query": .init(type: .string, description: "Search query for local conversation history."),
                    "limit": .init(type: .integer, description: "Maximum number of matching messages, clamped to 1...12. Defaults to 6."),
                ],
                required: ["query"]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "query": .init(type: .string, description: "Search query that was executed."),
                    "results": .init(type: .array, description: "Matching conversation messages."),
                    "resultsJSON": .init(type: .string, description: "Serialized matching conversation messages for models that prefer a string payload."),
                ],
                required: ["query", "results", "resultsJSON"]
            ),
            permissions: [.cloudContext],
            sideEffect: .none,
            networkPolicy: .noNetwork,
            timeoutSeconds: 10,
            explanationRequired: true
        ) { input in
            let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw AgentError.invalidToolArguments("conversation.search query must not be empty.")
            }
            let results = try await repository.searchConversations(query: query, limit: clamp(input.limit, defaultValue: 6, range: 1...12))
            return ConversationSearchOutput(query: query, results: results)
        }
    }
}

private func readVault(input: VaultReadInput, repository: any VaultRepository) async throws -> VaultReadOutput {
    let documents = try await repository.listDocuments()
    let requestedDocumentID = input.documentID.flatMap(UUID.init(uuidString:))
    let maxCharacters = clamp(input.maxCharacters, defaultValue: 12_000, range: 1...20_000)
    let chunkLimit = clamp(input.limit, defaultValue: 4, range: 1...12)

    if let requestedDocumentID {
        guard let document = documents.first(where: { $0.id == requestedDocumentID }) else {
            throw AgentError.invalidToolArguments("vault.read documentID was not found.")
        }
        let chunks = try await repository.chunks(documentID: requestedDocumentID)
        return try vaultReadOutput(
            document: document,
            chunks: selectVaultChunks(chunks, input: input, limit: chunkLimit),
            maxCharacters: maxCharacters
        )
    }

    if let chunkID = input.chunkID?.trimmingCharacters(in: .whitespacesAndNewlines), !chunkID.isEmpty {
        for document in documents {
            let chunks = try await repository.chunks(documentID: document.id)
            if let index = chunks.firstIndex(where: { $0.id == chunkID }) {
                let selected = Array(chunks[index..<min(chunks.endIndex, index + chunkLimit)])
                return try vaultReadOutput(document: document, chunks: selected, maxCharacters: maxCharacters)
            }
        }
        throw AgentError.invalidToolArguments("vault.read chunkID was not found.")
    }

    throw AgentError.invalidToolArguments("vault.read requires documentID or chunkID.")
}

private func selectVaultChunks(_ chunks: [VaultChunk], input: VaultReadInput, limit: Int) -> [VaultChunk] {
    if let chunkID = input.chunkID?.trimmingCharacters(in: .whitespacesAndNewlines),
       !chunkID.isEmpty,
       let index = chunks.firstIndex(where: { $0.id == chunkID }) {
        return Array(chunks[index..<min(chunks.endIndex, index + limit)])
    }

    let startOrdinal = max(0, input.startOrdinal ?? 0)
    return Array(chunks.filter { $0.ordinal >= startOrdinal }.prefix(limit))
}

private func vaultReadOutput(document: VaultDocumentRecord, chunks: [VaultChunk], maxCharacters: Int) throws -> VaultReadOutput {
    guard !chunks.isEmpty else {
        throw AgentError.invalidToolArguments("vault.read found no chunks for the requested range.")
    }
    var remaining = maxCharacters
    var truncated = false
    var readChunks = [VaultReadChunk]()
    var sections = [String]()

    for chunk in chunks where remaining > 0 {
        let text = truncate(chunk.text, maxCharacters: remaining)
        let chunkTruncated = text.count < chunk.text.count
        truncated = truncated || chunkTruncated
        remaining -= text.count
        readChunks.append(VaultReadChunk(chunkID: chunk.id, ordinal: chunk.ordinal, text: text, truncated: chunkTruncated))
        sections.append("[\(chunk.ordinal)] \(text)")
    }
    if readChunks.count < chunks.count {
        truncated = true
    }

    return VaultReadOutput(
        documentID: document.id.uuidString,
        documentTitle: document.title,
        chunks: readChunks,
        text: sections.joined(separator: "\n\n"),
        truncated: truncated
    )
}

private func readAttachment(_ attachment: ChatAttachment, offset: Int?, maxCharacters: Int?) async throws -> AttachmentReadOutput {
    guard let url = attachment.localURL, url.isFileURL else {
        throw AgentError.invalidToolArguments("attachment.read attachment file is not available locally.")
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw AgentError.invalidToolArguments("attachment.read attachment file no longer exists.")
    }

    let extraction = try await AttachmentTextExtractor.extractText(from: attachment, url: url)
    let start = max(0, offset ?? 0)
    let maxLength = clamp(maxCharacters, defaultValue: 12_000, range: 1...20_000)
    let bounded = slice(extraction.text, offset: start, maxCharacters: maxLength)
    return AttachmentReadOutput(
        attachmentID: attachment.id.uuidString,
        fileName: attachment.fileName,
        contentType: attachment.normalizedContentType,
        byteCount: attachment.byteCount,
        text: bounded.text,
        offset: start,
        truncated: bounded.truncated,
        note: extraction.note
    )
}

private enum AttachmentTextExtractor {
    static func extractText(from attachment: ChatAttachment, url: URL) async throws -> (text: String, note: String?) {
        switch attachment.cloudInputKind {
        case .textDocument:
            return (try String(contentsOf: url, encoding: .utf8), nil)
        case .pdf:
            return (try extractPDFText(from: url), nil)
        case .image:
            return ("", "Image attachments are not text-readable through attachment.read. Use a vision-capable model for visual content.")
        case .unsupported:
            return ("", "This attachment type is not text-readable through attachment.read.")
        }
    }

    private static func extractPDFText(from url: URL) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            throw AgentError.invalidToolArguments("attachment.read could not open the PDF.")
        }
        var pages = [String]()
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string, !text.isEmpty {
                pages.append("[Page \(index + 1)]\n\(text)")
            }
        }
        return pages.joined(separator: "\n\n")
        #else
        throw AgentError.invalidToolArguments("attachment.read PDF extraction is unavailable in this build.")
        #endif
    }
}

private func slice(_ text: String, offset: Int, maxCharacters: Int) -> (text: String, truncated: Bool) {
    guard offset < text.count else {
        return ("", false)
    }
    let startIndex = text.index(text.startIndex, offsetBy: offset)
    let available = text.distance(from: startIndex, to: text.endIndex)
    let length = min(maxCharacters, available)
    let endIndex = text.index(startIndex, offsetBy: length)
    return (String(text[startIndex..<endIndex]), length < available)
}

private func clamp(_ value: Int?, defaultValue: Int, range: ClosedRange<Int>) -> Int {
    min(max(value ?? defaultValue, range.lowerBound), range.upperBound)
}

private func truncate(_ text: String, maxCharacters: Int) -> String {
    guard text.count > maxCharacters else { return text }
    return String(text.prefix(max(0, maxCharacters)))
}
