import Foundation

public struct VaultChunk: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let sourceID: String
    public let ordinal: Int
    public let text: String
    public let startOffset: Int
    public let endOffset: Int
    public let checksum: String

    public var characterCount: Int {
        endOffset - startOffset
    }

    public var characterRange: Range<Int> {
        startOffset..<endOffset
    }

    public var sourceId: String {
        sourceID
    }

    public init(
        id: String,
        sourceID: String,
        ordinal: Int,
        text: String,
        startOffset: Int,
        endOffset: Int,
        checksum: String
    ) {
        self.id = id
        self.sourceID = sourceID
        self.ordinal = ordinal
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.checksum = checksum
    }
}

enum StableVaultHash {
    private static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    static func hexDigest(for text: String) -> String {
        var hash = offsetBasis

        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return String(format: "%016llx", hash)
    }
}
