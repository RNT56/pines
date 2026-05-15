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
    public var libraryName: String?
    public var tags: [String]
    public var task: HubTask?
    public var lastModified: Date?
    public var files: [ModelFileInfo]
    public var modelType: String?
    public var license: String?

    public init(
        repository: String,
        author: String? = nil,
        downloads: Int? = nil,
        likes: Int? = nil,
        libraryName: String? = nil,
        tags: [String] = [],
        task: HubTask? = nil,
        lastModified: Date? = nil,
        files: [ModelFileInfo] = [],
        modelType: String? = nil,
        license: String? = nil
    ) {
        self.repository = repository
        self.author = author
        self.downloads = downloads
        self.likes = likes
        self.libraryName = libraryName
        self.tags = tags
        self.task = task
        self.lastModified = lastModified
        self.files = files
        self.modelType = modelType
        self.license = license
    }

    public var preflightInput: ModelPreflightInput {
        ModelPreflightInput(
            repository: repository,
            configJSON: Self.configJSON(modelType: modelType),
            files: files,
            tags: tags,
            license: license
        )
    }

    private static func configJSON(modelType: String?) -> Data? {
        guard let modelType else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["model_type": modelType])
    }
}

public enum ModelCatalogSort: String, Hashable, Codable, Sendable, CaseIterable {
    case downloads
    case likes
    case updated = "lastModified"
}

public struct ModelSearchFilters: Hashable, Codable, Sendable {
    public var query: String
    public var task: HubTask?
    public var limit: Int
    public var sort: ModelCatalogSort
    public var descending: Bool

    public init(
        query: String = "",
        task: HubTask? = nil,
        limit: Int = 25,
        sort: ModelCatalogSort = .downloads,
        descending: Bool = true
    ) {
        self.query = query
        self.task = task
        self.limit = limit
        self.sort = sort
        self.descending = descending
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

    public func search(query: String, task: HubTask?, limit: Int = 25, accessToken: String? = nil) async throws -> [RemoteModelSummary] {
        try await search(
            filters: ModelSearchFilters(query: query, task: task, limit: limit),
            accessToken: accessToken
        )
    }

    public func search(filters: ModelSearchFilters, accessToken: String? = nil) async throws -> [RemoteModelSummary] {
        var components = URLComponents(url: baseURL.appending(path: "/api/models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "filter", value: "mlx"),
            URLQueryItem(name: "full", value: "true"),
            URLQueryItem(name: "config", value: "true"),
            URLQueryItem(name: "limit", value: String(max(1, min(filters.limit, 100)))),
            URLQueryItem(name: "sort", value: filters.sort.rawValue),
            URLQueryItem(name: "direction", value: filters.descending ? "-1" : "1"),
        ]

        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: query))
        }
        if let task = filters.task {
            components.queryItems?.append(URLQueryItem(name: "pipeline_tag", value: task.rawValue))
        }

        let url = components.url!
        let (data, response) = try await client.data(for: authorizedRequest(url: url, accessToken: accessToken))
        guard (200 ..< 300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode([HubModelDTO].self, from: data).map { dto in
            RemoteModelSummary(
                repository: dto.id,
                author: dto.author,
                downloads: dto.downloads,
                likes: dto.likes,
                libraryName: dto.libraryName,
                tags: dto.tags ?? [],
                task: dto.pipelineTag.flatMap(HubTask.init(rawValue:)),
                lastModified: dto.lastModified,
                files: dto.siblings?.map {
                    ModelFileInfo(path: $0.rfilename, size: $0.size ?? $0.lfs?.size, oid: $0.blobID ?? $0.lfs?.oid)
                } ?? [],
                modelType: dto.config?.modelType,
                license: dto.cardData?.license ?? dto.tags?.licenseTagValue
            )
        }
    }

    public func preflight(repository: String, revision: String = "main", accessToken: String? = nil) async throws -> ModelPreflightInput {
        let encodedRepository = repository
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let infoURL = baseURL.appending(path: "/api/models/\(encodedRepository)")
        let (infoData, infoResponse) = try await client.data(for: authorizedRequest(url: infoURL, accessToken: accessToken))
        guard (200 ..< 300).contains(infoResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let info = try decoder.decode(HubModelInfoDTO.self, from: infoData)
        async let config = optionalFile(repository: encodedRepository, revision: revision, path: "config.json", accessToken: accessToken)
        async let generation = optionalFile(repository: encodedRepository, revision: revision, path: "generation_config.json", accessToken: accessToken)
        async let processor = optionalFile(repository: encodedRepository, revision: revision, path: "processor_config.json", accessToken: accessToken)

        return try await ModelPreflightInput(
            repository: repository,
            configJSON: config,
            generationConfigJSON: generation,
            processorConfigJSON: processor,
            files: info.siblings?.map {
                ModelFileInfo(path: $0.rfilename, size: $0.size ?? $0.lfs?.size, oid: $0.blobID ?? $0.lfs?.oid)
            } ?? [],
            tags: info.tags ?? [],
            license: info.cardData?.license
        )
    }

    private func optionalFile(repository: String, revision: String, path: String, accessToken: String?) async throws -> Data? {
        let url = baseURL.appending(path: "/\(repository)/resolve/\(revision)/\(Self.encodedPath(path))")
        let (data, response) = try await client.data(for: authorizedRequest(url: url, accessToken: accessToken))
        if response.statusCode == 404 {
            return nil
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func authorizedRequest(url: URL, accessToken: String?) -> URLRequest {
        var request = URLRequest(url: url)
        if let accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty {
            request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func encodedPath(_ path: String) -> String {
        path.split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }
}

private struct HubModelDTO: Decodable {
    var id: String
    var author: String?
    var downloads: Int?
    var likes: Int?
    var libraryName: String?
    var tags: [String]?
    var pipelineTag: String?
    var lastModified: Date?
    var siblings: [HubSiblingDTO]?
    var config: HubModelConfigDTO?
    var cardData: HubCardDataDTO?

    enum CodingKeys: String, CodingKey {
        case id = "modelId"
        case author
        case downloads
        case likes
        case libraryName = "library_name"
        case tags
        case pipelineTag = "pipeline_tag"
        case lastModified = "lastModified"
        case siblings
        case config
        case cardData
    }
}

private struct HubModelConfigDTO: Decodable {
    var modelType: String?

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
    }
}

private struct HubModelInfoDTO: Decodable {
    var id: String
    var tags: [String]?
    var siblings: [HubSiblingDTO]?
    var cardData: HubCardDataDTO?

    enum CodingKeys: String, CodingKey {
        case id = "modelId"
        case tags
        case siblings
        case cardData
    }
}

private struct HubSiblingDTO: Decodable {
    var rfilename: String
    var size: Int64?
    var blobID: String?
    var lfs: HubLFSDTO?

    enum CodingKeys: String, CodingKey {
        case rfilename
        case size
        case blobID = "blobId"
        case lfs
    }
}

private struct HubLFSDTO: Decodable {
    var oid: String?
    var size: Int64?
}

private struct HubCardDataDTO: Decodable {
    var license: String?
}

private extension [String] {
    var licenseTagValue: String? {
        compactMap { tag -> String? in
            guard tag.localizedCaseInsensitiveContains("license:") else { return nil }
            return tag.split(separator: ":", maxSplits: 1).last.map(String.init)
        }
        .first
    }
}
