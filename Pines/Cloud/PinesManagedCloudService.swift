import Foundation
import PinesCore

struct PinesManagedCloudServiceConfiguration: Hashable, Sendable {
    var gatewayBaseURL: URL?
    var clientName: String
    var appBuild: String

    static func bundleDefault(bundle: Bundle = .main) -> Self {
        let rawURL = bundle.object(forInfoDictionaryKey: "PINES_MANAGED_CLOUD_BASE_URL") as? String
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return .init(
            gatewayBaseURL: rawURL.flatMap(URL.init(string:)),
            clientName: "pines-ios",
            appBuild: "\(version) (\(build))"
        )
    }
}

struct PinesManagedCloudService: Sendable {
    private enum Constants {
        static let secretService = "com.schtack.pines.managed-cloud"
        static let installationAccount = "anonymous-installation-id"
    }

    static let installationSecretService = Constants.secretService
    static let installationSecretAccount = Constants.installationAccount

    var configuration: PinesManagedCloudServiceConfiguration
    var secretStore: any SecretStore
    var urlSession: URLSession

    init(
        configuration: PinesManagedCloudServiceConfiguration = .bundleDefault(),
        secretStore: any SecretStore,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.secretStore = secretStore
        self.urlSession = urlSession
    }

    var isConfigured: Bool {
        configuration.gatewayBaseURL != nil
    }

    func availability(entitlement: ProEntitlementStatus, consent: ManagedCloudConsent) -> ManagedCloudAvailability {
        ManagedCloudAvailability(
            entitlement: entitlement,
            consent: consent,
            gatewayConfigured: isConfigured,
            supportedFeatures: isConfigured ? ManagedCloudPolicy.defaultSupportedFeatures : []
        )
    }

    func validateEntitlement(transactionID: String) async throws -> ProEntitlementStatus {
        let envelope = ManagedCloudEntitlementValidationRequest(transactionID: transactionID)
        let response: ManagedCloudEntitlementValidationResponse = try await postJSON(envelope, path: "/v1/app-store/transactions/validate")
        return response.status
    }

    func streamEvents(_ request: ChatRequest, availability: ManagedCloudAvailability) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        guard availability.supports(.chat) else {
            throw InferenceError.cloudNotAllowed
        }
        guard let url = endpoint("/v1/chat/stream") else {
            throw InferenceError.invalidRequest("Managed Pro Cloud gateway is not configured.")
        }

        var urlRequest = try await authenticatedRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(ManagedCloudChatRequest(request: request))
        let streamRequest = urlRequest
        let session = urlSession

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: streamRequest)
                    try Self.validateHTTPResponse(response)
                    var sseDecoder = CloudProviderSSEStreamDecoder()
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(throwing: InferenceError.cancelled)
                            return
                        }
                        guard let sseEvent = sseDecoder.ingest(line),
                              let streamEvent = try Self.decodeStreamEvent(sseEvent)
                        else {
                            continue
                        }
                        continuation.yield(streamEvent)
                    }
                    if let pending = sseDecoder.finish(),
                       let streamEvent = try Self.decodeStreamEvent(pending) {
                        continuation.yield(streamEvent)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func embed(_ request: EmbeddingRequest, availability: ManagedCloudAvailability) async throws -> EmbeddingResult {
        guard availability.supports(.embeddings) else {
            throw InferenceError.cloudNotAllowed
        }
        let response: ManagedCloudEmbeddingResponse = try await postJSON(
            ManagedCloudEmbeddingRequest(request: request),
            path: "/v1/embeddings"
        )
        return EmbeddingResult(modelID: response.modelID, vectors: response.vectors)
    }

    func countTokens(_ request: ChatRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudTokenCount {
        guard availability.supports(.tokenPreflight) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(ManagedCloudChatRequest(request: request), path: "/v1/tokens/count")
    }

    func capabilityManifest() async throws -> ManagedCloudCapabilityManifest {
        try await getJSON(path: "/v1/capabilities")
    }

    func rerank(_ request: ManagedCloudRerankRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudRerankResponse {
        guard availability.supports(.rerank) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(request, path: "/v1/rerank")
    }

    func extractStructured(_ request: ManagedCloudStructuredExtractionRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudStructuredExtractionResponse {
        guard availability.supports(.structuredExtraction) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(request, path: "/v1/extract")
    }

    func analyzeFile(_ request: ManagedCloudFileAnalysisRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudArtifactResponse {
        guard availability.supports(.fileAnalysis) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(request, path: "/v1/files/analyze")
    }

    func generateMedia(_ request: ManagedCloudMediaGenerationRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudArtifactResponse {
        guard availability.supports(.generatedMedia) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(request, path: "/v1/media/generate")
    }

    func transcribe(_ request: ManagedCloudTranscriptionRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudArtifactResponse {
        guard availability.supports(.transcription) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(request, path: "/v1/audio/transcribe")
    }

    func uploadCloudCopy(_ request: ManagedCloudCopyUploadRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudCopy {
        guard availability.supports(.cloudCopies) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(request, path: "/v1/cloud-copies")
    }

    func cloudCopies(availability: ManagedCloudAvailability) async throws -> [ManagedCloudCopy] {
        guard availability.supports(.cloudCopies) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await getJSON(path: "/v1/cloud-copies")
    }

    func refreshCloudCopy(id: String, availability: ManagedCloudAvailability) async throws -> ManagedCloudCopy {
        guard availability.supports(.cloudCopies) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(ManagedCloudEmptyBody(), path: "/v1/cloud-copies/\(id)/refresh")
    }

    func startBackgroundJob(_ request: ManagedCloudBackgroundJobRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudBackgroundJob {
        guard availability.supports(.backgroundJobs) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(request, path: "/v1/background-jobs")
    }

    func backgroundJob(id: String, availability: ManagedCloudAvailability) async throws -> ManagedCloudBackgroundJob {
        guard availability.supports(.backgroundJobs) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await getJSON(path: "/v1/background-jobs/\(id)")
    }

    func cancelBackgroundJob(id: String, availability: ManagedCloudAvailability) async throws -> ManagedCloudBackgroundJob {
        guard availability.supports(.backgroundJobs) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(ManagedCloudEmptyBody(), path: "/v1/background-jobs/\(id)/cancel")
    }

    func startDeepResearch(_ request: ManagedCloudDeepResearchRequest, availability: ManagedCloudAvailability) async throws -> ManagedCloudDeepResearchRun {
        guard availability.supports(.deepResearch) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(request, path: "/v1/deep-research")
    }

    func deepResearchRun(id: String, availability: ManagedCloudAvailability) async throws -> ManagedCloudDeepResearchRun {
        guard availability.supports(.deepResearch) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await getJSON(path: "/v1/deep-research/\(id)")
    }

    func cancelDeepResearch(id: String, availability: ManagedCloudAvailability) async throws -> ManagedCloudDeepResearchRun {
        guard availability.supports(.deepResearch) else {
            throw InferenceError.cloudNotAllowed
        }
        return try await postJSON(ManagedCloudEmptyBody(), path: "/v1/deep-research/\(id)/cancel")
    }

    func deleteCloudCopy(id: String, availability: ManagedCloudAvailability) async throws {
        guard availability.supports(.cloudCopies) else {
            throw InferenceError.cloudNotAllowed
        }
        try await sendEmpty(method: "DELETE", path: "/v1/cloud-copies/\(id)")
    }

    private func getJSON<Response: Decodable & Sendable>(path: String) async throws -> Response {
        guard let url = endpoint(path) else {
            throw InferenceError.invalidRequest("Managed Pro Cloud gateway is not configured.")
        }
        var request = try await authenticatedRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await urlSession.data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func postJSON<Body: Encodable & Sendable, Response: Decodable & Sendable>(_ body: Body, path: String) async throws -> Response {
        guard let url = endpoint(path) else {
            throw InferenceError.invalidRequest("Managed Pro Cloud gateway is not configured.")
        }
        var request = try await authenticatedRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await urlSession.data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func sendEmpty(method: String, path: String) async throws {
        guard let url = endpoint(path) else {
            throw InferenceError.invalidRequest("Managed Pro Cloud gateway is not configured.")
        }
        var request = try await authenticatedRequest(url: url)
        request.httpMethod = method
        let (data, response) = try await urlSession.data(for: request)
        try Self.validateHTTPResponse(response, data: data)
    }

    private func authenticatedRequest(url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.clientName, forHTTPHeaderField: "X-Pines-Client")
        request.setValue(configuration.appBuild, forHTTPHeaderField: "X-Pines-App-Build")
        request.setValue(try await installationID(), forHTTPHeaderField: "X-Pines-Installation-ID")
        return request
    }

    private func installationID() async throws -> String {
        if let existing = try await secretStore.read(service: Constants.secretService, account: Constants.installationAccount) {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        try await secretStore.write(id, service: Constants.secretService, account: Constants.installationAccount)
        return id
    }

    private func endpoint(_ path: String) -> URL? {
        guard let gatewayBaseURL = configuration.gatewayBaseURL else { return nil }
        return gatewayBaseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 402 || http.statusCode == 429 {
                throw InferenceError.invalidRequest("Pro Cloud limit reached or temporarily throttled. Select an Advanced Key provider to continue with your own provider quota, or try again later.")
            }
            let message = String(decoding: data, as: UTF8.self)
            throw InferenceError.invalidRequest("Managed Pro Cloud request failed (\(http.statusCode)): \(message)")
        }
    }

    private static func decodeStreamEvent(_ event: CloudProviderSSEEvent) throws -> InferenceStreamEvent? {
        guard let data = event.jsonData() else { return nil }
        let envelope = try JSONDecoder().decode(ManagedCloudStreamEventEnvelope.self, from: data)
        switch envelope.type {
        case "token", "message.delta":
            return .token(envelope.token ?? TokenDelta(text: envelope.text ?? ""))
        case "tool_call", "tool.call":
            guard let toolCall = envelope.toolCall else { return nil }
            return .toolCall(toolCall)
        case "metrics":
            guard let metrics = envelope.metrics else { return nil }
            return .metrics(metrics)
        case "finish", "done":
            return .finish(envelope.finish ?? InferenceFinish(reason: .stop))
        case "failure", "error":
            return .failure(envelope.failure ?? InferenceStreamFailure(code: "managed_cloud_error", message: envelope.text ?? "Managed Pro Cloud failed."))
        default:
            return nil
        }
    }
}

struct ManagedCloudInferenceProvider: InferenceProvider {
    let id: ProviderID = ManagedCloudPolicy.providerID
    let capabilities: ProviderCapabilities = ManagedCloudPolicy.defaultCapabilities
    var service: PinesManagedCloudService
    var availability: ManagedCloudAvailability

    init(service: PinesManagedCloudService, availability: ManagedCloudAvailability) {
        self.service = service
        self.availability = availability
    }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        try await service.streamEvents(request, availability: availability)
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        try await service.embed(request, availability: availability)
    }
}

private struct ManagedCloudEmptyBody: Encodable, Sendable {}

private struct ManagedCloudEntitlementValidationRequest: Encodable, Sendable {
    var transactionID: String
}

private struct ManagedCloudEntitlementValidationResponse: Decodable, Sendable {
    var status: ProEntitlementStatus
}

private struct ManagedCloudChatRequest: Encodable, Sendable {
    var request: ChatRequest
}

private struct ManagedCloudEmbeddingRequest: Encodable, Sendable {
    var request: EmbeddingRequest
}

private struct ManagedCloudEmbeddingResponse: Decodable, Sendable {
    var modelID: ModelID
    var vectors: [[Float]]
}

private struct ManagedCloudStreamEventEnvelope: Decodable, Sendable {
    var type: String
    var text: String?
    var token: TokenDelta?
    var toolCall: ToolCallDelta?
    var finish: InferenceFinish?
    var metrics: InferenceMetrics?
    var failure: InferenceStreamFailure?
}

struct ManagedCloudTokenCount: Hashable, Codable, Sendable {
    var promptTokens: Int
    var attachmentTokens: Int
    var estimatedCompletionTokens: Int
    var estimatedCostMicrounits: Int?
}

struct ManagedCloudCapabilityManifest: Hashable, Codable, Sendable {
    var supportedFeatures: Set<ManagedCloudFeature>
    var capabilities: ProviderCapabilities
    var defaultModelID: ModelID
}

struct ManagedCloudRerankRequest: Hashable, Codable, Sendable {
    var query: String
    var candidates: [String]
    var maxResults: Int
}

struct ManagedCloudRerankResponse: Hashable, Codable, Sendable {
    struct Result: Hashable, Codable, Sendable {
        var index: Int
        var score: Double
    }

    var results: [Result]
}

struct ManagedCloudStructuredExtractionRequest: Hashable, Codable, Sendable {
    var template: String
    var text: String
    var metadata: [String: String]
}

struct ManagedCloudStructuredExtractionResponse: Hashable, Codable, Sendable {
    var template: String
    var fieldsJSON: String
    var validationErrors: [String]
}

struct ManagedCloudFileAnalysisRequest: Hashable, Codable, Sendable {
    var title: String
    var cloudCopyID: String?
    var contentBase64: String?
    var prompt: String
}

struct ManagedCloudMediaGenerationRequest: Hashable, Codable, Sendable {
    var kind: String
    var prompt: String
    var options: [String: String]
}

struct ManagedCloudTranscriptionRequest: Hashable, Codable, Sendable {
    var cloudCopyID: String?
    var audioBase64: String?
    var contentType: String
    var options: [String: String]
}

struct ManagedCloudArtifactResponse: Hashable, Codable, Sendable {
    var artifactID: String
    var title: String
    var kind: String
    var contentType: String
    var text: String?
    var bytesBase64: String?
    var cloudCopyID: String?
    var usage: [String: String]
}

struct ManagedCloudCopyUploadRequest: Hashable, Codable, Sendable {
    var fileName: String
    var contentType: String
    var contentBase64: String
    var sourceDescription: String?
}

struct ManagedCloudCopy: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var fileName: String
    var contentType: String
    var byteCount: Int
    var createdAt: Date
    var expiresAt: Date?
}

struct ManagedCloudBackgroundJobRequest: Hashable, Codable, Sendable {
    var kind: String
    var title: String
    var payload: [String: String]
}

struct ManagedCloudBackgroundJob: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var kind: String
    var title: String
    var status: String
    var progress: Double
    var resultArtifactID: String?
    var failureMessage: String?
}

struct ManagedCloudDeepResearchRequest: Hashable, Codable, Sendable {
    var title: String
    var prompt: String
    var depth: String
    var allowedSourceDomains: [String]
}

struct ManagedCloudDeepResearchRun: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var status: String
    var progress: Double
    var sources: [String]
    var reportArtifactID: String?
    var failureMessage: String?
}
