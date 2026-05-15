import Foundation
import PinesCore

struct HuggingFaceCredentialService {
    static let keychainService = "com.schtack.pines.huggingface"
    static let tokenAccount = "hub-token"

    let secretStore: any SecretStore
    let auditRepository: (any AuditEventRepository)?

    func readToken() async throws -> String? {
        try await secretStore.read(service: Self.keychainService, account: Self.tokenAccount)
    }

    func saveToken(_ token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try await deleteToken()
            return
        }

        try await secretStore.write(trimmed, service: Self.keychainService, account: Self.tokenAccount)
        try await auditRepository?.append(
            AuditEvent(category: .security, summary: "Saved Hugging Face access token")
        )
    }

    func deleteToken() async throws {
        try await secretStore.delete(service: Self.keychainService, account: Self.tokenAccount)
        try await auditRepository?.append(
            AuditEvent(category: .security, summary: "Deleted Hugging Face access token")
        )
    }

    func validateToken(_ token: String? = nil) async throws -> String {
        let rawToken: String?
        if let token {
            rawToken = token
        } else {
            rawToken = try await readToken()
        }
        let accessToken = rawToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let accessToken, !accessToken.isEmpty else {
            return "No Hugging Face token is configured."
        }

        var request = URLRequest(url: URL(string: "https://huggingface.co/api/whoami-v2")!)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await URLSession.shared.data(for: request)

        let message: String
        if (200..<300).contains(http.statusCode) {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let name = payload?["name"] as? String
            message = name.map { "Validated Hugging Face token for \($0)." } ?? "Validated Hugging Face token."
        } else if http.statusCode == 401 || http.statusCode == 403 {
            message = "Hugging Face rejected the token."
        } else {
            message = "Hugging Face validation failed with HTTP \(http.statusCode)."
        }

        try await auditRepository?.append(
            AuditEvent(category: .security, summary: message)
        )
        return message
    }
}
