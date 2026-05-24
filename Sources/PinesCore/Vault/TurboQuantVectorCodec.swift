import Foundation

public enum TurboQuantVectorCodecError: Error, Equatable, LocalizedError, Sendable {
    case emptyVector
    case nonFiniteValue(index: Int)
    case zeroMagnitude
    case dimensionMismatch(expected: Int, actual: Int)
    case malformedCode
    case unsupportedPreset(String)

    public var errorDescription: String? {
        switch self {
        case .emptyVector:
            "TurboQuant vectors must contain at least one dimension."
        case let .nonFiniteValue(index):
            "TurboQuant vectors cannot contain NaN or infinity at index \(index)."
        case .zeroMagnitude:
            "TurboQuant cannot encode a zero-magnitude vector."
        case let .dimensionMismatch(expected, actual):
            "TurboQuant dimension mismatch. Expected \(expected), received \(actual)."
        case .malformedCode:
            "TurboQuant code data is malformed."
        case let .unsupportedPreset(preset):
            "TurboQuant preset \(preset) is not supported by this client."
        }
    }
}

public struct TurboQuantVectorCode: Hashable, Codable, Sendable {
    public var codecVersion: Int
    public var preset: TurboQuantPreset
    public var dimensions: Int
    public var seed: UInt64
    public var norm: Float
    public var maxAbs: Float
    public var highPrecisionMask: Data
    public var packedIndices: Data

    public init(
        codecVersion: Int = TurboQuantVectorCodec.codecVersion,
        preset: TurboQuantPreset,
        dimensions: Int,
        seed: UInt64,
        norm: Float,
        maxAbs: Float,
        highPrecisionMask: Data,
        packedIndices: Data
    ) {
        self.codecVersion = codecVersion
        self.preset = preset
        self.dimensions = dimensions
        self.seed = seed
        self.norm = norm
        self.maxAbs = maxAbs
        self.highPrecisionMask = highPrecisionMask
        self.packedIndices = packedIndices
    }
}

public struct TurboQuantVectorCodec: Sendable {
    public static let codecVersion = 2
    public static let legacyJSONCodecVersion = 1
    private static let binaryMagic = Array("PNTQV2".utf8)

    public var preset: TurboQuantPreset
    public var seed: UInt64

    public init(
        preset: TurboQuantPreset = .vaultVectorDefault,
        seed: UInt64 = 0x7069_6e65_735f_7471
    ) {
        self.preset = preset
        self.seed = seed
    }

    public static func stableSeed(for identifier: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    public func encodeToData(_ vector: [Float]) throws -> Data {
        try Self.encodeBinary(encode(vector))
    }

    public func decode(data: Data) throws -> [Float] {
        try decode(Self.decodeCode(data: data))
    }

    public static func decodeCode(data: Data) throws -> TurboQuantVectorCode {
        if data.starts(with: binaryMagic) {
            return try decodeBinary(data)
        }
        return try JSONDecoder().decode(TurboQuantVectorCode.self, from: data)
    }

    public func encode(_ vector: [Float]) throws -> TurboQuantVectorCode {
        let norm = try validate(vector)
        let normalized = vector.map { $0 / norm }
        let rotated = rotate(normalized, seed: seed)
        let maxAbs = rotated.reduce(Float(0)) { max($0, abs($1)) }
        guard maxAbs > 0 else {
            throw TurboQuantVectorCodecError.zeroMagnitude
        }

        let highPrecisionMask = highPrecisionMask(for: rotated)
        var writer = BitWriter()
        for index in rotated.indices {
            let bits = bitWidth(forHighPrecision: Self.bitIsSet(in: highPrecisionMask, index: index))
            let levels = (1 << bits) - 1
            let scaled = min(max(rotated[index] / maxAbs, -1), 1)
            let code = Int((Float(levels) * (scaled + 1) / 2).rounded())
            writer.append(code, bitCount: bits)
        }

        return TurboQuantVectorCode(
            preset: preset,
            dimensions: vector.count,
            seed: seed,
            norm: norm,
            maxAbs: maxAbs,
            highPrecisionMask: highPrecisionMask,
            packedIndices: writer.data()
        )
    }

    public func decode(_ code: TurboQuantVectorCode) throws -> [Float] {
        var output = [Float]()
        try decode(code, into: &output)
        return output
    }

    public func decode(_ code: TurboQuantVectorCode, into output: inout [Float]) throws {
        guard (code.codecVersion == Self.codecVersion || code.codecVersion == Self.legacyJSONCodecVersion),
              code.dimensions > 0,
              code.maxAbs.isFinite else {
            throw TurboQuantVectorCodecError.malformedCode
        }

        output.removeAll(keepingCapacity: true)
        output.append(contentsOf: repeatElement(Float(0), count: code.dimensions))

        let (stride, offset) = permutationParameters(dimension: code.dimensions, seed: code.seed)
        let inverseStride = modularInverse(stride, modulo: code.dimensions)
        var reader = BitReader(data: code.packedIndices)
        var decodedSquaredMagnitude = Float(0)
        for rotatedIndex in 0..<code.dimensions {
            let highPrecision = Self.bitIsSet(in: code.highPrecisionMask, index: rotatedIndex)
            let bits = bitWidth(forHighPrecision: highPrecision, preset: code.preset)
            guard let raw = reader.read(bitCount: bits) else {
                throw TurboQuantVectorCodecError.malformedCode
            }
            let levels = Float((1 << bits) - 1)
            let rotatedValue = ((Float(raw) / levels) * 2 - 1) * code.maxAbs
            let originalIndex = positiveModulo((rotatedIndex - offset) * inverseStride, code.dimensions)
            let decoded = sign(index: originalIndex, seed: code.seed) * rotatedValue
            output[originalIndex] = decoded
            decodedSquaredMagnitude += decoded * decoded
        }

        let decodedNorm = decodedSquaredMagnitude.squareRoot()
        guard decodedNorm > 0 else {
            throw TurboQuantVectorCodecError.zeroMagnitude
        }
        for index in output.indices {
            output[index] /= decodedNorm
        }
    }

    public func approximateCosineSimilarity(query: [Float], code: TurboQuantVectorCode) throws -> Double {
        var decodeBuffer = [Float]()
        return try approximateCosineSimilarity(query: query, code: code, decodeBuffer: &decodeBuffer)
    }

    public func approximateCosineSimilarity(
        query: [Float],
        code: TurboQuantVectorCode,
        decodeBuffer: inout [Float]
    ) throws -> Double {
        guard query.count == code.dimensions else {
            throw TurboQuantVectorCodecError.dimensionMismatch(expected: code.dimensions, actual: query.count)
        }
        let queryNorm = try validate(query)
        try decode(code, into: &decodeBuffer)
        let dot = zip(query, decodeBuffer).reduce(Float(0)) { partial, pair in
            partial + pair.0 * pair.1
        }
        return Double(dot / queryNorm)
    }

    public func approximateCosineSimilarity(query: [Float], codeData: Data) throws -> Double {
        let code = try Self.decodeCode(data: codeData)
        return try approximateCosineSimilarity(query: query, code: code)
    }

    private static func encodeBinary(_ code: TurboQuantVectorCode) throws -> Data {
        var data = Data(binaryMagic)
        data.append(UInt8(code.codecVersion))
        appendUInt32(UInt32(code.dimensions), to: &data)
        appendUInt64(code.seed, to: &data)
        appendUInt32(code.norm.bitPattern, to: &data)
        appendUInt32(code.maxAbs.bitPattern, to: &data)
        let presetBytes = Array(code.preset.rawValue.utf8)
        guard presetBytes.count <= UInt8.max else {
            throw TurboQuantVectorCodecError.malformedCode
        }
        data.append(UInt8(presetBytes.count))
        data.append(contentsOf: presetBytes)
        appendUInt32(UInt32(code.highPrecisionMask.count), to: &data)
        data.append(code.highPrecisionMask)
        appendUInt32(UInt32(code.packedIndices.count), to: &data)
        data.append(code.packedIndices)
        return data
    }

    private static func decodeBinary(_ data: Data) throws -> TurboQuantVectorCode {
        var reader = BinaryVectorCodeReader(data: data)
        guard reader.readBytes(count: binaryMagic.count) == binaryMagic,
              let version = reader.readUInt8(),
              let dimensions = reader.readUInt32(),
              let seed = reader.readUInt64(),
              let normBits = reader.readUInt32(),
              let maxAbsBits = reader.readUInt32(),
              let presetLength = reader.readUInt8(),
              let presetBytes = reader.readBytes(count: Int(presetLength)),
              let presetName = String(bytes: presetBytes, encoding: .utf8),
              let preset = TurboQuantPreset(rawValue: presetName),
              let maskLength = reader.readUInt32(),
              let maskBytes = reader.readBytes(count: Int(maskLength)),
              let packedLength = reader.readUInt32(),
              let packedBytes = reader.readBytes(count: Int(packedLength)),
              reader.isAtEnd else {
            throw TurboQuantVectorCodecError.malformedCode
        }
        guard version == UInt8(codecVersion) else {
            throw TurboQuantVectorCodecError.malformedCode
        }
        return TurboQuantVectorCode(
            codecVersion: Int(version),
            preset: preset,
            dimensions: Int(dimensions),
            seed: seed,
            norm: Float(bitPattern: normBits),
            maxAbs: Float(bitPattern: maxAbsBits),
            highPrecisionMask: Data(maskBytes),
            packedIndices: Data(packedBytes)
        )
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt64(_ value: UInt64, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func validate(_ vector: [Float]) throws -> Float {
        guard !vector.isEmpty else {
            throw TurboQuantVectorCodecError.emptyVector
        }
        var sum = Float(0)
        for (index, value) in vector.enumerated() {
            guard value.isFinite else {
                throw TurboQuantVectorCodecError.nonFiniteValue(index: index)
            }
            sum += value * value
        }
        guard sum > 0 else {
            throw TurboQuantVectorCodecError.zeroMagnitude
        }
        return sum.squareRoot()
    }

    private func highPrecisionMask(for vector: [Float]) -> Data {
        let highPrecisionCount = max(1, vector.count / 2)
        let rankedIndices = vector.indices.sorted { lhs, rhs in
            let lhsMagnitude = abs(vector[lhs])
            let rhsMagnitude = abs(vector[rhs])
            if lhsMagnitude == rhsMagnitude {
                return lhs < rhs
            }
            return lhsMagnitude > rhsMagnitude
        }

        var mask = Data(repeating: 0, count: (vector.count + 7) / 8)
        for index in rankedIndices.prefix(highPrecisionCount) {
            Self.setBit(in: &mask, index: index)
        }
        return mask
    }

    private func bitWidth(forHighPrecision highPrecision: Bool) -> Int {
        bitWidth(forHighPrecision: highPrecision, preset: preset)
    }

    private func bitWidth(forHighPrecision highPrecision: Bool, preset: TurboQuantPreset) -> Int {
        highPrecision ? preset.outlierBits : preset.baseBits
    }

    private func rotate(_ vector: [Float], seed: UInt64) -> [Float] {
        let dimension = vector.count
        var output = Array(repeating: Float(0), count: dimension)
        for index in 0..<dimension {
            let destination = permutationIndex(index, dimension: dimension, seed: seed)
            output[destination] = sign(index: index, seed: seed) * vector[index]
        }
        return output
    }

    private func inverseRotate(_ vector: [Float], seed: UInt64) -> [Float] {
        let dimension = vector.count
        var output = Array(repeating: Float(0), count: dimension)
        for index in 0..<dimension {
            let source = permutationIndex(index, dimension: dimension, seed: seed)
            output[index] = sign(index: index, seed: seed) * vector[source]
        }
        return output
    }

    private func permutationIndex(_ index: Int, dimension: Int, seed: UInt64) -> Int {
        guard dimension > 1 else {
            return 0
        }

        let (stride, offset) = permutationParameters(dimension: dimension, seed: seed)
        return (index * stride + offset) % dimension
    }

    private func permutationParameters(dimension: Int, seed: UInt64) -> (stride: Int, offset: Int) {
        var stride = Int(splitMix64(seed ^ 0xa076_1d64_78bd_642f) % UInt64(dimension))
        if stride == 0 {
            stride = 1
        }
        while gcd(stride, dimension) != 1 {
            stride += 1
            if stride >= dimension {
                stride = 1
            }
        }
        let offset = Int(splitMix64(seed ^ 0xe703_7ed1_a0b4_28db) % UInt64(dimension))
        return (stride, offset)
    }

    private func modularInverse(_ value: Int, modulo: Int) -> Int {
        var t = 0
        var newT = 1
        var r = modulo
        var newR = value
        while newR != 0 {
            let quotient = r / newR
            (t, newT) = (newT, t - quotient * newT)
            (r, newR) = (newR, r - quotient * newR)
        }
        return positiveModulo(t, modulo)
    }

    private func positiveModulo(_ value: Int, _ modulo: Int) -> Int {
        let remainder = value % modulo
        return remainder >= 0 ? remainder : remainder + modulo
    }

    private func sign(index: Int, seed: UInt64) -> Float {
        (splitMix64(seed &+ UInt64(index) &* 0x9e37_79b9_7f4a_7c15) & 1) == 0 ? 1 : -1
    }

    private func magnitude(_ vector: [Float]) -> Float {
        vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
    }

    private func gcd(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return a
    }

    private func splitMix64(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9e37_79b9_7f4a_7c15
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    private static func setBit(in data: inout Data, index: Int) {
        data[index / 8] |= UInt8(1 << (index % 8))
    }

    private static func bitIsSet(in data: Data, index: Int) -> Bool {
        guard index / 8 < data.count else {
            return false
        }
        return (data[index / 8] & UInt8(1 << (index % 8))) != 0
    }
}

private struct BitWriter {
    private var bytes = [UInt8]()
    private var currentByte: UInt8 = 0
    private var bitOffset = 0

    mutating func append(_ value: Int, bitCount: Int) {
        for bit in 0..<bitCount {
            if ((value >> bit) & 1) == 1 {
                currentByte |= UInt8(1 << bitOffset)
            }
            bitOffset += 1
            if bitOffset == 8 {
                bytes.append(currentByte)
                currentByte = 0
                bitOffset = 0
            }
        }
    }

    mutating func data() -> Data {
        if bitOffset > 0 {
            bytes.append(currentByte)
            currentByte = 0
            bitOffset = 0
        }
        return Data(bytes)
    }
}

private struct BitReader {
    let data: Data
    private var bitIndex = 0

    init(data: Data) {
        self.data = data
    }

    mutating func read(bitCount: Int) -> Int? {
        guard bitCount >= 0, bitIndex + bitCount <= data.count * 8 else {
            return nil
        }
        var value = 0
        for bit in 0..<bitCount {
            let sourceIndex = bitIndex + bit
            let byte = data[sourceIndex / 8]
            if (byte & UInt8(1 << (sourceIndex % 8))) != 0 {
                value |= 1 << bit
            }
        }
        bitIndex += bitCount
        return value
    }
}

private struct BinaryVectorCodeReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    var isAtEnd: Bool {
        offset == bytes.count
    }

    mutating func readUInt8() -> UInt8? {
        guard offset < bytes.count else {
            return nil
        }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt32() -> UInt32? {
        guard let value = readFixedWidthInteger(UInt32.self) else {
            return nil
        }
        return UInt32(littleEndian: value)
    }

    mutating func readUInt64() -> UInt64? {
        guard let value = readFixedWidthInteger(UInt64.self) else {
            return nil
        }
        return UInt64(littleEndian: value)
    }

    mutating func readBytes(count: Int) -> [UInt8]? {
        guard count >= 0, offset + count <= bytes.count else {
            return nil
        }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    private mutating func readFixedWidthInteger<T: FixedWidthInteger>(_ type: T.Type) -> T? {
        let count = MemoryLayout<T>.size
        guard offset + count <= bytes.count else {
            return nil
        }
        var value: T = 0
        for byteOffset in 0..<count {
            value |= T(bytes[offset + byteOffset]) << T(byteOffset * 8)
        }
        offset += count
        _ = type
        return value
    }
}
