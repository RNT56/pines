import CryptoKit
import Foundation
import PinesCore
import Security

enum SecureKeyPurpose: String, Sendable {
    case encryptedDatabase = "encrypted-database"
    case encryptedBlob = "encrypted-blob"
    case cloudKitE2E = "cloudkit-e2e"

    var isInstallBound: Bool {
        self != .cloudKitE2E
    }
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
        try Self.delete(account: Self.account(purpose: purpose, keyID: keyID))
    }

    static func deleteInstallBoundLocalDataKeys() throws {
        try delete(account: account(purpose: .encryptedDatabase, keyID: databaseKeyID))
        try delete(account: account(purpose: .encryptedBlob, keyID: blobKeyID))
    }

    static func loadOrCreateDataKey(purpose: SecureKeyPurpose, keyID: String) throws -> Data {
        let account = account(purpose: purpose, keyID: keyID)
        if let existing = try readData(account: account, installBound: purpose.isInstallBound) {
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
        try readData(account: account, installBound: false)
    }

    private static func readData(account: String, installBound: Bool) throws -> Data? {
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
        guard installBound else {
            return data
        }
        let context = installBindingContext(account: account)
        if InstallBoundSecretEnvelope.isEnvelope(data) {
            do {
                return try InstallBoundSecretEnvelope.open(
                    data,
                    installKey: InstallIdentityKeyStore.loadOrCreateKey(),
                    context: context
                )
            } catch InstallBoundSecretEnvelopeError.authenticationFailed,
                    InstallBoundSecretEnvelopeError.malformedEnvelope {
                try delete(account: account)
                return nil
            }
        }

        try writeData(data, account: account, synchronizable: false)
        return data
    }

    private static func writeData(_ data: Data, account: String, synchronizable: Bool) throws {
        let storedData = try storedKeyData(data, account: account, synchronizable: synchronizable)
        var query = baseQuery(account: account)
        let accessibility = synchronizable
            ? kSecAttrAccessibleWhenUnlocked
            : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        if synchronizable {
            query[kSecAttrSynchronizable as String] = true
        }
        let update: [String: Any] = [
            kSecValueData as String: storedData,
            kSecAttrAccessible as String: accessibility,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw SecureKeyStoreError.keychainStatus(updateStatus)
        }
        query[kSecAttrAccessible as String] = accessibility
        query[kSecValueData as String] = storedData
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureKeyStoreError.keychainStatus(addStatus)
        }
    }

    private static func delete(account: String) throws {
        var query = baseQuery(account: account)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemDelete(query as CFDictionary)
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

    private static func storedKeyData(_ data: Data, account: String, synchronizable: Bool) throws -> Data {
        guard !synchronizable else { return data }
        return try InstallBoundSecretEnvelope.seal(
            data,
            installKey: InstallIdentityKeyStore.loadOrCreateKey(),
            context: installBindingContext(account: account)
        )
    }

    private static func installBindingContext(account: String) -> String {
        "\(keychainService)::\(account)"
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

enum InstallIdentityKeyStoreError: Error, LocalizedError {
    case applicationSupportUnavailable
    case randomGenerationFailed(OSStatus)
    case invalidStoredKeyLength(Int)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Application Support storage is unavailable."
        case let .randomGenerationFailed(status):
            "Install binding key generation failed with status \(status)."
        case let .invalidStoredKeyLength(length):
            "Install binding key has invalid length \(length)."
        }
    }
}

enum InstallIdentityKeyStore {
    static func hasStoredKey(fileManager: FileManager = .default) throws -> Bool {
        try fileManager.fileExists(atPath: keyURL(fileManager: fileManager).path)
    }

    static func loadOrCreateKey(fileManager: FileManager = .default) throws -> Data {
        let url = try keyURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard data.count == InstallBoundSecretEnvelope.installKeyByteCount else {
                throw InstallIdentityKeyStoreError.invalidStoredKeyLength(data.count)
            }
            return data
        }

        var bytes = [UInt8](repeating: 0, count: InstallBoundSecretEnvelope.installKeyByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw InstallIdentityKeyStoreError.randomGenerationFailed(status)
        }
        let data = Data(bytes)
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        return data
    }

    private static func keyURL(fileManager: FileManager) throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw InstallIdentityKeyStoreError.applicationSupportUnavailable
        }
        return base
            .appending(path: "Pines", directoryHint: .isDirectory)
            .appending(path: "Security", directoryHint: .isDirectory)
            .appending(path: "install-binding-key-v1")
    }
}
