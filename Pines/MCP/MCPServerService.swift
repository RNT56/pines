import Foundation
import OSLog
import PinesCore

struct MCPServerService: Sendable {
    let repository: any MCPServerRepository
    let toolRegistry: ToolRegistry
    let secretStore: any SecretStore
    let auditRepository: (any AuditEventRepository)?

    private static let logger = Logger(subsystem: "com.schtack.pines", category: "mcp-server")
    private static let watchTasks = MCPServerWatchTaskRegistry()

    typealias SamplingHandler = @Sendable (_ request: MCPSamplingRequest, _ server: MCPServerConfiguration) async throws -> MCPSamplingResult

    func start(samplingHandler: SamplingHandler? = nil) async {
        let servers: [MCPServerConfiguration]
        do {
            servers = try await repository.listMCPServers()
        } catch {
            Self.logger.error("mcp_start_failed_to_list_servers error=\(error.localizedDescription, privacy: .public)")
            return
        }
        await Self.watchTasks.stopServers(excluding: Set(servers.filter(\.enabled).map(\.id)))
        for server in servers where server.enabled {
            await Self.watchTasks.start(serverID: server.id) {
                do {
                    try await refresh(server)
                } catch {
                    Self.logger.error("mcp_start_refresh_failed server=\(server.id.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                }
                await watchEvents(for: server, samplingHandler: samplingHandler)
            }
        }
    }

    func saveServer(_ server: MCPServerConfiguration, bearerToken: String?) async throws {
        if let bearerToken, !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await secretStore.write(bearerToken, service: server.keychainService, account: server.keychainAccount)
        }
        try await repository.upsertMCPServer(server)
        try await auditRepository?.append(
            AuditEvent(
                category: .security,
                summary: "Saved MCP server \(server.displayName)",
                networkDomains: Self.networkDomains(for: server)
            )
        )
        if server.enabled {
            try await refresh(server)
        } else {
            await Self.watchTasks.stop(serverID: server.id)
            try await unregisterTools(serverID: server.id)
        }
    }

    func deleteServer(_ server: MCPServerConfiguration) async throws {
        await Self.watchTasks.stop(serverID: server.id)
        try await unregisterTools(serverID: server.id)
        try await secretStore.delete(service: server.keychainService, account: server.keychainAccount)
        try await secretStore.delete(service: server.keychainService, account: "\(server.keychainAccount).access_token")
        try await secretStore.delete(service: server.keychainService, account: "\(server.keychainAccount).refresh_token")
        try await repository.deleteMCPServer(id: server.id)
        try await auditRepository?.append(
            AuditEvent(category: .security, summary: "Deleted MCP server \(server.displayName)")
        )
    }

    func refresh(_ server: MCPServerConfiguration) async throws {
        var connecting = server
        connecting.status = .connecting
        connecting.lastError = nil
        try await repository.upsertMCPServer(connecting)

        do {
            let client = MCPStreamableHTTPClient(server: connecting, secretStore: secretStore)
            _ = try await client.initialize()
            let tools = try await client.listTools()
            let records = Self.toolRecords(from: tools, server: connecting)
            try await repository.replaceMCPTools(records, serverID: server.id)
            if server.resourcesEnabled {
                try await refreshResources(server: connecting, client: client)
            }
            if server.promptsEnabled {
                try await refreshPrompts(server: connecting, client: client)
            }

            var ready = connecting
            ready.status = .ready
            ready.lastError = nil
            ready.lastConnectedAt = Date()
            try await repository.upsertMCPServer(ready)
            try await registerEnabledTools(server: ready, client: client)
            try await auditRepository?.append(
                AuditEvent(
                    category: .tool,
                    summary: "Discovered \(records.count) MCP tools from \(server.displayName)",
                    networkDomains: Self.networkDomains(for: server)
                )
            )
        } catch {
            try await unregisterTools(serverID: server.id)
            var failed = server
            failed.status = server.authMode == .none ? .failed : .requiresAuthentication
            failed.lastError = error.localizedDescription
            try await repository.upsertMCPServer(failed)
            throw error
        }
    }

    func setToolEnabled(serverID: MCPServerID, namespacedName: String, enabled: Bool) async throws {
        try await repository.updateMCPToolEnabled(serverID: serverID, namespacedName: namespacedName, enabled: enabled)
        let servers = try await repository.listMCPServers()
        if let server = servers.first(where: { $0.id == serverID }), server.enabled {
            try await refresh(server)
        }
    }

    func refreshResources(_ server: MCPServerConfiguration) async throws {
        let client = MCPStreamableHTTPClient(server: server, secretStore: secretStore)
        _ = try await client.initialize()
        try await refreshResources(server: server, client: client)
    }

    func refreshPrompts(_ server: MCPServerConfiguration) async throws {
        let client = MCPStreamableHTTPClient(server: server, secretStore: secretStore)
        _ = try await client.initialize()
        try await refreshPrompts(server: server, client: client)
    }

    func readResource(_ resource: MCPResourceRecord) async throws -> [MCPResourceContent] {
        guard let server = try await repository.listMCPServers().first(where: { $0.id == resource.serverID }) else {
            throw ToolRegistryError.toolNotFound(name: resource.serverID.rawValue)
        }
        let client = MCPStreamableHTTPClient(server: server, secretStore: secretStore)
        _ = try await client.initialize()
        return try await client.readResource(uri: resource.uri)
    }

    func setResourceSelected(_ resource: MCPResourceRecord, selected: Bool) async throws {
        try await repository.updateMCPResourceSelection(serverID: resource.serverID, uri: resource.uri, selected: selected)
    }

    func setResourceSubscribed(_ resource: MCPResourceRecord, subscribed: Bool) async throws {
        guard let server = try await repository.listMCPServers().first(where: { $0.id == resource.serverID }) else {
            throw ToolRegistryError.toolNotFound(name: resource.serverID.rawValue)
        }
        let client = MCPStreamableHTTPClient(server: server, secretStore: secretStore)
        _ = try await client.initialize()
        if subscribed {
            try await client.subscribeResource(uri: resource.uri)
        } else {
            try await client.unsubscribeResource(uri: resource.uri)
        }
        try await repository.updateMCPResourceSubscription(serverID: resource.serverID, uri: resource.uri, subscribed: subscribed)
    }

    func getPrompt(_ prompt: MCPPromptRecord, arguments: [String: String]) async throws -> MCPPromptResult {
        guard let server = try await repository.listMCPServers().first(where: { $0.id == prompt.serverID }) else {
            throw ToolRegistryError.toolNotFound(name: prompt.serverID.rawValue)
        }
        let client = MCPStreamableHTTPClient(server: server, secretStore: secretStore)
        _ = try await client.initialize()
        return try await client.getPrompt(name: prompt.name, arguments: arguments)
    }

    private func registerEnabledTools(server: MCPServerConfiguration, client: MCPStreamableHTTPClient) async throws {
        try await unregisterTools(serverID: server.id)
        let tools = try await repository.listMCPTools(serverID: server.id)
        for tool in tools where tool.enabled {
            let metadata = try AnyToolSpec(
                name: tool.namespacedName,
                version: "mcp",
                description: tool.description.isEmpty ? "Remote MCP tool \(tool.originalName)." : tool.description,
                inputJSONSchema: tool.inputSchema,
                outputJSONSchema: JSONValue.objectSchema(),
                permissions: [.network],
                sideEffect: .readsExternalData,
                networkPolicy: .allowListedDomains(Self.networkDomains(for: server)),
                timeoutSeconds: 60,
                explanationRequired: true,
                inputType: "MCPToolArguments",
                outputType: "MCPToolResult"
            )
            let originalName = tool.originalName
            try await toolRegistry.registerRaw(metadata) { inputJSON in
                let result = try await client.callTool(name: originalName, argumentsJSON: inputJSON)
                return try Self.outputJSON(from: result)
            }
        }
    }

    private func unregisterTools(serverID: MCPServerID) async throws {
        let existing = try await repository.listMCPTools(serverID: serverID)
        for tool in existing {
            await toolRegistry.unregister(tool.namespacedName)
        }
        let registered = await toolRegistry.listSpecs()
        for spec in registered where spec.name.hasPrefix("mcp.\(serverID.rawValue).") {
            await toolRegistry.unregister(spec.name)
        }
    }

    private func refreshResources(server: MCPServerConfiguration, client: MCPStreamableHTTPClient) async throws {
        let resources = try await client.listResources()
        let templates = try await client.listResourceTemplates()
        try await repository.replaceMCPResources(resources, serverID: server.id)
        try await repository.replaceMCPResourceTemplates(templates, serverID: server.id)
    }

    private func refreshPrompts(server: MCPServerConfiguration, client: MCPStreamableHTTPClient) async throws {
        let prompts = try await client.listPrompts()
        try await repository.replaceMCPPrompts(prompts, serverID: server.id)
    }

    private func watchEvents(for server: MCPServerConfiguration, samplingHandler: SamplingHandler?) async {
        let client = MCPStreamableHTTPClient(server: server, secretStore: secretStore)
        do {
            _ = try await client.initialize()
            for try await event in client.serverEventStream() {
                switch event {
                case let .notification(notification) where notification.method == "notifications/tools/list_changed":
                    try await refresh(server)
                case let .notification(notification) where notification.method == "notifications/resources/list_changed" || notification.method == "notifications/resources/updated":
                    if server.resourcesEnabled {
                        try await refreshResources(server)
                    }
                case let .notification(notification) where notification.method == "notifications/prompts/list_changed":
                    if server.promptsEnabled {
                        try await refreshPrompts(server)
                    }
                case let .samplingRequest(id, request):
                    guard server.samplingEnabled, let samplingHandler else {
                        try await client.sendJSONRPCError(id: id, code: -32000, message: "Sampling is disabled for this MCP server.")
                        continue
                    }
                    do {
                        let result = try await samplingHandler(request, server)
                        try await client.sendSamplingResult(id: id, result: result)
                    } catch {
                        try await client.sendJSONRPCError(id: id, code: -32000, message: error.localizedDescription)
                    }
                case let .request(id, method, _):
                    try await client.sendJSONRPCError(id: id, code: -32601, message: "Unsupported client request: \(method)")
                case .notification:
                    break
                }
            }
        } catch {
            var degraded = server
            degraded.status = .degraded
            degraded.lastError = error.localizedDescription
            do {
                try await repository.upsertMCPServer(degraded)
            } catch {
                Self.logger.error("mcp_degraded_state_persist_failed server=\(server.id.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func toolRecords(from tools: [MCPToolDefinition], server: MCPServerConfiguration) -> [MCPToolRecord] {
        let serverSlug = MCPNameSanitizer.serverSlug(displayName: server.displayName, fallback: server.id.rawValue)
        var used = Set<String>()
        return tools.enumerated().map { index, tool in
            var namespacedName = MCPNameSanitizer.toolName(serverSlug: serverSlug, originalName: tool.name)
            if used.contains(namespacedName) {
                namespacedName = MCPNameSanitizer.toolName(serverSlug: serverSlug, originalName: "\(tool.name)-\(index + 1)")
            }
            used.insert(namespacedName)
            return MCPToolRecord(
                serverID: server.id,
                originalName: tool.name,
                namespacedName: namespacedName,
                displayName: tool.name,
                description: tool.description ?? "Remote MCP tool \(tool.name).",
                inputSchema: tool.inputSchema
            )
        }
    }

    private static func outputJSON(from result: MCPToolCallResult) throws -> String {
        let data = try JSONEncoder().encode(result)
        let maxBytes = 32 * 1024
        guard data.count > maxBytes else {
            return String(decoding: data, as: UTF8.self)
        }
        let text = String(decoding: data.prefix(maxBytes), as: UTF8.self)
        let truncated = JSONValue.object([
            "truncated": .bool(true),
            "content": .string(text),
        ])
        return String(decoding: try JSONEncoder().encode(truncated), as: UTF8.self)
    }

    private static func networkDomains(for server: MCPServerConfiguration) -> [String] {
        server.endpointURL.host(percentEncoded: false).map { [$0] } ?? []
    }
}

private actor MCPServerWatchTaskRegistry {
    private var tasks: [MCPServerID: (token: UUID, task: Task<Void, Never>)] = [:]

    func start(serverID: MCPServerID, operation: @escaping @Sendable () async -> Void) {
        tasks[serverID]?.task.cancel()

        let token = UUID()
        let task = Task.detached(priority: .background) {
            await operation()
            await self.removeFinished(serverID: serverID, token: token)
        }
        tasks[serverID] = (token, task)
    }

    func stop(serverID: MCPServerID) {
        tasks.removeValue(forKey: serverID)?.task.cancel()
    }

    func stopServers(excluding activeServerIDs: Set<MCPServerID>) {
        let staleServerIDs = tasks.keys.filter { !activeServerIDs.contains($0) }
        for serverID in staleServerIDs {
            stop(serverID: serverID)
        }
    }

    private func removeFinished(serverID: MCPServerID, token: UUID) {
        guard tasks[serverID]?.token == token else { return }
        tasks[serverID] = nil
    }
}
