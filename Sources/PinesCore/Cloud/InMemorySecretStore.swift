import Foundation

public actor InMemorySecretStore: SecretStore {
    private var storage = [String: String]()

    public init() {}

    public func read(service: String, account: String) async throws -> String? {
        storage[key(service: service, account: account)]
    }

    public func write(_ secret: String, service: String, account: String) async throws {
        storage[key(service: service, account: account)] = secret
    }

    public func delete(service: String, account: String) async throws {
        storage.removeValue(forKey: key(service: service, account: account))
    }

    private func key(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}
