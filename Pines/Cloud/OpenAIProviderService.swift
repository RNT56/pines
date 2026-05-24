import Foundation
import PinesCore

struct OpenAIProviderService {
    let configuration: CloudProviderConfiguration
    let secretStore: any SecretStore
    var urlSession: URLSession = .shared

    func rawJSON(
        method: OpenAIHTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: JSONValue? = nil
    ) async throws -> OpenAIProviderResponse {
        try await send(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body.map { try JSONEncoder().encode($0) },
            contentType: body == nil ? nil : "application/json"
        )
    }

    func rawMultipart(
        method: OpenAIHTTPMethod = .post,
        path: String,
        queryItems: [URLQueryItem] = [],
        multipart: OpenAIMultipartForm
    ) async throws -> OpenAIProviderResponse {
        let boundary = "PinesOpenAI-\(UUID().uuidString)"
        return try await send(
            method: method,
            path: path,
            queryItems: queryItems,
            body: multipart.encoded(boundary: boundary),
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    func listFiles(_ request: OpenAIFileListRequest = OpenAIFileListRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "files", queryItems: request.queryItems)
    }

    func uploadFile(_ request: OpenAIFileUploadRequest) async throws -> OpenAIProviderResponse {
        try await rawMultipart(path: "files", multipart: request.multipart)
    }

    func retrieveFile(_ fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "files/\(fileID)")
    }

    func retrieveFileContent(_ fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "files/\(fileID)/content")
    }

    func deleteFile(_ fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .delete, path: "files/\(fileID)")
    }

    func listVectorStores(_ request: OpenAIListRequest = OpenAIListRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "vector_stores", queryItems: request.queryItems)
    }

    func createVectorStore(_ request: OpenAIVectorStoreCreateRequest = OpenAIVectorStoreCreateRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "vector_stores", body: request.body)
    }

    func retrieveVectorStore(_ vectorStoreID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "vector_stores/\(vectorStoreID)")
    }

    func updateVectorStore(_ vectorStoreID: String, body: JSONValue) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "vector_stores/\(vectorStoreID)", body: body)
    }

    func deleteVectorStore(_ vectorStoreID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .delete, path: "vector_stores/\(vectorStoreID)")
    }

    func searchVectorStore(_ vectorStoreID: String, body: JSONValue) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "vector_stores/\(vectorStoreID)/search", body: body)
    }

    func listVectorStoreFiles(_ vectorStoreID: String, request: OpenAIListRequest = OpenAIListRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "vector_stores/\(vectorStoreID)/files", queryItems: request.queryItems)
    }

    func attachVectorStoreFile(_ vectorStoreID: String, fileID: String, attributes: JSONValue? = nil) async throws -> OpenAIProviderResponse {
        var fields: [String: JSONValue] = ["file_id": .string(fileID)]
        if let attributes {
            fields["attributes"] = attributes
        }
        return try await rawJSON(method: .post, path: "vector_stores/\(vectorStoreID)/files", body: .object(fields))
    }

    func retrieveVectorStoreFile(_ vectorStoreID: String, fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "vector_stores/\(vectorStoreID)/files/\(fileID)")
    }

    func retrieveVectorStoreFileContent(_ vectorStoreID: String, fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "vector_stores/\(vectorStoreID)/files/\(fileID)/content")
    }

    func deleteVectorStoreFile(_ vectorStoreID: String, fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .delete, path: "vector_stores/\(vectorStoreID)/files/\(fileID)")
    }

    func createVectorStoreFileBatch(_ vectorStoreID: String, fileIDs: [String], attributes: JSONValue? = nil) async throws -> OpenAIProviderResponse {
        var fields: [String: JSONValue] = ["file_ids": .array(fileIDs.map(JSONValue.string))]
        if let attributes {
            fields["attributes"] = attributes
        }
        return try await rawJSON(method: .post, path: "vector_stores/\(vectorStoreID)/file_batches", body: .object(fields))
    }

    func retrieveVectorStoreFileBatch(_ vectorStoreID: String, batchID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "vector_stores/\(vectorStoreID)/file_batches/\(batchID)")
    }

    func cancelVectorStoreFileBatch(_ vectorStoreID: String, batchID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "vector_stores/\(vectorStoreID)/file_batches/\(batchID)/cancel")
    }

    func listVectorStoreFileBatchFiles(_ vectorStoreID: String, batchID: String, request: OpenAIListRequest = OpenAIListRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "vector_stores/\(vectorStoreID)/file_batches/\(batchID)/files", queryItems: request.queryItems)
    }

    func listContainers(_ request: OpenAIContainerListRequest = OpenAIContainerListRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "containers", queryItems: request.queryItems)
    }

    func createContainer(_ request: OpenAIContainerCreateRequest) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "containers", body: request.body)
    }

    func retrieveContainer(_ containerID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "containers/\(containerID)")
    }

    func deleteContainer(_ containerID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .delete, path: "containers/\(containerID)")
    }

    func listContainerFiles(_ containerID: String, request: OpenAIListRequest = OpenAIListRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "containers/\(containerID)/files", queryItems: request.queryItems)
    }

    func uploadContainerFile(_ containerID: String, request: OpenAIFileUploadRequest) async throws -> OpenAIProviderResponse {
        try await rawMultipart(path: "containers/\(containerID)/files", multipart: request.multipart)
    }

    func retrieveContainerFile(_ containerID: String, fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "containers/\(containerID)/files/\(fileID)")
    }

    func retrieveContainerFileContent(_ containerID: String, fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "containers/\(containerID)/files/\(fileID)/content")
    }

    func deleteContainerFile(_ containerID: String, fileID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .delete, path: "containers/\(containerID)/files/\(fileID)")
    }

    func createImage(_ request: OpenAIImageCreateRequest) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "images/generations", body: request.body)
    }

    func createImageEdit(body: JSONValue) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "images/edits", body: body)
    }

    func createImageEdit(multipart: OpenAIMultipartForm) async throws -> OpenAIProviderResponse {
        try await rawMultipart(path: "images/edits", multipart: multipart)
    }

    func createImageVariation(multipart: OpenAIMultipartForm) async throws -> OpenAIProviderResponse {
        try await rawMultipart(path: "images/variations", multipart: multipart)
    }

    func listVideos(_ request: OpenAIListRequest = OpenAIListRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "videos", queryItems: request.queryItems)
    }

    func createVideo(_ request: OpenAIVideoCreateRequest) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "videos", body: request.body)
    }

    func createVideo(multipart: OpenAIMultipartForm) async throws -> OpenAIProviderResponse {
        try await rawMultipart(path: "videos", multipart: multipart)
    }

    func retrieveVideo(_ videoID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "videos/\(videoID)")
    }

    func retrieveVideoContent(_ videoID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "videos/\(videoID)/content")
    }

    func listBatches(_ request: OpenAIBatchListRequest = OpenAIBatchListRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "batches", queryItems: request.queryItems)
    }

    func createBatch(_ request: OpenAIBatchCreateRequest) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "batches", body: request.body)
    }

    func retrieveBatch(_ batchID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "batches/\(batchID)")
    }

    func cancelBatch(_ batchID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "batches/\(batchID)/cancel")
    }

    func createSpeech(body: JSONValue) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "audio/speech", body: body)
    }

    func createTranscription(multipart: OpenAIMultipartForm) async throws -> OpenAIProviderResponse {
        try await rawMultipart(path: "audio/transcriptions", multipart: multipart)
    }

    func createTranslation(multipart: OpenAIMultipartForm) async throws -> OpenAIProviderResponse {
        try await rawMultipart(path: "audio/translations", multipart: multipart)
    }

    func createRealtimeClientSecret(_ request: OpenAIRealtimeClientSecretRequest = OpenAIRealtimeClientSecretRequest()) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "realtime/client_secrets", body: request.body)
    }

    func createRealtimeTranslationClientSecret(body: JSONValue = .object([:])) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "realtime/translations/client_secrets", body: body)
    }

    func createRealtimeSession(body: JSONValue) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "realtime/sessions", body: body)
    }

    func createRealtimeTranscriptionSession(body: JSONValue) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "realtime/transcription_sessions", body: body)
    }

    func retrieveResponse(_ responseID: String, queryItems: [URLQueryItem] = []) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .get, path: "responses/\(responseID)", queryItems: queryItems)
    }

    func cancelResponse(_ responseID: String) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "responses/\(responseID)/cancel")
    }

    func createDeepResearchRun(_ request: OpenAIDeepResearchRequest) async throws -> OpenAIProviderResponse {
        try await rawJSON(method: .post, path: "responses", body: request.openAIResponsesBody)
    }

    func createDeepResearchRunRecord(_ request: OpenAIDeepResearchRequest) async throws -> (response: OpenAIProviderResponse, run: ProviderResearchRunRecord) {
        let response = try await createDeepResearchRun(request)
        return (response, OpenAIProviderRecordMapper.providerResearchRun(from: request, response: response.json))
    }

    func retrieveDeepResearchRun(responseID: OpenAIResponseID) async throws -> OpenAIProviderResponse {
        try await retrieveResponse(responseID.rawValue)
    }

    func retrieveDeepResearchRunRecord(_ run: ProviderResearchRunRecord) async throws -> (response: OpenAIProviderResponse, run: ProviderResearchRunRecord) {
        guard let responseID = run.responseID, !responseID.isEmpty else {
            throw InferenceError.invalidRequest("OpenAI Deep Research run \(run.id) does not have a provider response ID.")
        }
        let response = try await retrieveResponse(responseID)
        return (response, OpenAIProviderRecordMapper.providerResearchRun(updating: run, response: response.json))
    }

    func cancelDeepResearchRun(responseID: OpenAIResponseID) async throws -> OpenAIProviderResponse {
        try await cancelResponse(responseID.rawValue)
    }

    func cancelDeepResearchRunRecord(_ run: ProviderResearchRunRecord) async throws -> (response: OpenAIProviderResponse, run: ProviderResearchRunRecord) {
        guard let responseID = run.responseID, !responseID.isEmpty else {
            throw InferenceError.invalidRequest("OpenAI Deep Research run \(run.id) does not have a provider response ID.")
        }
        let response = try await cancelResponse(responseID)
        return (response, OpenAIProviderRecordMapper.providerResearchRun(updating: run, response: response.json))
    }

    private func send(
        method: OpenAIHTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> OpenAIProviderResponse {
        guard let apiKey = try await readAPIKey() else {
            throw CloudProviderError.missingAPIKey
        }

        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        addOpenAIClientRequestID(to: &request)
        try await applyExtraHeaders(to: &request)

        let (data, http) = try await urlSession.data(for: request)
        let providerResponse = OpenAIProviderResponse(data: data, httpResponse: http)
        guard (200..<300).contains(http.statusCode) else {
            throw CloudProviderError.providerRejectedRequest(
                statusCode: http.statusCode,
                message: messageWithRequestID(
                    providerErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                    requestID: providerResponse.requestID
                )
            )
        }
        return providerResponse
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
        guard usesOfficialOpenAIAPI else {
            return configuration.baseURL
        }
        return Self.openAIV1BaseURL(from: configuration.baseURL)
    }

    private var usesOfficialOpenAIAPI: Bool {
        if configuration.kind == .openAI {
            return true
        }
        guard let host = configuration.baseURL.host(percentEncoded: false)?.lowercased() else {
            return false
        }
        return host == "api.openai.com"
    }

    private static func openAIV1BaseURL(from url: URL) -> URL {
        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.split(separator: "/").last?.lowercased() == "v1" {
            return url
        }
        return url.appending(path: "v1")
    }

    private func addOpenAIClientRequestID(to request: inout URLRequest) {
        guard usesOfficialOpenAIAPI else { return }
        request.addValue(UUID().uuidString, forHTTPHeaderField: "X-Client-Request-Id")
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

    private func providerErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = json["message"] as? String {
                return message
            }
            if let detail = json["detail"] as? String {
                return detail
            }
        }
        let fallback = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback?.isEmpty == false ? fallback : nil
    }

    private func messageWithRequestID(_ message: String, requestID: String?) -> String {
        guard let requestID, !requestID.isEmpty else { return message }
        return "\(message) (OpenAI request ID: \(requestID))"
    }
}

enum OpenAIHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

struct OpenAIProviderResponse {
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
        requestID = headers["x-request-id"] ?? headers["X-Request-Id"] ?? headers["openai-request-id"]
    }

    var json: JSONValue? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

struct OpenAIListRequest {
    var limit: Int?
    var order: OpenAIListOrder?
    var after: String?
    var before: String?

    init(limit: Int? = nil, order: OpenAIListOrder? = nil, after: String? = nil, before: String? = nil) {
        self.limit = limit
        self.order = order
        self.after = after
        self.before = before
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem]()
        appendCommonQueryItems(to: &items)
        return items
    }

    func appendCommonQueryItems(to items: inout [URLQueryItem]) {
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let order {
            items.append(URLQueryItem(name: "order", value: order.rawValue))
        }
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        if let before {
            items.append(URLQueryItem(name: "before", value: before))
        }
    }
}

enum OpenAIListOrder: String {
    case ascending = "asc"
    case descending = "desc"
}

struct OpenAIFileListRequest {
    var purpose: String?
    var limit: Int?
    var order: OpenAIListOrder?
    var after: String?

    init(purpose: String? = nil, limit: Int? = nil, order: OpenAIListOrder? = nil, after: String? = nil) {
        self.purpose = purpose
        self.limit = limit
        self.order = order
        self.after = after
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem]()
        if let purpose {
            items.append(URLQueryItem(name: "purpose", value: purpose))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let order {
            items.append(URLQueryItem(name: "order", value: order.rawValue))
        }
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        return items
    }
}

struct OpenAIBatchListRequest {
    var after: String?
    var limit: Int?

    init(after: String? = nil, limit: Int? = nil) {
        self.after = after
        self.limit = limit
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem]()
        if let after {
            items.append(URLQueryItem(name: "after", value: after))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return items
    }
}

struct OpenAIContainerListRequest {
    var limit: Int?
    var order: OpenAIListOrder?
    var after: String?
    var name: String?

    init(limit: Int? = nil, order: OpenAIListOrder? = nil, after: String? = nil, name: String? = nil) {
        self.limit = limit
        self.order = order
        self.after = after
        self.name = name
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem]()
        OpenAIListRequest(limit: limit, order: order, after: after).appendCommonQueryItems(to: &items)
        if let name {
            items.append(URLQueryItem(name: "name", value: name))
        }
        return items
    }
}

struct OpenAIFileUploadRequest {
    var fileName: String
    var contentType: String
    var data: Data
    var purpose: String?
    var fields: [String: String]

    init(fileName: String, contentType: String, data: Data, purpose: String? = nil, fields: [String: String] = [:]) {
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
        self.purpose = purpose
        self.fields = fields
    }

    var multipart: OpenAIMultipartForm {
        var resolvedFields = fields
        if let purpose {
            resolvedFields["purpose"] = purpose
        }
        return OpenAIMultipartForm(
            fields: resolvedFields,
            files: [
                OpenAIMultipartFile(name: "file", fileName: fileName, contentType: contentType, data: data),
            ]
        )
    }
}

struct OpenAIVectorStoreCreateRequest {
    var name: String?
    var description: String?
    var fileIDs: [String]
    var expiresAfter: JSONValue?
    var metadata: [String: String]
    var rawFields: [String: JSONValue]

    init(
        name: String? = nil,
        description: String? = nil,
        fileIDs: [String] = [],
        expiresAfter: JSONValue? = nil,
        metadata: [String: String] = [:],
        rawFields: [String: JSONValue] = [:]
    ) {
        self.name = name
        self.description = description
        self.fileIDs = fileIDs
        self.expiresAfter = expiresAfter
        self.metadata = metadata
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        if let name {
            fields["name"] = .string(name)
        }
        if let description {
            fields["description"] = .string(description)
        }
        if !fileIDs.isEmpty {
            fields["file_ids"] = .array(fileIDs.map(JSONValue.string))
        }
        if let expiresAfter {
            fields["expires_after"] = expiresAfter
        }
        if !metadata.isEmpty {
            fields["metadata"] = .object(metadata.mapValues(JSONValue.string))
        }
        return .object(fields)
    }
}

struct OpenAIContainerCreateRequest {
    var name: String?
    var memoryLimit: String?
    var expiresAfter: JSONValue?
    var networkPolicy: JSONValue?
    var skills: [JSONValue]
    var rawFields: [String: JSONValue]

    init(
        name: String? = nil,
        memoryLimit: String? = nil,
        expiresAfter: JSONValue? = nil,
        networkPolicy: JSONValue? = nil,
        skills: [JSONValue] = [],
        rawFields: [String: JSONValue] = [:]
    ) {
        self.name = name
        self.memoryLimit = memoryLimit
        self.expiresAfter = expiresAfter
        self.networkPolicy = networkPolicy
        self.skills = skills
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        if let name {
            fields["name"] = .string(name)
        }
        if let memoryLimit {
            fields["memory_limit"] = .string(memoryLimit)
        }
        if let expiresAfter {
            fields["expires_after"] = expiresAfter
        }
        if let networkPolicy {
            fields["network_policy"] = networkPolicy
        }
        if !skills.isEmpty {
            fields["skills"] = .array(skills)
        }
        return .object(fields)
    }
}

struct OpenAIImageCreateRequest {
    var model: String?
    var prompt: String
    var rawFields: [String: JSONValue]

    init(prompt: String, model: String? = nil, rawFields: [String: JSONValue] = [:]) {
        self.model = model
        self.prompt = prompt
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        fields["prompt"] = .string(prompt)
        if let model {
            fields["model"] = .string(model)
        }
        return .object(fields)
    }
}

struct OpenAIVideoCreateRequest {
    var prompt: String
    var model: String?
    var rawFields: [String: JSONValue]

    init(prompt: String, model: String? = nil, rawFields: [String: JSONValue] = [:]) {
        self.prompt = prompt
        self.model = model
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        fields["prompt"] = .string(prompt)
        if let model {
            fields["model"] = .string(model)
        }
        return .object(fields)
    }
}

struct OpenAIBatchCreateRequest {
    var inputFileID: String
    var endpoint: String
    var completionWindow: String
    var metadata: [String: String]
    var outputExpiresAfter: JSONValue?
    var rawFields: [String: JSONValue]

    init(
        inputFileID: String,
        endpoint: String,
        completionWindow: String = "24h",
        metadata: [String: String] = [:],
        outputExpiresAfter: JSONValue? = nil,
        rawFields: [String: JSONValue] = [:]
    ) {
        self.inputFileID = inputFileID
        self.endpoint = endpoint
        self.completionWindow = completionWindow
        self.metadata = metadata
        self.outputExpiresAfter = outputExpiresAfter
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        fields["input_file_id"] = .string(inputFileID)
        fields["endpoint"] = .string(endpoint)
        fields["completion_window"] = .string(completionWindow)
        if !metadata.isEmpty {
            fields["metadata"] = .object(metadata.mapValues(JSONValue.string))
        }
        if let outputExpiresAfter {
            fields["output_expires_after"] = outputExpiresAfter
        }
        return .object(fields)
    }
}

struct OpenAIRealtimeClientSecretRequest {
    var session: JSONValue?
    var expiresAfter: JSONValue?
    var rawFields: [String: JSONValue]

    init(session: JSONValue? = nil, expiresAfter: JSONValue? = nil, rawFields: [String: JSONValue] = [:]) {
        self.session = session
        self.expiresAfter = expiresAfter
        self.rawFields = rawFields
    }

    var body: JSONValue {
        var fields = rawFields
        if let session {
            fields["session"] = session
        }
        if let expiresAfter {
            fields["expires_after"] = expiresAfter
        }
        return .object(fields)
    }
}

struct OpenAIMultipartForm {
    var fields: [String: String]
    var files: [OpenAIMultipartFile]

    init(fields: [String: String] = [:], files: [OpenAIMultipartFile] = []) {
        self.fields = fields
        self.files = files
    }

    func encoded(boundary: String) -> Data {
        var data = Data()
        let lineBreak = "\r\n"
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            data.append("--\(boundary)\(lineBreak)")
            data.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
            data.append("\(value)\(lineBreak)")
        }
        for file in files {
            data.append("--\(boundary)\(lineBreak)")
            data.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.fileName)\"\(lineBreak)")
            data.append("Content-Type: \(file.contentType)\(lineBreak)\(lineBreak)")
            data.append(file.data)
            data.append(lineBreak)
        }
        data.append("--\(boundary)--\(lineBreak)")
        return data
    }
}

struct OpenAIMultipartFile {
    var name: String
    var fileName: String
    var contentType: String
    var data: Data

    init(name: String, fileName: String, contentType: String, data: Data) {
        self.name = name
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension OpenAIDeepResearchRequest {
    var openAIResponsesBody: JSONValue {
        var metadata = metadata
        metadata["pines_run_type"] = OpenAIRunKind.deepResearch.rawValue
        metadata["pines_research_request_id"] = id.uuidString
        metadata["pines_research_depth"] = depth.rawValue
        metadata["pines_research_source_scope"] = sourcePolicy.scope.rawValue

        var fields: [String: JSONValue] = [
            "model": .string(modelID.rawValue),
            "background": .bool(true),
            "store": .bool(true),
            "service_tier": .string(serviceTier.rawValue),
            "metadata": .object(metadata.mapValues(JSONValue.string)),
            "reasoning": .object([
                "effort": .string(reasoningEffort),
                "summary": .string(reasoningSummary),
            ]),
            "input": .array([
                .object([
                    "role": .string("developer"),
                    "content": .array([
                        .object([
                            "type": .string("input_text"),
                            "text": .string(developerInstructions),
                        ]),
                    ]),
                ]),
                .object([
                    "role": .string("user"),
                    "content": .array([
                        .object([
                            "type": .string("input_text"),
                            "text": .string(prompt),
                        ]),
                    ]),
                ]),
            ]),
            "include": .array([
                .string("web_search_call.action.sources"),
                .string("file_search_call.results"),
                .string("code_interpreter_call.outputs"),
            ]),
            "tools": .array(toolConfigurations),
        ]

        if let maxToolCalls {
            fields["max_tool_calls"] = .number(Double(maxToolCalls))
        }
        if let responseOutputTokenBudget {
            fields["max_output_tokens"] = .number(Double(responseOutputTokenBudget))
        }
        return .object(fields)
    }

    private var reasoningSummary: String {
        switch depth {
        case .quick:
            return "auto"
        case .standard, .deep:
            return "detailed"
        }
    }

    private var reasoningEffort: String {
        switch depth {
        case .quick:
            return "medium"
        case .standard:
            return "high"
        case .deep:
            return "xhigh"
        }
    }

    private var maxToolCalls: Int? {
        switch depth {
        case .quick:
            return 8
        case .standard:
            return 16
        case .deep:
            return 32
        }
    }

    private var developerInstructions: String {
        """
        You are running an OpenAI Deep Research workflow inside Pines.
        Produce a citation-rich \(reportFormat.rawValue) report titled "\(title)".
        Depth: \(depth.rawValue).
        Source policy: \(sourcePolicy.scope.rawValue).
        Use web research to decompose the question, gather evidence, and synthesize findings.
        Prefer primary sources and clearly distinguish facts, estimates, and uncertainty.
        Include a concise executive summary, key findings, cited evidence, and follow-up questions.
        Do not claim local Vault access unless provider-hosted files or explicitly approved MCP sources are supplied.
        """
    }

    private var toolConfigurations: [JSONValue] {
        var tools: [JSONValue] = [.object(webSearchTool)]
        if !sourcePolicy.vectorStoreIDs.isEmpty {
            tools.append(.object([
                "type": .string("file_search"),
                "vector_store_ids": .array(sourcePolicy.vectorStoreIDs.map { .string($0.rawValue) }),
            ]))
        }
        if includeCodeInterpreter {
            tools.append(.object([
                "type": .string("code_interpreter"),
                "container": .object(["type": .string("auto")]),
            ]))
        }
        if sourcePolicy.scope == .webAndMCP,
           let serverLabel = sourcePolicy.mcpServerLabel,
           let serverURL = sourcePolicy.mcpServerURL {
            tools.append(.object([
                "type": .string("mcp"),
                "server_label": .string(serverLabel),
                "server_url": .string(serverURL.absoluteString),
                "require_approval": .string(sourcePolicy.requireMCPApproval),
            ]))
        }
        return tools
    }

    private var webSearchTool: [String: JSONValue] {
        var tool: [String: JSONValue] = [
            "type": .string("web_search"),
            "search_context_size": .string(depth == .quick ? "medium" : "high"),
        ]
        var filters = [String: JSONValue]()
        if !sourcePolicy.allowedDomains.isEmpty {
            filters["allowed_domains"] = .array(sourcePolicy.allowedDomains.map(JSONValue.string))
        }
        if !sourcePolicy.blockedDomains.isEmpty {
            filters["blocked_domains"] = .array(sourcePolicy.blockedDomains.map(JSONValue.string))
        }
        if !filters.isEmpty {
            tool["filters"] = .object(filters)
        }
        if sourcePolicy.webSearchReturnTokenBudget != nil || depth == .deep {
            tool["return_token_budget"] = .string("unlimited")
        }
        return tool
    }
}
