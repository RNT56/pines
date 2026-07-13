import Foundation
import PinesCore

struct AnthropicProviderService: Sendable {
    static let apiVersion = "2023-06-01"
    static let filesAPIBeta = "files-api-2025-04-14"

    let configuration: CloudProviderConfiguration
    let secretStore: any SecretStore
    var urlSession: URLSession = .shared

    func rawJSON(
        method: AnthropicHTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: JSONValue? = nil,
        betaHeaders: [String] = []
    ) async throws -> AnthropicProviderResponse {
        try await send(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body.map { try JSONEncoder().encode($0) },
            contentType: body == nil ? nil : "application/json",
            accept: "application/json",
            betaHeaders: betaHeaders
        )
    }

    func rawMultipart(
        method: AnthropicHTTPMethod = .post,
        path: String,
        queryItems: [URLQueryItem] = [],
        multipart: OpenAIMultipartForm,
        betaHeaders: [String] = []
    ) async throws -> AnthropicProviderResponse {
        let boundary = "PinesAnthropic-\(UUID().uuidString)"
        return try await send(
            method: method,
            path: path,
            queryItems: queryItems,
            body: multipart.encoded(boundary: boundary),
            contentType: "multipart/form-data; boundary=\(boundary)",
            accept: "application/json",
            betaHeaders: betaHeaders
        )
    }

    func listFiles(_ request: AnthropicListRequest = AnthropicListRequest(limit: 100)) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .get, path: "files", queryItems: request.queryItems, betaHeaders: [Self.filesAPIBeta])
    }

    func uploadFile(_ request: AnthropicFileUploadRequest) async throws -> AnthropicProviderResponse {
        try await rawMultipart(path: "files", multipart: request.multipart, betaHeaders: [Self.filesAPIBeta])
    }

    func retrieveFile(_ fileID: String) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .get, path: "files/\(fileID)", betaHeaders: [Self.filesAPIBeta])
    }

    func retrieveFileContent(_ fileID: String) async throws -> AnthropicProviderResponse {
        try await send(
            method: .get,
            path: "files/\(fileID)/content",
            accept: "application/octet-stream",
            betaHeaders: [Self.filesAPIBeta],
            maxResponseBytes: BoundedHTTPResponse.fileLimit
        )
    }

    func deleteFile(_ fileID: String) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .delete, path: "files/\(fileID)", betaHeaders: [Self.filesAPIBeta])
    }

    func listBatches(_ request: AnthropicListRequest = AnthropicListRequest(limit: 100)) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .get, path: "messages/batches", queryItems: request.queryItems)
    }

    func createBatch(_ request: AnthropicMessageBatchCreateRequest) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .post, path: "messages/batches", body: request.body)
    }

    func createBatch(body: JSONValue) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .post, path: "messages/batches", body: body)
    }

    func retrieveBatch(_ batchID: String) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .get, path: "messages/batches/\(batchID)")
    }

    func cancelBatch(_ batchID: String) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .post, path: "messages/batches/\(batchID)/cancel")
    }

    func deleteBatch(_ batchID: String) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .delete, path: "messages/batches/\(batchID)")
    }

    func retrieveBatchResults(_ batchID: String) async throws -> AnthropicProviderResponse {
        try await send(
            method: .get,
            path: "messages/batches/\(batchID)/results",
            accept: "application/x-jsonlines",
            maxResponseBytes: BoundedHTTPResponse.fileLimit
        )
    }

    func countTokens(body: JSONValue) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .post, path: "messages/count_tokens", body: body)
    }

    func countTokens(modelID: ModelID, body: JSONValue) async throws -> AnthropicProviderResponse {
        var fields = body.objectValue ?? [:]
        fields["model"] = .string(modelID.rawValue)
        return try await countTokens(body: .object(fields))
    }

    func listModels(_ request: AnthropicListRequest = AnthropicListRequest(limit: 100)) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .get, path: "models", queryItems: request.queryItems)
    }

    func retrieveModel(_ modelID: ModelID) async throws -> AnthropicProviderResponse {
        try await rawJSON(method: .get, path: "models/\(modelID.rawValue)")
    }

    private func send(
        method: AnthropicHTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        accept: String? = nil,
        betaHeaders: [String] = [],
        maxResponseBytes: Int = BoundedHTTPResponse.jsonLimit
    ) async throws -> AnthropicProviderResponse {
        guard let apiKey = try await readAPIKey() else {
            throw CloudProviderError.missingAPIKey
        }

        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if let accept {
            request.addValue(accept, forHTTPHeaderField: "Accept")
        }
        if let contentType {
            request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let betas = betaHeaders
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingDuplicates()
        if !betas.isEmpty {
            request.addValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        try await applyExtraHeaders(to: &request)

        var lastRetryableResponse: AnthropicProviderResponse?
        for attempt in 0..<3 {
            let (data, http) = try await BoundedHTTPResponse.data(for: request, session: urlSession, maxBytes: maxResponseBytes)
            let providerResponse = AnthropicProviderResponse(data: data, httpResponse: http)
            if (200..<300).contains(http.statusCode) {
                return providerResponse
            }
            if Self.isRetryable(statusCode: http.statusCode), attempt < 2 {
                lastRetryableResponse = providerResponse
                try await Task.sleep(for: .seconds(Self.retryDelaySeconds(for: attempt)))
                continue
            }
            throw providerRejectedRequest(from: providerResponse)
        }
        throw providerRejectedRequest(from: lastRetryableResponse)
    }

    private func readAPIKey() async throws -> String? {
        let apiKey = try await secretStore.read(
            service: configuration.keychainService,
            account: configuration.keychainAccount
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return apiKey?.isEmpty == false ? apiKey : nil
    }

    private func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var url = apiBaseURL
        for segment in path.split(separator: "/").map(String.init) {
            url.append(path: segment)
        }
        guard !queryItems.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let resolved = components?.url else {
            throw CloudProviderError.invalidResponse
        }
        return resolved
    }

    private var apiBaseURL: URL {
        Self.anthropicV1BaseURL(from: configuration.baseURL)
    }

    private static func anthropicV1BaseURL(from url: URL) -> URL {
        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.split(separator: "/").last?.lowercased() == "v1" {
            return url
        }
        return url.appending(path: "v1")
    }

    private func applyExtraHeaders(to request: inout URLRequest) async throws {
        if let url = request.url {
            try EndpointSecurityPolicy().validate(
                url,
                useCase: .cloudProvider,
                allowsExplicitLocalHTTP: configuration.allowInsecureLocalHTTP
            )
        }

        for header in configuration.headers {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard header.kind == .secretReference || !CloudProviderHeader.isSecretLikeName(name) else {
                throw InferenceError.invalidRequest("Cloud provider header \(name) must be stored as a Keychain secret reference.")
            }
            let value: String?
            switch header.kind {
            case .publicValue:
                value = header.value
            case .secretReference:
                guard let service = header.keychainService,
                      let account = header.keychainAccount
                else {
                    throw InferenceError.invalidRequest("Cloud provider header \(name) is missing its Keychain reference.")
                }
                value = try await secretStore.read(service: service, account: account)
            }
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 429 || (500..<600).contains(statusCode)
    }

    private static func retryDelaySeconds(for attempt: Int) -> Int64 {
        min(Int64(1 << max(0, attempt)), 8)
    }

    private func providerRejectedRequest(from response: AnthropicProviderResponse?) -> CloudProviderError {
        let statusCode = response?.statusCode ?? -1
        return CloudProviderError.providerRejectedRequest(
            statusCode: statusCode,
            message: BYOKCloudInferenceProvider.messageWithRequestID(
                response.flatMap { BYOKCloudInferenceProvider.providerErrorMessage(from: $0.data) }
                    ?? HTTPURLResponse.localizedString(forStatusCode: statusCode),
                requestID: response?.requestID,
                providerKind: .anthropic
            )
        )
    }
}

enum AnthropicHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

struct AnthropicProviderResponse: Sendable {
    var data: Data
    var statusCode: Int
    var headers: [String: String]
    var requestID: String?

    init(data: Data, httpResponse: HTTPURLResponse) {
        self.data = data
        statusCode = httpResponse.statusCode
        headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        requestID = Self.headerValue("request-id", in: headers)
            ?? Self.headerValue("x-request-id", in: headers)
    }

    var json: JSONValue? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    func headerValue(_ name: String) -> String? {
        Self.headerValue(name, in: headers)
    }

    private static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        let lowercased = name.lowercased()
        return headers.first { $0.key.lowercased() == lowercased }?.value
    }
}

struct AnthropicListRequest: Sendable {
    var beforeID: String?
    var afterID: String?
    var limit: Int?

    init(beforeID: String? = nil, afterID: String? = nil, limit: Int? = nil) {
        self.beforeID = beforeID
        self.afterID = afterID
        self.limit = limit
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem]()
        if let beforeID, !beforeID.isEmpty {
            items.append(URLQueryItem(name: "before_id", value: beforeID))
        }
        if let afterID, !afterID.isEmpty {
            items.append(URLQueryItem(name: "after_id", value: afterID))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return items
    }
}

struct AnthropicFileUploadRequest: Sendable {
    var fileName: String
    var contentType: String
    var data: Data
    var fields: [String: String]

    init(fileName: String, contentType: String, data: Data, fields: [String: String] = [:]) {
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
        self.fields = fields
    }

    var multipart: OpenAIMultipartForm {
        OpenAIMultipartForm(
            fields: fields,
            files: [
                OpenAIMultipartFile(name: "file", fileName: fileName, contentType: contentType, data: data),
            ]
        )
    }
}

struct AnthropicMessageBatchCreateRequest: Sendable {
    var requests: [AnthropicMessageBatchRequest]
    var metadata: [String: String]
    var rawFields: [String: JSONValue]

    init(
        requests: [AnthropicMessageBatchRequest],
        metadata: [String: String] = [:],
        rawFields: [String: JSONValue] = [:]
    ) {
        self.requests = requests
        self.metadata = metadata
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        fields["requests"] = .array(requests.map(\.body))
        if !metadata.isEmpty {
            fields["metadata"] = .object(metadata.mapValues(JSONValue.string))
        }
        return .object(fields)
    }
}

struct AnthropicMessageBatchRequest: Sendable {
    var customID: String
    var params: JSONValue

    init(customID: String, params: JSONValue) {
        self.customID = customID
        self.params = params
    }

    var body: JSONValue {
        .object([
            "custom_id": .string(customID),
            "params": params,
        ])
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value).inserted
        }
    }
}
