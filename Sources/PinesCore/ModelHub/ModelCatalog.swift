import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HubTask: String, Codable, Sendable, CaseIterable {
    case textGeneration = "text-generation"
    case imageTextToText = "image-text-to-text"
    case featureExtraction = "feature-extraction"
    case sentenceSimilarity = "sentence-similarity"
}

public struct RemoteModelSummary: Identifiable, Hashable, Codable, Sendable {
    public var id: String { repository }
    public var repository: String
    public var author: String?
    public var downloads: Int?
    public var likes: Int?
    public var tags: [String]
    public var task: HubTask?
    public var lastModified: Date?

    public init(
        repository: String,
        author: String? = nil,
        downloads: Int? = nil,
        likes: Int? = nil,
        tags: [String] = [],
        task: HubTask? = nil,
        lastModified: Date? = nil
    ) {
        self.repository = repository
        self.author = author
        self.downloads = downloads
        self.likes = likes
        self.tags = tags
        self.task = task
        self.lastModified = lastModified
    }
}

public struct ModelFileInfo: Hashable, Codable, Sendable {
    public var path: String
    public var size: Int64?
    public var oid: String?

    public init(path: String, size: Int64? = nil, oid: String? = nil) {
        self.path = path
        self.size = size
        self.oid = oid
    }
}

public struct ModelPreflightInput: Hashable, Sendable {
    public var repository: String
    public var configJSON: Data?
    public var generationConfigJSON: Data?
    public var processorConfigJSON: Data?
    public var files: [ModelFileInfo]
    public var tags: [String]
    public var license: String?

    public init(
        repository: String,
        configJSON: Data?,
        generationConfigJSON: Data? = nil,
        processorConfigJSON: Data? = nil,
        files: [ModelFileInfo],
        tags: [String] = [],
        license: String? = nil
    ) {
        self.repository = repository
        self.configJSON = configJSON
        self.generationConfigJSON = generationConfigJSON
        self.processorConfigJSON = processorConfigJSON
        self.files = files
        self.tags = tags
        self.license = license
    }
}

public struct ModelPreflightResult: Hashable, Codable, Sendable {
    public var repository: String
    public var verification: ModelVerificationState
    public var modalities: Set<ModelModality>
    public var modelType: String?
    public var processorClass: String?
    public var estimatedBytes: Int64
    public var reasons: [String]
    public var license: String?

    public init(
        repository: String,
        verification: ModelVerificationState,
        modalities: Set<ModelModality>,
        modelType: String? = nil,
        processorClass: String? = nil,
        estimatedBytes: Int64 = 0,
        reasons: [String] = [],
        license: String? = nil
    ) {
        self.repository = repository
        self.verification = verification
        self.modalities = modalities
        self.modelType = modelType
        self.processorClass = processorClass
        self.estimatedBytes = estimatedBytes
        self.reasons = reasons
        self.license = license
    }
}

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPClient {
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request, delegate: nil)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

public struct HuggingFaceModelCatalogService: Sendable {
    private let client: any HTTPClient
    private let baseURL: URL
    private let decoder: JSONDecoder

    public init(
        client: any HTTPClient = URLSession.shared,
        baseURL: URL = URL(string: "https://huggingface.co")!
    ) {
        self.client = client
        self.baseURL = baseURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func search(query: String, task: HubTask?, limit: Int = 25) async throws -> [RemoteModelSummary] {
        var components = URLComponents(url: baseURL.appending(path: "/api/models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "library", value: "mlx"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
        ]

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: query))
        }
        if let task {
            components.queryItems?.append(URLQueryItem(name: "pipeline_tag", value: task.rawValue))
        }

        let url = components.url!
        let (data, response) = try await client.data(for: URLRequest(url: url))
        guard (200 ..< 300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode([HubModelDTO].self, from: data).map { dto in
            RemoteModelSummary(
                repository: dto.id,
                author: dto.author,
                downloads: dto.downloads,
                likes: dto.likes,
                tags: dto.tags ?? [],
                task: dto.pipelineTag.flatMap(HubTask.init(rawValue:)),
                lastModified: dto.lastModified
            )
        }
    }
}

private struct HubModelDTO: Decodable {
    var id: String
    var author: String?
    var downloads: Int?
    var likes: Int?
    var tags: [String]?
    var pipelineTag: String?
    var lastModified: Date?

    enum CodingKeys: String, CodingKey {
        case id = "modelId"
        case author
        case downloads
        case likes
        case tags
        case pipelineTag = "pipeline_tag"
        case lastModified = "lastModified"
    }
}
