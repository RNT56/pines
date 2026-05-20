import CryptoKit
import Foundation

public enum InstallBoundSecretEnvelopeError: Error, LocalizedError, Sendable {
    case invalidInstallKeyLength
    case notAnEnvelope
    case malformedEnvelope
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidInstallKeyLength:
            "Install binding key must be 32 bytes."
        case .notAnEnvelope:
            "Secret data is not install-bound."
        case .malformedEnvelope:
            "Install-bound secret data is malformed."
        case .authenticationFailed:
            "Install-bound secret could not be authenticated."
        }
    }
}

public enum InstallBoundSecretEnvelope {
    private static let magic = Data("pines.install-bound-secret.v1\n".utf8)
    public static let installKeyByteCount = 32

    public static func isEnvelope(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    public static func seal(_ plaintext: Data, installKey: Data, context: String) throws -> Data {
        guard installKey.count == installKeyByteCount else {
            throw InstallBoundSecretEnvelopeError.invalidInstallKeyLength
        }
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: installKey),
            authenticating: Data(context.utf8)
        )
        guard let combined = sealed.combined else {
            throw InstallBoundSecretEnvelopeError.malformedEnvelope
        }
        return magic + combined
    }

    public static func open(_ data: Data, installKey: Data, context: String) throws -> Data {
        guard installKey.count == installKeyByteCount else {
            throw InstallBoundSecretEnvelopeError.invalidInstallKeyLength
        }
        guard isEnvelope(data) else {
            throw InstallBoundSecretEnvelopeError.notAnEnvelope
        }
        let body = data.dropFirst(magic.count)
        guard body.count > 28 else {
            throw InstallBoundSecretEnvelopeError.malformedEnvelope
        }
        do {
            let sealed = try AES.GCM.SealedBox(combined: Data(body))
            return try AES.GCM.open(
                sealed,
                using: SymmetricKey(data: installKey),
                authenticating: Data(context.utf8)
            )
        } catch {
            throw InstallBoundSecretEnvelopeError.authenticationFailed
        }
    }
}
