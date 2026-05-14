import Foundation

public enum BuiltInToolSpecs {
    public static func webSearchSpec() throws -> ToolSpec<WebSearchInput, WebSearchOutput> {
        try ToolSpec(
            name: "web.search",
            description: "Search the web using the user-configured search provider.",
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
        ) { _ in
            throw AgentError.permissionDenied("No web search provider is configured.")
        }
    }

    public static func browserObserveSpec() throws -> ToolSpec<BrowserObserveInput, BrowserObserveOutput> {
        try ToolSpec(
            name: "browser.observe",
            description: "Read a constrained accessibility snapshot from the isolated in-app browser.",
            inputSchema: ToolIOSchema(
                properties: [
                    "url": .init(type: .string, description: "Visible page URL."),
                ],
                required: ["url"]
            ),
            outputSchema: ToolIOSchema(
                properties: [
                    "snapshot": .init(type: .string, description: "Sanitized page snapshot."),
                ],
                required: ["snapshot"]
            ),
            permissions: [.browser, .network],
            sideEffect: .readsExternalData,
            networkPolicy: .userApproved,
            timeoutSeconds: 10,
            explanationRequired: true
        ) { _ in
            throw AgentError.permissionDenied("Browser tool requires a WKWebView runtime.")
        }
    }
}

public struct WebSearchInput: ToolInput, Equatable {
    public var query: String
    public var limit: Int

    public init(query: String, limit: Int = 5) {
        self.query = query
        self.limit = limit
    }
}

public struct WebSearchOutput: ToolOutput, Equatable {
    public var resultsJSON: String

    public init(resultsJSON: String) {
        self.resultsJSON = resultsJSON
    }
}

public struct BrowserObserveInput: ToolInput, Equatable {
    public var url: String

    public init(url: String) {
        self.url = url
    }
}

public struct BrowserObserveOutput: ToolOutput, Equatable {
    public var snapshot: String

    public init(snapshot: String) {
        self.snapshot = snapshot
    }
}
