import CryptoKit
import Foundation

public struct TurboQuantFallbackContract: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var mode: TurboQuantUserMode
    public var allowPackedFallback: Bool
    public var allowDecodedLayerLocalFallback: Bool
    public var allowFullDecodedFallback: Bool
    public var allowShorterContextRetry: Bool
    public var allowCloudRetry: Bool
    public var failIfCompressedPathUnavailable: Bool
    public var reserveBytes: Int64

    public var contractHash: String {
        Self.sha256Hex(
            for: ContractHashPayload(
                allowCloudRetry: allowCloudRetry,
                allowDecodedLayerLocalFallback: allowDecodedLayerLocalFallback,
                allowFullDecodedFallback: allowFullDecodedFallback,
                allowPackedFallback: allowPackedFallback,
                allowShorterContextRetry: allowShorterContextRetry,
                failIfCompressedPathUnavailable: failIfCompressedPathUnavailable,
                mode: mode,
                reserveBytes: reserveBytes,
                schemaVersion: schemaVersion
            )
        )
    }

    public var policyHash: String {
        Self.sha256Hex(
            for: PolicyHashPayload(
                allowCloudRetry: allowCloudRetry,
                allowDecodedLayerLocalFallback: allowDecodedLayerLocalFallback,
                allowFullDecodedFallback: allowFullDecodedFallback,
                allowPackedFallback: allowPackedFallback,
                allowShorterContextRetry: allowShorterContextRetry,
                failIfCompressedPathUnavailable: failIfCompressedPathUnavailable,
                mode: mode,
                schemaVersion: schemaVersion
            )
        )
    }

    public init(
        schemaVersion: Int = Self.schemaVersion,
        mode: TurboQuantUserMode,
        allowPackedFallback: Bool,
        allowDecodedLayerLocalFallback: Bool,
        allowFullDecodedFallback: Bool,
        allowShorterContextRetry: Bool,
        allowCloudRetry: Bool,
        failIfCompressedPathUnavailable: Bool,
        reserveBytes: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.allowPackedFallback = allowPackedFallback
        self.allowDecodedLayerLocalFallback = allowDecodedLayerLocalFallback
        self.allowFullDecodedFallback = allowFullDecodedFallback
        self.allowShorterContextRetry = allowShorterContextRetry
        self.allowCloudRetry = allowCloudRetry
        self.failIfCompressedPathUnavailable = failIfCompressedPathUnavailable
        self.reserveBytes = max(0, reserveBytes)
    }

    public static func productDefault(
        for mode: TurboQuantUserMode,
        allowCloudRetry: Bool = false,
        reserveBytes overrideReserveBytes: Int64? = nil
    ) -> Self {
        let reserveBytes = overrideReserveBytes ?? defaultReserveBytes(for: mode)

        switch mode {
        case .fastest:
            return Self(
                mode: mode,
                allowPackedFallback: true,
                allowDecodedLayerLocalFallback: false,
                allowFullDecodedFallback: false,
                allowShorterContextRetry: true,
                allowCloudRetry: allowCloudRetry,
                failIfCompressedPathUnavailable: false,
                reserveBytes: reserveBytes
            )
        case .balanced:
            return Self(
                mode: mode,
                allowPackedFallback: true,
                allowDecodedLayerLocalFallback: true,
                allowFullDecodedFallback: false,
                allowShorterContextRetry: true,
                allowCloudRetry: allowCloudRetry,
                failIfCompressedPathUnavailable: false,
                reserveBytes: reserveBytes
            )
        case .maxContext:
            return Self(
                mode: mode,
                allowPackedFallback: false,
                allowDecodedLayerLocalFallback: false,
                allowFullDecodedFallback: false,
                allowShorterContextRetry: true,
                allowCloudRetry: allowCloudRetry,
                failIfCompressedPathUnavailable: true,
                reserveBytes: reserveBytes
            )
        case .batterySaver:
            return Self(
                mode: mode,
                allowPackedFallback: false,
                allowDecodedLayerLocalFallback: false,
                allowFullDecodedFallback: false,
                allowShorterContextRetry: true,
                allowCloudRetry: allowCloudRetry,
                failIfCompressedPathUnavailable: false,
                reserveBytes: reserveBytes
            )
        }
    }

    public static func defaultReserveBytes(for mode: TurboQuantUserMode) -> Int64 {
        switch mode {
        case .fastest:
            128 * 1_024 * 1_024
        case .balanced:
            512 * 1_024 * 1_024
        case .maxContext:
            64 * 1_024 * 1_024
        case .batterySaver:
            64 * 1_024 * 1_024
        }
    }

    public func shorterContextDowngradePath() -> [TurboQuantModeDowngrade] {
        guard allowShorterContextRetry else {
            return []
        }

        switch mode {
        case .fastest:
            return [
                TurboQuantModeDowngrade(mode: .fastest, reason: .shorterContextRetry),
                TurboQuantModeDowngrade(mode: .batterySaver, reason: .batterySaverShorterContext),
            ]
        case .balanced:
            return [
                TurboQuantModeDowngrade(mode: .balanced, reason: .shorterContextRetry),
                TurboQuantModeDowngrade(mode: .batterySaver, reason: .batterySaverShorterContext),
            ]
        case .maxContext:
            return [
                TurboQuantModeDowngrade(mode: .maxContext, reason: .shorterContextRetry),
                TurboQuantModeDowngrade(mode: .balanced, reason: .balancedShorterContext),
                TurboQuantModeDowngrade(mode: .batterySaver, reason: .batterySaverShorterContext),
            ]
        case .batterySaver:
            return [
                TurboQuantModeDowngrade(mode: .batterySaver, reason: .shorterContextRetry),
            ]
        }
    }

    public func permitsFullDecodedFallback(budgetedDecodedFallbackBytes: Int64) -> Bool {
        allowFullDecodedFallback
            && budgetedDecodedFallbackBytes > 0
            && reserveBytes >= budgetedDecodedFallbackBytes
    }

    private static func sha256Hex<Payload: Encodable>(for payload: Payload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(payload) else {
            preconditionFailure("TurboQuantFallbackContract canonical JSON encoding failed")
        }

        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct TurboQuantModeDowngrade: Hashable, Codable, Sendable {
    public var mode: TurboQuantUserMode
    public var requiresShorterContext: Bool
    public var reason: TurboQuantModeDowngradeReason
    public var downgradeReason: String
    public var userFacingMessage: String

    public init(
        mode: TurboQuantUserMode,
        requiresShorterContext: Bool = true,
        reason: TurboQuantModeDowngradeReason
    ) {
        self.mode = mode
        self.requiresShorterContext = requiresShorterContext
        self.reason = reason
        self.downgradeReason = reason.rawValue
        self.userFacingMessage = reason.userFacingMessage(for: mode)
    }
}

public enum TurboQuantModeDowngradeReason: String, Hashable, Codable, Sendable, CaseIterable {
    case shorterContextRetry
    case balancedShorterContext
    case batterySaverShorterContext

    public func userFacingMessage(for mode: TurboQuantUserMode) -> String {
        switch self {
        case .shorterContextRetry:
            "Reduced local context for \(mode.displayName)."
        case .balancedShorterContext:
            "Reduced local context and moved to Balanced."
        case .batterySaverShorterContext:
            "Reduced local context and moved to Battery Saver."
        }
    }
}

private struct ContractHashPayload: Encodable {
    var allowCloudRetry: Bool
    var allowDecodedLayerLocalFallback: Bool
    var allowFullDecodedFallback: Bool
    var allowPackedFallback: Bool
    var allowShorterContextRetry: Bool
    var failIfCompressedPathUnavailable: Bool
    var mode: TurboQuantUserMode
    var reserveBytes: Int64
    var schemaVersion: Int
}

private struct PolicyHashPayload: Encodable {
    var allowCloudRetry: Bool
    var allowDecodedLayerLocalFallback: Bool
    var allowFullDecodedFallback: Bool
    var allowPackedFallback: Bool
    var allowShorterContextRetry: Bool
    var failIfCompressedPathUnavailable: Bool
    var mode: TurboQuantUserMode
    var schemaVersion: Int
}
