import Foundation

public struct VaultChunker: Sendable {
    public struct Configuration: Equatable, Hashable, Sendable {
        public let maxCharacterCount: Int
        public let overlapCharacterCount: Int

        public var maxCharacters: Int {
            maxCharacterCount
        }

        public var overlapCharacters: Int {
            overlapCharacterCount
        }

        public init(maxCharacterCount: Int = 1_200, overlapCharacterCount: Int = 160) {
            precondition(maxCharacterCount > 0, "maxCharacterCount must be greater than zero")
            precondition(overlapCharacterCount >= 0, "overlapCharacterCount cannot be negative")
            precondition(
                overlapCharacterCount < maxCharacterCount,
                "overlapCharacterCount must be smaller than maxCharacterCount"
            )

            self.maxCharacterCount = maxCharacterCount
            self.overlapCharacterCount = overlapCharacterCount
        }

        public init(maxCharacters: Int, overlapCharacters: Int) {
            self.init(maxCharacterCount: maxCharacters, overlapCharacterCount: overlapCharacters)
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func chunks(for text: String, sourceID: String) -> [VaultChunk] {
        chunk(text, sourceID: sourceID)
    }

    public func chunks(from text: String, sourceID: String) -> [VaultChunk] {
        chunk(text, sourceID: sourceID)
    }

    public func chunks(sourceID: String, text: String) -> [VaultChunk] {
        chunk(text, sourceID: sourceID)
    }

    public func chunk(text: String, sourceID: String) -> [VaultChunk] {
        chunk(text, sourceID: sourceID)
    }

    public func chunk(_ text: String, sourceID: String) -> [VaultChunk] {
        let normalizedText = normalizeLineEndings(in: text)
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var chunks: [VaultChunk] = []
        var start = normalizedText.startIndex

        while start < normalizedText.endIndex {
            let proposedEnd = normalizedText.index(
                start,
                offsetBy: configuration.maxCharacterCount,
                limitedBy: normalizedText.endIndex
            ) ?? normalizedText.endIndex
            let end = preferredEnd(in: normalizedText, start: start, proposedEnd: proposedEnd)

            if let bounds = trimmedBounds(in: normalizedText, start: start, end: end) {
                chunks.append(
                    makeChunk(
                        sourceID: sourceID,
                        ordinal: chunks.count,
                        text: normalizedText,
                        bounds: bounds
                    )
                )
            }

            guard end < normalizedText.endIndex else {
                break
            }

            let overlappedStart = normalizedText.index(
                end,
                offsetBy: -configuration.overlapCharacterCount,
                limitedBy: start
            ) ?? end
            start = overlappedStart > start ? overlappedStart : end
        }

        return chunks
    }

    private func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func preferredEnd(in text: String, start: String.Index, proposedEnd: String.Index) -> String.Index {
        guard proposedEnd < text.endIndex else {
            return proposedEnd
        }

        let minimumDistance = max(configuration.maxCharacterCount / 2, 1)
        let minimumEnd = text.index(start, offsetBy: minimumDistance, limitedBy: proposedEnd) ?? proposedEnd
        var cursor = proposedEnd

        while cursor > minimumEnd {
            let previous = text.index(before: cursor)
            let character = text[previous]

            if character == "\n" {
                return cursor
            }

            if character.isWhitespace {
                return previous
            }

            if ".!?;:".contains(character) {
                return cursor
            }

            cursor = previous
        }

        return proposedEnd
    }

    private func trimmedBounds(
        in text: String,
        start: String.Index,
        end: String.Index
    ) -> (start: String.Index, end: String.Index)? {
        var lower = start
        var upper = end

        while lower < upper, text[lower].isWhitespace {
            lower = text.index(after: lower)
        }

        while upper > lower {
            let previous = text.index(before: upper)
            guard text[previous].isWhitespace else {
                break
            }
            upper = previous
        }

        guard lower < upper else {
            return nil
        }

        return (lower, upper)
    }

    private func makeChunk(
        sourceID: String,
        ordinal: Int,
        text: String,
        bounds: (start: String.Index, end: String.Index)
    ) -> VaultChunk {
        let chunkText = String(text[bounds.start..<bounds.end])
        let checksum = StableVaultHash.hexDigest(for: chunkText)
        let stableIDInput = "\(sourceID)|\(ordinal)|\(checksum)"

        return VaultChunk(
            id: "chunk_\(StableVaultHash.hexDigest(for: stableIDInput))",
            sourceID: sourceID,
            ordinal: ordinal,
            text: chunkText,
            startOffset: text.distance(from: text.startIndex, to: bounds.start),
            endOffset: text.distance(from: text.startIndex, to: bounds.end),
            checksum: checksum
        )
    }
}
