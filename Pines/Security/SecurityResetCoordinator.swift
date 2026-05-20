import Foundation
import PinesCore
import Security

struct SecurityResetCoordinator: Sendable {
    let settingsRepository: (any SettingsRepository)?
    let cloudProviderRepository: (any CloudProviderRepository)?
    let mcpServerRepository: (any MCPServerRepository)?
    let secretStore: any SecretStore
    let auditRepository: (any AuditEventRepository)?
    let redactor: Redactor

    func runIfNeeded() async {
        do {
            guard var settings = try await settingsRepository?.loadSettings(),
                  settings.securityConfiguration.securityResetCompletedAt == nil
            else {
                return
            }

            try await resetCloudProviders()
            try await resetMCPServers()
            try await secretStore.delete(service: HuggingFaceCredentialService.keychainService, account: HuggingFaceCredentialService.tokenAccount)
            try await secretStore.delete(service: BraveSearchTool.keychainService, account: BraveSearchTool.keychainAccount)

            settings.securityConfiguration.securityResetCompletedAt = Date()
            try await settingsRepository?.saveSettings(settings)
            try await auditRepository?.append(
                AuditEvent(
                    category: .security,
                    summary: "Completed high-assurance security reset; credentials must be re-entered."
                )
            )
        } catch {
            try? await auditRepository?.append(
                AuditEvent(
                    category: .security,
                    summary: "High-assurance security reset failed.",
                    redactedPayload: redactor.redact(error.localizedDescription)
                )
            )
        }
    }

    private func resetCloudProviders() async throws {
        guard let cloudProviderRepository else { return }
        let policy = EndpointSecurityPolicy()
        for var provider in try await cloudProviderRepository.listProviders() {
            try await secretStore.delete(service: provider.keychainService, account: provider.keychainAccount)
            for header in provider.headers where header.kind == .secretReference {
                guard let service = header.keychainService,
                      let account = header.keychainAccount
                else { continue }
                try await secretStore.delete(service: service, account: account)
            }
            provider.headers = []
            provider.validationStatus = .unvalidated
            provider.lastValidatedAt = nil
            provider.lastValidationError = nil
            do {
                try policy.validate(
                    provider.baseURL,
                    useCase: .cloudProvider,
                    allowsExplicitLocalHTTP: provider.allowInsecureLocalHTTP
                )
            } catch {
                provider.enabledForAgents = false
                provider.validationStatus = .invalid
                provider.lastValidationError = redactor.redact(error.localizedDescription)
            }
            try await cloudProviderRepository.upsertProvider(provider)
        }
    }

    private func resetMCPServers() async throws {
        guard let mcpServerRepository else { return }
        let policy = EndpointSecurityPolicy()
        for var server in try await mcpServerRepository.listMCPServers() {
            try await secretStore.delete(service: server.keychainService, account: server.keychainAccount)
            try await secretStore.delete(service: server.keychainService, account: "\(server.keychainAccount).access_token")
            try await secretStore.delete(service: server.keychainService, account: "\(server.keychainAccount).refresh_token")
            server.status = .disconnected
            server.lastError = nil
            do {
                try policy.validate(server.endpointURL, useCase: .mcpEndpoint, allowsExplicitLocalHTTP: server.allowInsecureLocalHTTP)
                if let authorizationURL = server.oauthAuthorizationURL {
                    try policy.validate(authorizationURL, useCase: .oauthAuthorization)
                }
                if let tokenURL = server.oauthTokenURL {
                    try policy.validate(tokenURL, useCase: .oauthToken)
                }
            } catch {
                server.enabled = false
                server.status = .failed
                server.lastError = redactor.redact(error.localizedDescription)
            }
            try await mcpServerRepository.upsertMCPServer(server)
        }
    }
}

struct AppDataResetService: Sendable {
    let services: PinesAppServices

    func eraseAllData() async throws {
        await services.mcpServerService?.stopAll()
        try await services.cloudKitSyncService?.deleteAllRemoteData()
        try await deleteKnownKeychainSecrets()
        try await services.modelLifecycleService?.deleteAllLocalModelData()
        guard let resetRepository = services.liveStore else {
            throw AppDataResetError.persistenceUnavailable
        }
        try await resetRepository.deleteAllUserRecords()
        try removeLocalSupportDirectories()
        try await services.secureKeyStore.deleteDataKey(purpose: .encryptedBlob, keyID: SecureKeyStore.blobKeyID)
        try await services.secureKeyStore.deleteDataKey(purpose: .cloudKitE2E, keyID: SecureKeyStore.cloudKitKeyID)
    }

    private func deleteKnownKeychainSecrets() async throws {
        let providers = try await services.cloudProviderRepository?.listProviders() ?? []
        let providerByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        for provider in providers {
            try await services.secretStore.delete(service: provider.keychainService, account: provider.keychainAccount)
            for header in provider.headers where header.kind == .secretReference {
                guard let service = header.keychainService,
                      let account = header.keychainAccount
                else { continue }
                try await services.secretStore.delete(service: service, account: account)
            }
        }

        let liveSessions = try await services.providerLiveSessionRepository?.listProviderLiveSessions(providerID: nil) ?? []
        for session in liveSessions {
            guard let account = session.credentialKeychainAccount,
                  let provider = providerByID[session.providerID]
            else { continue }
            try await services.secretStore.delete(service: provider.keychainService, account: account)
        }

        let servers = try await services.mcpServerRepository?.listMCPServers() ?? []
        for server in servers {
            try await services.secretStore.delete(service: server.keychainService, account: server.keychainAccount)
            try await services.secretStore.delete(service: server.keychainService, account: "\(server.keychainAccount).access_token")
            try await services.secretStore.delete(service: server.keychainService, account: "\(server.keychainAccount).refresh_token")
        }

        try await services.secretStore.delete(service: HuggingFaceCredentialService.keychainService, account: HuggingFaceCredentialService.tokenAccount)
        try await services.secretStore.delete(service: BraveSearchTool.keychainService, account: BraveSearchTool.keychainAccount)
        try await services.secretStore.delete(service: PinesManagedCloudService.installationSecretService, account: PinesManagedCloudService.installationSecretAccount)
        try KnownKeychainPurger.deleteKnownUserSecretServices()
    }

    private func removeLocalSupportDirectories() throws {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppDataResetError.applicationSupportUnavailable
        }
        let pinesDirectory = applicationSupport.appending(path: "Pines", directoryHint: .isDirectory)
        for child in ["Models", "ChatAttachments", "VaultFiles", "EncryptedBlobs"] {
            let url = pinesDirectory.appending(path: child, directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        let providerArtifacts = applicationSupport.appending(path: "OpenAIProviderArtifacts", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: providerArtifacts.path) {
            try fileManager.removeItem(at: providerArtifacts)
        }
        let artifactImports = fileManager.temporaryDirectory.appending(path: "PinesArtifactImports", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: artifactImports.path) {
            try fileManager.removeItem(at: artifactImports)
        }
    }
}

enum AppInstallStateCoordinator {
    private static let markerService = "com.schtack.pines.install-state"
    private static let markerAccount = "install-marker-v1"

    static func prepareForLaunch() throws {
        let hadInstallMarker = try hasInstallMarker()
        let hasInstallKey = try InstallIdentityKeyStore.hasStoredKey()
        if hadInstallMarker && !hasInstallKey {
            try KnownKeychainPurger.deleteDeletedInstallKeychainRemnants()
            try DeletedInstallLocalDataScrubber.deleteLocalRemnantsBeforeStoreOpen()
        }
        _ = try InstallIdentityKeyStore.loadOrCreateKey()
        try writeInstallMarker()
    }

    private static func hasInstallMarker() throws -> Bool {
        var query = markerQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else {
            throw AppInstallStateError.keychainStatus(status)
        }
        return true
    }

    private static func writeInstallMarker() throws {
        var query = markerQuery()
        let value = Data("installed-v1".utf8)
        let update: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw AppInstallStateError.keychainStatus(updateStatus)
        }

        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppInstallStateError.keychainStatus(addStatus)
        }
    }

    private static func markerQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: markerService,
            kSecAttrAccount as String: markerAccount,
        ]
    }
}

enum KnownKeychainPurger {
    private static let knownUserSecretServices = [
        "com.schtack.pines.cloud",
        "com.schtack.pines.mcp",
        HuggingFaceCredentialService.keychainService,
        BraveSearchTool.keychainService,
        PinesManagedCloudService.installationSecretService,
    ]

    static func deleteKnownUserSecretServices() throws {
        for service in knownUserSecretServices {
            try deleteGenericPasswordItems(service: service)
        }
    }

    static func deleteDeletedInstallKeychainRemnants() throws {
        try SecureKeyStore.deleteInstallBoundLocalDataKeys()
        try deleteKnownUserSecretServices()
    }

    private static func deleteGenericPasswordItems(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppInstallStateError.keychainStatus(status)
        }
    }
}

enum DeletedInstallLocalDataScrubber {
    static func deleteLocalRemnantsBeforeStoreOpen(fileManager: FileManager = .default) throws {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppDataResetError.applicationSupportUnavailable
        }
        let urls = [
            applicationSupport.appending(path: "Pines", directoryHint: .isDirectory),
            applicationSupport.appending(path: "OpenAIProviderArtifacts", directoryHint: .isDirectory),
            fileManager.temporaryDirectory.appending(path: "PinesArtifactImports", directoryHint: .isDirectory),
        ]
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

enum AppInstallStateError: Error, LocalizedError {
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychainStatus(status):
            "Install state Keychain operation failed with status \(status)."
        }
    }
}

enum AppDataResetError: Error, LocalizedError {
    case persistenceUnavailable
    case applicationSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .persistenceUnavailable:
            "Local persistence is unavailable."
        case .applicationSupportUnavailable:
            "Application Support storage is unavailable."
        }
    }
}
