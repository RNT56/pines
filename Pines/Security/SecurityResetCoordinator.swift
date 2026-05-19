import Foundation
import PinesCore

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
