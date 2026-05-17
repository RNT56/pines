import Foundation
import PinesCore

@MainActor
extension PinesAppModel {
    func requestToolApproval(_ request: ToolApprovalRequest) async -> ToolApprovalStatus {
        pendingToolApproval = request
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    func resolvePendingToolApproval(_ status: ToolApprovalStatus) {
        pendingToolApproval = nil
        emitHaptic(status == .approved ? .primaryAction : .runCancelled)
        approvalContinuation?.resume(returning: status)
        approvalContinuation = nil
    }

    func requestCloudContextApproval(_ request: CloudContextApprovalRequest) async -> CloudContextApprovalDecision {
        cloudContextContinuation?.resume(returning: .cancel)
        pendingCloudContextApproval = request
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            cloudContextContinuation = continuation
        }
    }

    func resolvePendingCloudContextApproval(_ decision: CloudContextApprovalDecision) {
        pendingCloudContextApproval = nil
        emitHaptic(decision == .sendWithContext ? .primaryAction : .runCancelled)
        cloudContextContinuation?.resume(returning: decision)
        cloudContextContinuation = nil
    }

    func requestCloudVaultEmbeddingApproval(_ request: CloudVaultEmbeddingApprovalRequest) async -> Bool {
        cloudVaultEmbeddingContinuation?.resume(returning: false)
        pendingCloudVaultEmbeddingApproval = request
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            cloudVaultEmbeddingContinuation = continuation
        }
    }

    func resolvePendingCloudVaultEmbeddingApproval(_ approved: Bool) {
        pendingCloudVaultEmbeddingApproval = nil
        emitHaptic(approved ? .primaryAction : .runCancelled)
        cloudVaultEmbeddingContinuation?.resume(returning: approved)
        cloudVaultEmbeddingContinuation = nil
    }

    func resolvePendingMCPSampling(_ approved: Bool) {
        pendingMCPSamplingRequest = nil
        samplingContinuation?.resume(returning: approved)
        samplingContinuation = nil
    }

    func resolvePendingMCPSamplingResultReview(_ approved: Bool) {
        pendingMCPSamplingResultReview = nil
        samplingResultContinuation?.resume(returning: approved)
        samplingResultContinuation = nil
    }

    func requestMCPSamplingApproval(_ request: MCPSamplingRequest) async -> Bool {
        pendingMCPSamplingRequest = request
        mcpSamplingPromptDraft = Self.chatText(from: request.messages)
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            samplingContinuation = continuation
        }
    }

    func requestMCPSamplingResultApproval(_ result: MCPSamplingResult, serverID: MCPServerID) async -> Bool {
        pendingMCPSamplingResultReview = MCPSamplingResultReview(
            serverID: serverID,
            result: result,
            summary: Self.samplingResultSummary(result)
        )
        emitHaptic(.toolApprovalNeeded)
        return await withCheckedContinuation { continuation in
            samplingResultContinuation = continuation
        }
    }

    func emitHaptic(_ event: PinesHapticEvent) {
        hapticSignal = PinesHapticSignal(event: event)
    }

    func handleMCPSampling(
        _ request: MCPSamplingRequest,
        server: MCPServerConfiguration,
        services: PinesAppServices
    ) async throws -> MCPSamplingResult {
        guard server.samplingEnabled else {
            throw InferenceError.unsupportedCapability("Sampling is disabled for this MCP server.")
        }
        let usedRequests = mcpSamplingRequestCountByServer[server.id, default: 0]
        guard usedRequests < server.maxSamplingRequestsPerSession else {
            throw InferenceError.invalidRequest("MCP sampling request limit reached for \(server.displayName).")
        }
        await auditMCPSampling(
            server: server,
            summary: "MCP sampling requested by \(server.displayName)",
            request: request,
            services: services
        )
        let approved = await requestMCPSamplingApproval(request)
        await auditMCPSampling(
            server: server,
            summary: approved ? "Approved MCP sampling for \(server.displayName)" : "Denied MCP sampling for \(server.displayName)",
            request: request,
            services: services
        )
        guard approved else {
            throw AgentError.permissionDenied("MCP sampling request was denied.")
        }
        mcpSamplingRequestCountByServer[server.id, default: 0] += 1
        let editedPrompt = mcpSamplingPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = try Self.chatMessages(
            from: request.messages,
            systemPrompt: request.systemPrompt,
            editedPrompt: editedPrompt.isEmpty ? nil : editedPrompt
        )
        let tools = try request.tools.map {
            try AnyToolSpec(
                name: $0.name,
                version: "mcp-sampling",
                description: $0.description ?? "MCP sampling tool \($0.name).",
                inputJSONSchema: $0.inputSchema
            )
        }
        let requiredInputs = ProviderInputRequirements(messages: messages)
        let settings: AppSettingsSnapshot?
        do {
            settings = try await services.settingsRepository?.loadSettings()
        } catch {
            settings = nil
            recordRecoverableIssue("mcp_sampling.settings_load", error: error, services: services)
        }

        if let localModelID = rankedLocalModelID(for: request, requiredInputs: requiredInputs),
           let localInstall = installedModel(for: localModelID) {
            try await services.mlxRuntime.load(
                localInstall,
                profile: localRuntimeProfile(for: localInstall, settings: settings, services: services)
            )
            let sampling = chatSampling(
                for: services.mlxRuntime.localProviderID,
                settings: settings,
                services: services,
                requestedMaxTokens: request.maxTokens,
                temperature: Float(request.temperature ?? 0.6)
            )
            let localChatRequest = ChatRequest(
                modelID: localModelID,
                messages: messages,
                sampling: sampling,
                allowsTools: !tools.isEmpty,
                availableTools: tools
            )

            do {
                let result = try await runMCPSampling(localChatRequest, provider: services.mlxRuntime, modelID: localModelID)
                let returnApproved = await requestMCPSamplingResultApproval(result, serverID: server.id)
                await auditMCPSampling(
                    server: server,
                    summary: returnApproved ? "Returned MCP sampling result to \(server.displayName)" : "Blocked MCP sampling result for \(server.displayName)",
                    request: request,
                    result: result,
                    services: services
                )
                guard returnApproved else {
                    throw AgentError.permissionDenied("MCP sampling result was not approved for return.")
                }
                return result
            } catch {
                recordRecoverableIssue("mcp_sampling.local_attempt", error: error, services: services)
            }
        }

        guard server.byokSamplingEnabled,
              let cloudProvider = rankedCloudProvider(for: request, requiredInputs: requiredInputs, requiresTools: !tools.isEmpty)
        else {
            throw InferenceError.providerUnavailable(services.mlxRuntime.localProviderID)
        }
        guard let cloudModelID = cloudProvider.defaultModelID else {
            throw InferenceError.invalidRequest("The selected cloud provider does not define a default model.")
        }
        let sampling = chatSampling(
            for: cloudProvider.id,
            settings: settings,
            services: services,
            requestedMaxTokens: request.maxTokens,
            temperature: Float(request.temperature ?? 0.6)
        )
        let cloudChatRequest = ChatRequest(
            modelID: cloudModelID,
            messages: messages,
            sampling: sampling,
            allowsTools: !tools.isEmpty,
            availableTools: tools
        )
        let provider = BYOKCloudInferenceProvider(configuration: cloudProvider, secretStore: services.secretStore)
        let result = try await runMCPSampling(
            cloudChatRequest,
            provider: provider,
            modelID: cloudModelID
        )
        let returnApproved = await requestMCPSamplingResultApproval(result, serverID: server.id)
        await auditMCPSampling(
            server: server,
            summary: returnApproved ? "Returned MCP sampling result to \(server.displayName)" : "Blocked MCP sampling result for \(server.displayName)",
            request: request,
            result: result,
            services: services
        )
        guard returnApproved else {
            throw AgentError.permissionDenied("MCP sampling result was not approved for return.")
        }
        return result
    }

    func rankedLocalModelID(for request: MCPSamplingRequest, requiredInputs: ProviderInputRequirements) -> ModelID? {
        guard !requiredInputs.requiresPDFs && !requiredInputs.requiresTextDocuments else { return nil }
        let preference = MCPModelPreferenceProfile(json: request.modelPreferences)
        let candidates = models
            .map(\.install)
            .filter { install in
                install.state == .installed
                    && install.modalities.contains(.text)
                    && (!requiredInputs.requiresImages || install.modalities.contains(.vision))
            }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { left, right in
            samplingModelScore(install: left, preference: preference) < samplingModelScore(install: right, preference: preference)
        }?.modelID
    }

    func installedModel(for modelID: ModelID) -> ModelInstall? {
        models
            .map(\.install)
            .first { install in
                install.modelID == modelID && install.state == .installed
            }
    }

    func providerDisplayName(for providerID: ProviderID, services: PinesAppServices) -> String {
        if providerID == services.mlxRuntime.localProviderID {
            return "Local"
        }
        return cloudProviders.first(where: { $0.id == providerID })?.displayName ?? providerID.rawValue
    }

    func emptyCloudOutputMessage(
        providerID: ProviderID,
        modelID: ModelID,
        services: PinesAppServices
    ) -> String {
        guard providerID != services.mlxRuntime.localProviderID else {
            return "The selected model finished without producing output."
        }
        let providerName = providerDisplayName(for: providerID, services: services)
        return "\(providerName) returned a successful stream for \(modelID.rawValue), but Pines did not receive visible text. Check the provider event diagnostics above and retry with a text-capable chat model."
    }

    func messageWithProviderDiagnostics(_ message: String, metadata: [String: String]) -> String {
        let diagnosticKeys = [
            CloudProviderMetadataKeys.openAIRequestID,
            CloudProviderMetadataKeys.openAIResponseID,
            CloudProviderMetadataKeys.openAIChatCompletionID,
            CloudProviderMetadataKeys.openAIModel,
            CloudProviderMetadataKeys.openAISystemFingerprint,
            CloudProviderMetadataKeys.anthropicRequestID,
            CloudProviderMetadataKeys.anthropicMessageID,
            CloudProviderMetadataKeys.geminiRequestID,
            CloudProviderMetadataKeys.geminiResponseID,
            CloudProviderMetadataKeys.geminiInteractionID,
            CloudProviderMetadataKeys.geminiModelVersion,
            LocalProviderMetadataKeys.turboQuantActiveBackend,
            LocalProviderMetadataKeys.turboQuantAttentionPath,
            LocalProviderMetadataKeys.turboQuantKernelProfile,
            LocalProviderMetadataKeys.turboQuantSelfTestStatus,
            LocalProviderMetadataKeys.turboQuantFallbackReason,
            LocalProviderMetadataKeys.turboQuantLastUnsupportedShape,
        ]
        let diagnostics = diagnosticKeys.compactMap { key -> String? in
            guard let value = metadata[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }
        guard !diagnostics.isEmpty else { return message }
        return "\(message)\n\nProvider diagnostics: \(diagnostics.joined(separator: ", "))"
    }

    func providerKind(for providerID: ProviderID, services: PinesAppServices) -> CloudProviderKind? {
        if providerID == services.mlxRuntime.localProviderID {
            return nil
        }
        return cloudProviders.first(where: { $0.id == providerID })?.kind
    }

    func displayName(for modelID: ModelID, providerID: ProviderID) -> String {
        if let install = installedModel(for: modelID), install.modelID == modelID {
            return Self.localModelDisplayName(install)
        }
        if let model = cloudModelCatalog[providerID]?.first(where: { $0.id == modelID }) {
            return model.displayName
        }
        return Self.friendlyModelName(modelID.rawValue)
    }

    func localModelScore(_ install: ModelInstall) -> Double {
        let parameterScale = min(Double(install.parameterCount ?? 0) / 10_000_000_000, 10)
        let byteScale = min(Double(install.estimatedBytes ?? 0) / 10_000_000_000, 10)
        return parameterScale * 10 + byteScale
    }

    func rankedCloudProvider(for request: MCPSamplingRequest, requiredInputs: ProviderInputRequirements, requiresTools: Bool) -> CloudProviderConfiguration? {
        let preference = MCPModelPreferenceProfile(json: request.modelPreferences)
        let candidates = cloudProviders.filter { provider in
            provider.enabledForAgents
                && provider.capabilities.textGeneration
                && requiredInputs.isSatisfied(by: provider.capabilities)
                && (!requiresTools || provider.capabilities.toolCalling)
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { left, right in
            samplingCloudScore(provider: left, preference: preference) < samplingCloudScore(provider: right, preference: preference)
        }
    }

    func samplingModelScore(install: ModelInstall, preference: MCPModelPreferenceProfile) -> Double {
        let searchable = [
            install.modelID.rawValue,
            install.displayName,
            install.repository,
            install.modelType ?? "",
            install.processorClass ?? "",
        ].joined(separator: " ").lowercased()
        var score = 10.0
        for hint in preference.hints {
            let normalizedHint = hint.lowercased()
            if searchable == normalizedHint {
                score += 120
            } else if searchable.contains(normalizedHint) {
                score += 60
            }
        }
        if install.modelID == defaultModelID {
            score += 12
        }
        let parameterScale = min(Double(install.parameterCount ?? 0) / 10_000_000_000, 1)
        let byteScale = min(Double(install.estimatedBytes ?? 0) / 10_000_000_000, 1)
        score += preference.intelligencePriority * parameterScale * 24
        score += preference.speedPriority * (1 - max(parameterScale, byteScale)) * 18
        score += preference.costPriority * (1 - byteScale) * 12
        return score
    }

    func samplingCloudScore(provider: CloudProviderConfiguration, preference: MCPModelPreferenceProfile) -> Double {
        let searchable = [
            provider.displayName,
            provider.kind.rawValue,
            provider.baseURL.host(percentEncoded: false) ?? "",
            provider.defaultModelID?.rawValue ?? "",
        ].joined(separator: " ").lowercased()
        var score = 5.0
        for hint in preference.hints {
            let normalizedHint = hint.lowercased()
            if searchable == normalizedHint {
                score += 120
            } else if searchable.contains(normalizedHint) {
                score += 60
            }
        }
        score += preference.intelligencePriority * 8
        score += preference.speedPriority * (provider.kind == .openAICompatible ? 6 : 4)
        score -= preference.costPriority * 4
        return score
    }

    func auditMCPSampling(
        server: MCPServerConfiguration,
        summary: String,
        request: MCPSamplingRequest,
        result: MCPSamplingResult? = nil,
        services: PinesAppServices
    ) async {
        let payload = [
            "server=\(server.id.rawValue)",
            "messages=\(request.messages.count)",
            "tools=\(request.tools.count)",
            "maxTokens=\(request.maxTokens ?? 512)",
            "includeContext=\(request.includeContext ?? "unspecified")",
            result.map { "result=\(Self.samplingResultKind($0))" },
        ].compactMap { $0 }.joined(separator: ", ")
        await appendAuditEvent(
            AuditEvent(
                category: .consent,
                summary: summary,
                redactedPayload: payload,
                networkDomains: server.endpointURL.host(percentEncoded: false).map { [$0] } ?? []
            ),
            services: services,
            component: "mcp_sampling"
        )
    }

    static func samplingResultKind(_ result: MCPSamplingResult) -> String {
        switch result.content {
        case .text:
            return "text"
        case .toolUse:
            return "tool_use"
        case .toolResult:
            return "tool_result"
        case .resource:
            return "resource"
        case .image:
            return "image"
        case .audio:
            return "audio"
        case .unknown:
            return "unknown"
        }
    }

    func runMCPSampling(
        _ request: ChatRequest,
        provider: any InferenceProvider,
        modelID: ModelID
    ) async throws -> MCPSamplingResult {
        let stream = try await provider.streamEvents(request)
        var text = ""
        var stopReason = "endTurn"
        for try await event in stream {
            switch event {
            case let .token(delta):
                text += delta.text
            case let .toolCall(toolCall):
                let input: JSONValue
                do {
                    input = try JSONDecoder().decode(JSONValue.self, from: Data(toolCall.argumentsFragment.utf8))
                } catch {
                    throw InferenceError.invalidRequest("MCP sampling tool call arguments were not valid JSON: \(error.localizedDescription)")
                }
                return MCPSamplingResult(
                    content: .toolUse(id: toolCall.id, name: toolCall.name, input: input),
                    model: modelID.rawValue,
                    stopReason: "toolUse"
                )
            case let .finish(finish):
                stopReason = finish.reason == .length ? "maxTokens" : "endTurn"
            case let .failure(failure):
                throw InferenceError.invalidRequest(failure.message)
            case .metrics:
                break
            }
        }
        return MCPSamplingResult(content: .text(text), model: modelID.rawValue, stopReason: stopReason)
    }

    static func chatMessages(from messages: [MCPPromptMessage], systemPrompt: String?, editedPrompt: String? = nil) throws -> [ChatMessage] {
        var chatMessages = [ChatMessage]()
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatMessages.append(ChatMessage(role: .system, content: systemPrompt))
        }
        if let editedPrompt, !editedPrompt.isEmpty {
            chatMessages.append(ChatMessage(role: .user, content: editedPrompt))
            return chatMessages
        }
        for message in messages {
            let role: ChatRole = message.role == .assistant ? .assistant : .user
            let converted = try textAndAttachments(from: message.content)
            chatMessages.append(ChatMessage(role: role, content: converted.text, attachments: converted.attachments))
        }
        return chatMessages
    }

    static func samplingResultSummary(_ result: MCPSamplingResult) -> String {
        switch result.content {
        case let .text(text):
            return text
        case let .toolUse(id, name, _):
            return "Tool use \(id): \(name)"
        case let .toolResult(toolUseID, content):
            let text: String
            do {
                text = try textAndAttachments(from: content).text
            } catch {
                text = "[Unreadable tool result content: \(error.localizedDescription)]"
            }
            return "Tool result \(toolUseID)\n\(text)"
        case let .resource(resource):
            return resource.text ?? "[Resource: \(resource.uri)]"
        case let .image(_, mimeType):
            return "[Image: \(mimeType)]"
        case let .audio(_, mimeType):
            return "[Audio: \(mimeType)]"
        case .unknown:
            return "[Unsupported sampling result content]"
        }
    }

    static func chatText(from messages: [MCPPromptMessage]) -> String {
        messages.map { message in
            do {
                return try textAndAttachments(from: message.content).text
            } catch {
                return "[Unreadable prompt content: \(error.localizedDescription)]"
            }
        }.joined(separator: "\n\n")
    }

    static func textAndAttachments(from contents: [MCPMessageContent]) throws -> (text: String, attachments: [ChatAttachment]) {
        var parts = [String]()
        var attachments = [ChatAttachment]()
        for content in contents {
            switch content {
            case let .text(text):
                parts.append(text)
            case let .resource(resource):
                if let text = resource.text {
                    parts.append(text)
                } else if let blob = resource.blob {
                    let attachment = try mcpAttachment(
                        fromBase64: blob,
                        mimeType: resource.mimeType,
                        fileNameHint: resource.uri
                    )
                    attachments.append(attachment)
                    parts.append("[Embedded resource attachment: \(attachment.fileName), \(attachment.contentType)]")
                }
            case let .image(data, mimeType):
                let attachment = try mcpAttachment(fromBase64: data, mimeType: mimeType, fileNameHint: "sampling-image")
                guard attachment.kind == .image else {
                    throw InferenceError.unsupportedCapability("MCP image content used unsupported MIME type \(mimeType).")
                }
                attachments.append(attachment)
                parts.append("[Image: \(attachment.contentType)]")
            case .audio:
                throw InferenceError.unsupportedCapability("Audio sampling content is not supported yet.")
            case let .toolUse(id, name, _):
                parts.append("[Tool use \(id): \(name)]")
            case let .toolResult(toolUseID, content):
                let nested = try textAndAttachments(from: content)
                parts.append("[Tool result \(toolUseID)]\n\(nested.text)")
            case .unknown:
                break
            }
        }
        return (parts.joined(separator: "\n\n"), attachments)
    }

    private static let maxMCPAttachmentBytes = 10 * 1024 * 1024

    static func mcpAttachment(fromBase64 data: String, mimeType: String?, fileNameHint: String) throws -> ChatAttachment {
        guard let decoded = Data(base64Encoded: data) else {
            throw InferenceError.invalidRequest("MCP resource content was not valid base64.")
        }
        guard decoded.count <= maxMCPAttachmentBytes else {
            throw InferenceError.invalidRequest("MCP resource exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(maxMCPAttachmentBytes), countStyle: .file)) attachment limit.")
        }
        let normalizedMimeType = (mimeType ?? "application/octet-stream").lowercased()
        guard let policy = mcpAttachmentPolicy(for: normalizedMimeType) else {
            throw InferenceError.unsupportedCapability("MCP resource MIME type \(normalizedMimeType) is not allowed as an attachment.")
        }
        let safeName = sanitizedMCPFileName(from: fileNameHint, fallbackExtension: policy.fileExtension)
        let url = FileManager.default.temporaryDirectory.appending(path: "mcp-\(UUID().uuidString)-\(safeName)")
        try decoded.write(to: url)
        return ChatAttachment(
            kind: policy.kind,
            fileName: url.lastPathComponent,
            contentType: normalizedMimeType,
            localURL: url,
            byteCount: decoded.count
        )
    }

    static func mcpAttachmentPolicy(for mimeType: String) -> (kind: AttachmentKind, fileExtension: String)? {
        switch mimeType {
        case "image/png":
            return (.image, "png")
        case "image/jpeg", "image/jpg":
            return (.image, "jpg")
        case "image/webp":
            return (.image, "webp")
        case "image/gif":
            return (.image, "gif")
        case "application/pdf":
            return (.document, "pdf")
        case "text/plain":
            return (.document, "txt")
        case "text/markdown", "text/x-markdown":
            return (.document, "md")
        case "application/json":
            return (.document, "json")
        case "text/csv":
            return (.document, "csv")
        default:
            return nil
        }
    }

    static func sanitizedMCPFileName(from hint: String, fallbackExtension: String) -> String {
        let candidate = hint
            .split(separator: "/")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "resource"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitizedScalars = candidate.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
        var name = sanitizedScalars.joined().trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        if name.isEmpty {
            name = "resource"
        }
        if !name.lowercased().hasSuffix(".\(fallbackExtension)") {
            name += ".\(fallbackExtension)"
        }
        return String(name.prefix(96))
    }

}
