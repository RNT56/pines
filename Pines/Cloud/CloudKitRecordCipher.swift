import CryptoKit
import Foundation

struct CloudKitEncryptedPayload: Hashable, Codable, Sendable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var keyID: String
    var nonce: Data
    var ciphertext: Data
    var tag: Data
    var updatedAt: Date
    var tombstone: Bool
}

struct CloudKitRecordCipher: Sendable {
    let secureKeyStore: SecureKeyStore

    func seal<Payload: Encodable>(
        _ payload: Payload,
        recordType: String,
        recordName: String,
        updatedAt: Date,
        tombstone: Bool = false
    ) async throws -> CloudKitEncryptedPayload {
        let key = try await secureKeyStore.dataKey(purpose: .cloudKitE2E, keyID: SecureKeyStore.cloudKitKeyID)
        let data = try JSONEncoder().encode(payload)
        let sealed = try AES.GCM.seal(
            data,
            using: key,
            authenticating: associatedData(recordType: recordType, recordName: recordName)
        )
        return CloudKitEncryptedPayload(
            schemaVersion: CloudKitEncryptedPayload.schemaVersion,
            keyID: SecureKeyStore.cloudKitKeyID,
            nonce: sealed.nonce.data,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag,
            updatedAt: updatedAt,
            tombstone: tombstone
        )
    }

    func open<Payload: Decodable>(
        _ encrypted: CloudKitEncryptedPayload,
        as type: Payload.Type,
        recordType: String,
        recordName: String
    ) async throws -> Payload {
        guard encrypted.schemaVersion == CloudKitEncryptedPayload.schemaVersion else {
            throw CloudKitRecordCipherError.unsupportedSchema(encrypted.schemaVersion)
        }
        let key = try await secureKeyStore.dataKey(purpose: .cloudKitE2E, keyID: encrypted.keyID)
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: encrypted.nonce),
            ciphertext: encrypted.ciphertext,
            tag: encrypted.tag
        )
        let data = try AES.GCM.open(
            box,
            using: key,
            authenticating: associatedData(recordType: recordType, recordName: recordName)
        )
        return try JSONDecoder().decode(type, from: data)
    }

    private func associatedData(recordType: String, recordName: String) -> Data {
        Data("\(recordType):\(recordName):v\(CloudKitEncryptedPayload.schemaVersion)".utf8)
    }
}

enum CloudKitRecordCipherError: Error, LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "Unsupported encrypted CloudKit record schema version \(version)."
        }
    }
}

private extension AES.GCM.Nonce {
    var data: Data {
        withUnsafeBytes { Data($0) }
    }
}
