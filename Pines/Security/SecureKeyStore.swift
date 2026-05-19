import CryptoKit
import Foundation
import PinesCore
import Security

enum SecureKeyPurpose: String, Sendable {
    case encryptedDatabase = "encrypted-database"
    case encryptedBlob = "encrypted-blob"
    case cloudKitE2E = "cloudkit-e2e"
}

actor SecureKeyStore {
    static let keychainService = "com.schtack.pines.keys"
    static let cloudKitKeyID = "cloudkit-e2e-v1"
    static let databaseKeyID = "sqlite-sqlcipher-v1"
    static let blobKeyID = "blob-aes-gcm-v1"

    func dataKey(purpose: SecureKeyPurpose, keyID: String) async throws -> SymmetricKey {
        try SymmetricKey(data: Self.loadOrCreateDataKey(purpose: purpose, keyID: keyID))
    }

    func deleteDataKey(purpose: SecureKeyPurpose, keyID: String) async throws {
        try Self.delete(account: account(purpose: purpose, keyID: keyID))
    }

    static func loadOrCreateDataKey(purpose: SecureKeyPurpose, keyID: String) throws -> Data {
        let account = account(purpose: purpose, keyID: keyID)
        if let existing = try readData(account: account) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SecureKeyStoreError.randomGenerationFailed(status)
        }
        let data = Data(bytes)
        try writeData(
            data,
            account: account,
            synchronizable: purpose == .cloudKitE2E
        )
        return data
    }

    private static func account(purpose: SecureKeyPurpose, keyID: String) -> String {
        "\(purpose.rawValue)::\(keyID)"
    }

    private static func readData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureKeyStoreError.keychainStatus(status)
        }
        guard let data = item as? Data else {
            throw SecureKeyStoreError.invalidKeyData
        }
        return data
    }

    private static func writeData(_ data: Data, account: String, synchronizable: Bool) throws {
        var query = baseQuery(account: account)
        query[kSecAttrAccessible as String] = synchronizable
            ? kSecAttrAccessibleWhenUnlocked
            : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        if synchronizable {
            query[kSecAttrSynchronizable as String] = true
        }
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw SecureKeyStoreError.keychainStatus(updateStatus)
        }
        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureKeyStoreError.keychainStatus(addStatus)
        }
    }

    private static func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureKeyStoreError.keychainStatus(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
    }
}

enum SecureKeyStoreError: Error, LocalizedError {
    case randomGenerationFailed(OSStatus)
    case keychainStatus(OSStatus)
    case invalidKeyData

    var errorDescription: String? {
        switch self {
        case let .randomGenerationFailed(status):
            "Secure key generation failed with status \(status)."
        case let .keychainStatus(status):
            "Secure key Keychain operation failed with status \(status)."
        case .invalidKeyData:
            "Secure key item did not contain data."
        }
    }
}
