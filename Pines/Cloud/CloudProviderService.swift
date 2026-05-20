import Foundation
import PinesCore

struct CloudProviderService {
    let repository: any CloudProviderRepository
    let secretStore: any SecretStore
    let auditRepository: (any AuditEventRepository)?

    func saveProvider(_ provider: CloudProviderConfiguration, apiKey: String?) async throws {
        if let apiKey, !apiKey.isEmpty {
            try await secretStore.write(apiKey, service: provider.keychainService, account: provider.keychainAccount)
        }
        try await repository.upsertProvider(provider)
        try await auditRepository?.append(
            AuditEvent(category: .cloudProvider, summary: "Saved provider \(provider.displayName)", providerID: provider.id)
        )
    }

    func deleteProvider(_ provider: CloudProviderConfiguration) async throws {
        try await secretStore.delete(service: provider.keychainService, account: provider.keychainAccount)
        for header in provider.headers where header.kind == .secretReference {
            guard let service = header.keychainService,
                  let account = header.keychainAccount
            else { continue }
            try await secretStore.delete(service: service, account: account)
        }
        try await repository.deleteProvider(id: provider.id)
        try await auditRepository?.append(
            AuditEvent(category: .cloudProvider, summary: "Deleted provider \(provider.displayName)", providerID: provider.id)
        )
    }

    func validate(_ provider: CloudProviderConfiguration) async throws -> ProviderValidationResult {
        let inferenceProvider = BYOKCloudInferenceProvider(configuration: provider, secretStore: secretStore)
        let result = try await inferenceProvider.validate(modelID: provider.defaultModelID)
        var updated = provider
        updated.validationStatus = result.status
        updated.lastValidatedAt = result.validatedAt
        updated.lastValidationError = result.status == .valid ? nil : Redactor().redact(result.message)
        try await repository.upsertProvider(updated)
        try await auditRepository?.append(
            AuditEvent(
                category: .cloudProvider,
                summary: "Validated provider \(provider.displayName): \(result.status.rawValue)",
                providerID: provider.id
            )
        )
        return result
    }

    func openAIProviderService(for provider: CloudProviderConfiguration) -> OpenAIProviderService {
        OpenAIProviderService(configuration: provider, secretStore: secretStore)
    }

    func openAILifecycleCoordinator(
        for provider: CloudProviderConfiguration,
        repositories: OpenAIProviderLifecycleRepositories
    ) -> OpenAIProviderLifecycleCoordinator {
        OpenAIProviderLifecycleCoordinator(
            service: openAIProviderService(for: provider),
            repositories: repositories
        )
    }

    func geminiProviderService(for provider: CloudProviderConfiguration) -> GeminiProviderService {
        GeminiProviderService(configuration: provider, secretStore: secretStore)
    }

    func anthropicProviderService(for provider: CloudProviderConfiguration) -> AnthropicProviderService {
        AnthropicProviderService(configuration: provider, secretStore: secretStore)
    }

    func geminiLiveSessionService(for provider: CloudProviderConfiguration) -> GeminiLiveSessionService {
        GeminiLiveSessionService(configuration: provider, secretStore: secretStore)
    }

    func geminiLifecycleCoordinator(
        for provider: CloudProviderConfiguration,
        repositories: GeminiProviderLifecycleRepositories
    ) -> GeminiProviderLifecycleCoordinator {
        GeminiProviderLifecycleCoordinator(
            service: geminiProviderService(for: provider),
            repositories: repositories
        )
    }

    func anthropicLifecycleCoordinator(
        for provider: CloudProviderConfiguration,
        repositories: AnthropicProviderLifecycleRepositories
    ) -> AnthropicProviderLifecycleCoordinator {
        AnthropicProviderLifecycleCoordinator(
            service: anthropicProviderService(for: provider),
            repositories: repositories
        )
    }
}
