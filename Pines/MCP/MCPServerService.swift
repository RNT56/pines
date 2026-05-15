import Foundation
import PinesCore

struct MCPServerService {
    let repository: any MCPServerRepository
    let toolRegistry: ToolRegistry
    let secretStore: any SecretStore
    let auditRepository: (any AuditEventRepository)?

    func start() async {
        let servers = (try? await repository.listMCPServers()) ?? []
        for server in servers where server.enabled {
            Task {
                try? await refresh(server)
                await watchListChanges(for: server)
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
            try await unregisterTools(serverID: server.id)
        }
    }

    func deleteServer(_ server: MCPServerConfiguration) async throws {
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

    private func watchListChanges(for server: MCPServerConfiguration) async {
        let client = MCPStreamableHTTPClient(server: server, secretStore: secretStore)
        do {
            _ = try await client.initialize()
            for try await notification in client.notificationStream() {
                if notification.method == "notifications/tools/list_changed" {
                    try await refresh(server)
                }
            }
        } catch {
            var degraded = server
            degraded.status = .degraded
            degraded.lastError = error.localizedDescription
            try? await repository.upsertMCPServer(degraded)
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
