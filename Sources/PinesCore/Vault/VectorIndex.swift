import Foundation

public enum VectorIndexError: Error, Equatable, LocalizedError, Sendable {
    case duplicateID(String)
    case emptyVector
    case zeroMagnitude
    case nonFiniteValue(index: Int)
    case dimensionMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case let .duplicateID(id):
            "A vector with id '\(id)' already exists."
        case .emptyVector:
            "Vectors must contain at least one dimension."
        case .zeroMagnitude:
            "Cosine search cannot index or query a zero-magnitude vector."
        case let .nonFiniteValue(index):
            "Vectors cannot contain NaN or infinity at index \(index)."
        case let .dimensionMismatch(expected, actual):
            "Vector dimension mismatch. Expected \(expected), received \(actual)."
        }
    }
}

public typealias VectorSearchError = VectorIndexError
public typealias CosineVectorIndex = VectorIndex

public struct VectorEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let vector: [Double]
    public let metadata: [String: String]

    public var chunkID: String? {
        metadata["chunkID"]
    }

    public init(id: String, vector: [Double], metadata: [String: String] = [:]) {
        self.id = id
        self.vector = vector
        self.metadata = metadata
    }

    public init(id: String, chunkID: String, vector: [Double], metadata: [String: String] = [:]) {
        var metadata = metadata
        metadata["chunkID"] = chunkID
        self.init(id: id, vector: vector, metadata: metadata)
    }

    public init(id: String, vector: [Float], metadata: [String: String] = [:]) {
        self.init(id: id, vector: vector.map(Double.init), metadata: metadata)
    }

    public init(id: String, chunkID: String, vector: [Float], metadata: [String: String] = [:]) {
        self.init(id: id, chunkID: chunkID, vector: vector.map(Double.init), metadata: metadata)
    }
}

public struct VectorSearchResult: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String {
        entry.id
    }

    public let entry: VectorEntry
    public let score: Double

    public init(entry: VectorEntry, score: Double) {
        self.entry = entry
        self.score = score
    }
}

public struct VectorIndex: Codable, Equatable, Sendable {
    private struct IndexedVector: Codable, Equatable, Sendable {
        let entry: VectorEntry
        let magnitude: Double
    }

    public private(set) var dimension: Int?
    private var indexedVectors: [IndexedVector]

    public var count: Int {
        indexedVectors.count
    }

    public var isEmpty: Bool {
        indexedVectors.isEmpty
    }

    public var entries: [VectorEntry] {
        indexedVectors.map(\.entry)
    }

    public init() {
        dimension = nil
        indexedVectors = []
    }

    public init(entries: [VectorEntry]) throws {
        self.init()

        for entry in entries {
            try insert(entry)
        }
    }

    public func entry(id: String) -> VectorEntry? {
        indexedVectors.first { $0.entry.id == id }?.entry
    }

    public mutating func insert(_ entry: VectorEntry) throws {
        guard self.entry(id: entry.id) == nil else {
            throw VectorIndexError.duplicateID(entry.id)
        }

        let magnitude = try validate(entry.vector)
        try validateDimension(entry.vector.count)

        indexedVectors.append(IndexedVector(entry: entry, magnitude: magnitude))
    }

    public mutating func add(_ entry: VectorEntry) throws {
        try insert(entry)
    }

    public mutating func insert(id: String, vector: [Double], metadata: [String: String] = [:]) throws {
        try insert(VectorEntry(id: id, vector: vector, metadata: metadata))
    }

    public mutating func insert(id: String, vector: [Float], metadata: [String: String] = [:]) throws {
        try insert(VectorEntry(id: id, vector: vector, metadata: metadata))
    }

    public mutating func add(id: String, vector: [Double], metadata: [String: String] = [:]) throws {
        try insert(id: id, vector: vector, metadata: metadata)
    }

    public mutating func add(id: String, vector: [Float], metadata: [String: String] = [:]) throws {
        try insert(id: id, vector: vector, metadata: metadata)
    }

    public mutating func upsert(_ entry: VectorEntry) throws {
        let magnitude = try validate(entry.vector)

        if let index = indexedVectors.firstIndex(where: { $0.entry.id == entry.id }) {
            guard entry.vector.count == indexedVectors[index].entry.vector.count else {
                throw VectorIndexError.dimensionMismatch(
                    expected: indexedVectors[index].entry.vector.count,
                    actual: entry.vector.count
                )
            }

            indexedVectors[index] = IndexedVector(entry: entry, magnitude: magnitude)
            return
        }

        try validateDimension(entry.vector.count)
        indexedVectors.append(IndexedVector(entry: entry, magnitude: magnitude))
    }

    public mutating func upsert(id: String, vector: [Double], metadata: [String: String] = [:]) throws {
        try upsert(VectorEntry(id: id, vector: vector, metadata: metadata))
    }

    public mutating func upsert(id: String, vector: [Float], metadata: [String: String] = [:]) throws {
        try upsert(VectorEntry(id: id, vector: vector, metadata: metadata))
    }

    @discardableResult
    public mutating func remove(id: String) -> VectorEntry? {
        guard let index = indexedVectors.firstIndex(where: { $0.entry.id == id }) else {
            return nil
        }

        let removed = indexedVectors.remove(at: index).entry

        if indexedVectors.isEmpty {
            dimension = nil
        }

        return removed
    }

    public func search(_ query: [Double], limit: Int = 10) throws -> [VectorSearchResult] {
        try search(query: query, limit: limit)
    }

    public func nearest(to query: [Double], limit: Int = 10) throws -> [VectorSearchResult] {
        try search(query: query, limit: limit)
    }

    public func search(query: [Double], limit: Int = 10) throws -> [VectorSearchResult] {
        guard limit > 0 else {
            return []
        }

        let queryMagnitude = try validate(query)

        guard let dimension else {
            return []
        }

        guard query.count == dimension else {
            throw VectorIndexError.dimensionMismatch(expected: dimension, actual: query.count)
        }

        return indexedVectors
            .map { indexedVector in
                VectorSearchResult(
                    entry: indexedVector.entry,
                    score: dotProduct(indexedVector.entry.vector, query) / (indexedVector.magnitude * queryMagnitude)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.entry.id < rhs.entry.id
                }

                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    public func search(query: [Double], topK: Int) throws -> [VectorSearchResult] {
        try search(query: query, limit: topK)
    }

    public func search(_ query: [Float], limit: Int = 10) throws -> [VectorSearchResult] {
        try search(query: query.map(Double.init), limit: limit)
    }

    public func nearest(to query: [Float], limit: Int = 10) throws -> [VectorSearchResult] {
        try search(query: query.map(Double.init), limit: limit)
    }

    public func search(query: [Float], limit: Int = 10) throws -> [VectorSearchResult] {
        try search(query.map(Double.init), limit: limit)
    }

    public func search(query: [Float], topK: Int) throws -> [VectorSearchResult] {
        try search(query: query.map(Double.init), limit: topK)
    }

    private mutating func validateDimension(_ actual: Int) throws {
        if let dimension {
            guard dimension == actual else {
                throw VectorIndexError.dimensionMismatch(expected: dimension, actual: actual)
            }
        } else {
            dimension = actual
        }
    }

    private func validate(_ vector: [Double]) throws -> Double {
        guard !vector.isEmpty else {
            throw VectorIndexError.emptyVector
        }

        var squaredMagnitude = 0.0

        for (index, value) in vector.enumerated() {
            guard value.isFinite else {
                throw VectorIndexError.nonFiniteValue(index: index)
            }

            squaredMagnitude += value * value
        }

        guard squaredMagnitude > 0 else {
            throw VectorIndexError.zeroMagnitude
        }

        return squaredMagnitude.squareRoot()
    }

    private func dotProduct(_ lhs: [Double], _ rhs: [Double]) -> Double {
        zip(lhs, rhs).reduce(into: 0.0) { partialResult, pair in
            partialResult += pair.0 * pair.1
        }
    }
}
