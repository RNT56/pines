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
        updated.lastValidationError = result.status == .valid ? nil : result.message
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
}
