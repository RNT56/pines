import Foundation
import PinesCore

struct GeminiProviderService {
    private static let interactionsHeaders = ["Api-Revision": "2026-05-20"]

    let configuration: CloudProviderConfiguration
    let secretStore: any SecretStore
    var urlSession: URLSession = .shared

    func rawJSON(
        method: GeminiHTTPMethod,
        path: String,
        apiVersion: String = "v1beta",
        queryItems: [URLQueryItem] = [],
        body: JSONValue? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> GeminiProviderResponse {
        try await send(
            method: method,
            path: path,
            apiVersion: apiVersion,
            queryItems: queryItems,
            body: body.map { try JSONEncoder().encode($0) },
            contentType: body == nil ? nil : "application/json",
            extraHeaders: extraHeaders
        )
    }

    func startResumableUpload(
        displayName: String? = nil,
        mimeType: String,
        byteCount: Int
    ) async throws -> GeminiUploadSession {
        var file = [String: JSONValue]()
        if let displayName, !displayName.isEmpty {
            file["displayName"] = .string(displayName)
        }
        let response = try await send(
            method: .post,
            path: "files",
            apiVersion: "upload/v1beta",
            body: try JSONEncoder().encode(JSONValue.object(["file": .object(file)])),
            contentType: "application/json",
            extraHeaders: [
                "X-Goog-Upload-Protocol": "resumable",
                "X-Goog-Upload-Command": "start",
                "X-Goog-Upload-Header-Content-Type": mimeType,
                "X-Goog-Upload-Header-Content-Length": String(byteCount),
            ]
        )
        guard let uploadURL = response.headerValue("X-Goog-Upload-URL") else {
            throw CloudProviderError.invalidResponse
        }
        return GeminiUploadSession(uploadURL: uploadURL, response: response)
    }

    func uploadResumableData(
        to uploadURL: String,
        data: Data,
        offset: Int = 0,
        finalize: Bool = true
    ) async throws -> GeminiProviderResponse {
        guard let url = URL(string: uploadURL) else {
            throw CloudProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue(finalize ? "upload, finalize" : "upload", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.addValue(String(offset), forHTTPHeaderField: "X-Goog-Upload-Offset")
        try await applyExtraHeaders(to: &request)
        return try await send(request)
    }

    func listFiles(_ request: GeminiListRequest = GeminiListRequest()) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .get, path: "files", queryItems: request.queryItems)
    }

    func getFile(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .get, path: normalizedResourcePath(name, defaultCollection: "files"))
    }

    func deleteFile(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .delete, path: normalizedResourcePath(name, defaultCollection: "files"))
    }

    func countTokens(modelID: ModelID, body: JSONValue) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .post, path: "\(normalizedModelPath(modelID)):countTokens", body: body)
    }

    func generateContent(modelID: ModelID, body: JSONValue) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .post, path: "\(normalizedModelPath(modelID)):generateContent", body: body)
    }

    func streamGenerateContent(modelID: ModelID, body: JSONValue) async throws -> GeminiProviderResponse {
        try await rawJSON(
            method: .post,
            path: "\(normalizedModelPath(modelID)):streamGenerateContent",
            queryItems: [URLQueryItem(name: "alt", value: "sse")],
            body: body
        )
    }

    func batchGenerateContent(modelID: ModelID, body: JSONValue) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .post, path: "\(normalizedModelPath(modelID)):batchGenerateContent", body: body)
    }

    func generateVideos(modelID: ModelID, body: JSONValue) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .post, path: "\(normalizedModelPath(modelID)):generateVideos", body: body)
    }

    func predict(modelID: ModelID, body: JSONValue) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .post, path: "\(normalizedModelPath(modelID)):predict", body: body)
    }

    func createCachedContent(body: JSONValue) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .post, path: "cachedContents", body: body)
    }

    func listCachedContents(_ request: GeminiListRequest = GeminiListRequest()) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .get, path: "cachedContents", queryItems: request.queryItems)
    }

    func getCachedContent(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .get, path: normalizedResourcePath(name, defaultCollection: "cachedContents"))
    }

    func updateCachedContent(
        _ name: String,
        body: JSONValue,
        updateMask: String? = nil
    ) async throws -> GeminiProviderResponse {
        let queryItems = updateMask.map { [URLQueryItem(name: "updateMask", value: $0)] } ?? []
        return try await rawJSON(
            method: .patch,
            path: normalizedResourcePath(name, defaultCollection: "cachedContents"),
            queryItems: queryItems,
            body: body
        )
    }

    func deleteCachedContent(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .delete, path: normalizedResourcePath(name, defaultCollection: "cachedContents"))
    }

    func listModels(_ request: GeminiListRequest = GeminiListRequest(pageSize: 100)) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .get, path: "models", queryItems: request.queryItems)
    }

    func getModel(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .get, path: normalizedResourcePath(name, defaultCollection: "models"))
    }

    func getOperation(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .get, path: normalizedResourcePath(name, defaultCollection: "operations"))
    }

    func cancelOperation(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .post, path: "\(normalizedResourcePath(name, defaultCollection: "operations")):cancel")
    }

    func createInteraction(body: JSONValue, stream: Bool = false) async throws -> GeminiProviderResponse {
        let queryItems = stream ? [URLQueryItem(name: "alt", value: "sse")] : []
        return try await rawJSON(method: .post, path: "interactions", queryItems: queryItems, body: body, extraHeaders: Self.interactionsHeaders)
    }

    func getInteraction(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .get, path: normalizedResourcePath(name, defaultCollection: "interactions"), extraHeaders: Self.interactionsHeaders)
    }

    func cancelInteraction(_ name: String) async throws -> GeminiProviderResponse {
        try await rawJSON(method: .post, path: "\(normalizedResourcePath(name, defaultCollection: "interactions")):cancel", extraHeaders: Self.interactionsHeaders)
    }

    private func send(
        method: GeminiHTTPMethod,
        path: String,
        apiVersion: String = "v1beta",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> GeminiProviderResponse {
        guard let apiKey = try await readAPIKey() else {
            throw CloudProviderError.missingAPIKey
        }

        var request = URLRequest(url: try url(path: path, apiVersion: apiVersion, queryItems: queryItems))
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in extraHeaders {
            request.addValue(value, forHTTPHeaderField: name)
        }
        try await applyExtraHeaders(to: &request)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> GeminiProviderResponse {
        let (data, http) = try await urlSession.data(for: request)
        let providerResponse = GeminiProviderResponse(data: data, httpResponse: http)
        guard (200..<300).contains(http.statusCode) else {
            throw CloudProviderError.providerRejectedRequest(
                statusCode: http.statusCode,
                message: BYOKCloudInferenceProvider.messageWithRequestID(
                    BYOKCloudInferenceProvider.providerErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                    requestID: providerResponse.requestID,
                    providerKind: .gemini
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

    private func url(path: String, apiVersion: String, queryItems: [URLQueryItem]) throws -> URL {
        var url = configuration.baseURL
        for segment in apiVersion.split(separator: "/").map(String.init) + path.split(separator: "/").map(String.init) {
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

    private func normalizedModelPath(_ modelID: ModelID) -> String {
        let raw = modelID.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.hasPrefix("models/") ? raw : "models/\(raw)"
    }

    private func normalizedResourcePath(_ name: String, defaultCollection: String) -> String {
        let raw = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.contains("/") ? raw : "\(defaultCollection)/\(raw)"
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
}

enum GeminiHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct GeminiProviderResponse {
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
        requestID = Self.headerValue("x-request-id", in: headers)
            ?? Self.headerValue("x-goog-request-id", in: headers)
            ?? Self.headerValue("x-cloud-trace-context", in: headers)
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

struct GeminiUploadSession {
    var uploadURL: String
    var response: GeminiProviderResponse
}

struct GeminiListRequest {
    var pageSize: Int?
    var pageToken: String?

    init(pageSize: Int? = nil, pageToken: String? = nil) {
        self.pageSize = pageSize
        self.pageToken = pageToken
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem]()
        if let pageSize {
            items.append(URLQueryItem(name: "pageSize", value: String(pageSize)))
        }
        if let pageToken, !pageToken.isEmpty {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return items
    }
}
