import Foundation
import PinesCore

enum BraveSearchTool {
    static let keychainService = "com.schtack.pines.search"
    static let keychainAccount = "brave-search"

    static func spec(secretStore: any SecretStore) throws -> ToolSpec<WebSearchInput, WebSearchOutput> {
        try ToolSpec(
            name: "web.search",
            description: "Search the web using the user's Brave Search API key.",
            inputSchema: ToolIOSchema(
                properties: [
                    "query": .init(type: .string, description: "Search query."),
                    "limit": .init(type: .integer, description: "Maximum number of results."),
                ],
                required: ["query"]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "resultsJSON": .init(type: .string, description: "Serialized search results with title, url, and snippet."),
                ],
                required: ["resultsJSON"]
            ),
            permissions: [.network],
            sideEffect: .readsExternalData,
            networkPolicy: .userApproved,
            timeoutSeconds: 12,
            explanationRequired: true
        ) { input in
            guard let apiKey = try await secretStore.read(service: keychainService, account: keychainAccount), !apiKey.isEmpty else {
                throw AgentError.permissionDenied("Brave Search API key is not configured.")
            }

            var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
            components.queryItems = [
                URLQueryItem(name: "q", value: input.query),
                URLQueryItem(name: "count", value: String(max(1, min(input.limit, 10)))),
                URLQueryItem(name: "safesearch", value: "moderate"),
            ]

            var request = URLRequest(url: components.url!)
            request.addValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            let (data, http) = try await URLSession.shared.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                throw AgentError.permissionDenied("Brave Search request failed.")
            }

            let payload = try BravePayload(data: data)
            return WebSearchOutput(resultsJSON: payload.resultsJSON)
        }
    }
}

private struct BravePayload {
    var resultsJSON: String

    init(data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = ((root?["web"] as? [String: Any])?["results"] as? [[String: Any]]) ?? []
        let compact = results.map { result in
            [
                "title": result["title"] as? String ?? "",
                "url": result["url"] as? String ?? "",
                "snippet": result["description"] as? String ?? "",
            ]
        }
        let output = try JSONSerialization.data(withJSONObject: compact)
        resultsJSON = String(decoding: output, as: UTF8.self)
    }
}
