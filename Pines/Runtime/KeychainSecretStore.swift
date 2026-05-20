import Foundation
import PinesCore
import Security

actor KeychainSecretStore: SecretStore {
    func read(service: String, account: String) async throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainSecretStoreError.invalidData
        }
        if InstallBoundSecretEnvelope.isEnvelope(data) {
            do {
                let plaintext = try InstallBoundSecretEnvelope.open(
                    data,
                    installKey: InstallIdentityKeyStore.loadOrCreateKey(),
                    context: Self.installBindingContext(service: service, account: account)
                )
                guard let secret = String(data: plaintext, encoding: .utf8) else {
                    throw KeychainSecretStoreError.invalidData
                }
                return secret
            } catch InstallBoundSecretEnvelopeError.authenticationFailed,
                    InstallBoundSecretEnvelopeError.malformedEnvelope {
                try await delete(service: service, account: account)
                return nil
            }
        }
        guard let secret = String(data: data, encoding: .utf8) else {
            throw KeychainSecretStoreError.invalidData
        }
        try await write(secret, service: service, account: account)
        return secret
    }

    func write(_ secret: String, service: String, account: String) async throws {
        let data = try InstallBoundSecretEnvelope.seal(
            Data(secret.utf8),
            installKey: InstallIdentityKeyStore.loadOrCreateKey(),
            context: Self.installBindingContext(service: service, account: account)
        )
        var query = baseQuery(service: service, account: account)

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status != errSecItemNotFound {
            throw KeychainSecretStoreError.unhandledStatus(status)
        }

        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretStoreError.unhandledStatus(addStatus)
        }
    }

    func delete(service: String, account: String) async throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func installBindingContext(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}

enum KeychainSecretStoreError: Error, LocalizedError {
    case invalidData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "Keychain item did not contain UTF-8 data."
        case let .unhandledStatus(status):
            "Keychain operation failed with status \(status)."
        }
    }
}
