import Foundation
import PinesCore

struct AgentRuntimeCallbacks: Sendable {
    let approvalHandler: @Sendable (ToolApprovalRequest) async -> ToolApprovalStatus
    let activityHandler: @Sendable (AgentActivityEvent) async -> Void

    init(
        approvalHandler: @escaping @Sendable (ToolApprovalRequest) async -> ToolApprovalStatus = { _ in .denied },
        activityHandler: @escaping @Sendable (AgentActivityEvent) async -> Void = { _ in }
    ) {
        self.approvalHandler = approvalHandler
        self.activityHandler = activityHandler
    }
}

protocol AgentRuntime: Sendable {
    func run(
        session: AgentSession,
        request: ChatRequest,
        provider: any InferenceProvider
    ) -> AsyncThrowingStream<InferenceStreamEvent, Error>
}

protocol AgentRuntimeFactory: Sendable {
    func makeRuntime(callbacks: AgentRuntimeCallbacks) -> any AgentRuntime
}

protocol AgentToolCatalog: Sendable {
    func availableTools(enabledToolNames: Set<String>?) async -> [AnyToolSpec]
}

struct DefaultAgentRuntimeFactory: AgentRuntimeFactory {
    let toolRegistry: ToolRegistry
    let policyGate: ToolPolicyGate
    let auditRepository: (any AuditEventRepository)?

    func makeRuntime(callbacks: AgentRuntimeCallbacks) -> any AgentRuntime {
        AgentRunner(
            toolRegistry: toolRegistry,
            policyGate: policyGate,
            auditRepository: auditRepository,
            approvalHandler: callbacks.approvalHandler,
            activityHandler: callbacks.activityHandler
        )
    }
}

struct RegistryAgentToolCatalog: AgentToolCatalog {
    let secretStore: any SecretStore
    let toolRegistry: ToolRegistry

    func availableTools(enabledToolNames: Set<String>?) async -> [AnyToolSpec] {
        let hasBraveSearchKey: Bool
        do {
            hasBraveSearchKey = try await secretStore.read(
                service: BraveSearchTool.keychainService,
                account: BraveSearchTool.keychainAccount
            )?.isEmpty == false
        } catch {
            hasBraveSearchKey = false
        }

        let allowed = enabledToolNames
        let specs = await toolRegistry.listSpecs()
        return specs
            .filter { spec in
                guard allowed.map({ $0.contains(spec.name) }) ?? true else { return false }
                switch spec.name {
                case CalculatorTool.name,
                     TimeNowTool.name,
                     DateCalculateTool.name,
                     WebFetchTool.name,
                     AttachmentReadTool.name,
                     VaultSearchTool.name,
                     VaultReadTool.name,
                     ConversationSearchTool.name:
                    return true
                case "web.search":
                    return hasBraveSearchKey
                case "browser.observe", "browser.action":
                    return true
                default:
                    return spec.name.hasPrefix("mcp.")
                }
            }
            .sorted { left, right in
                Self.sortKey(left.name) < Self.sortKey(right.name)
            }
    }

    private static func sortKey(_ name: String) -> String {
        switch name {
        case CalculatorTool.name:
            "00-\(name)"
        case TimeNowTool.name:
            "01-\(name)"
        case DateCalculateTool.name:
            "02-\(name)"
        case AttachmentReadTool.name:
            "03-\(name)"
        case VaultSearchTool.name:
            "04-\(name)"
        case VaultReadTool.name:
            "05-\(name)"
        case ConversationSearchTool.name:
            "06-\(name)"
        case "web.search":
            "10-\(name)"
        case WebFetchTool.name:
            "11-\(name)"
        case "browser.observe":
            "20-\(name)"
        case "browser.action":
            "30-\(name)"
        default:
            "90-\(name)"
        }
    }
}

struct AgentRunner: AgentRuntime {
    private static let maxSearchCalls = 3

    let toolRegistry: ToolRegistry
    let policyGate: ToolPolicyGate
    let auditRepository: (any AuditEventRepository)?
    let approvalHandler: @Sendable (ToolApprovalRequest) async -> ToolApprovalStatus
    let activityHandler: @Sendable (AgentActivityEvent) async -> Void

    init(
        toolRegistry: ToolRegistry,
        policyGate: ToolPolicyGate,
        auditRepository: (any AuditEventRepository)?,
        approvalHandler: @escaping @Sendable (ToolApprovalRequest) async -> ToolApprovalStatus = { _ in .denied },
        activityHandler: @escaping @Sendable (AgentActivityEvent) async -> Void = { _ in }
    ) {
        self.toolRegistry = toolRegistry
        self.policyGate = policyGate
        self.auditRepository = auditRepository
        self.approvalHandler = approvalHandler
        self.activityHandler = activityHandler
    }

    private struct SkippedToolCall {
        var toolCall: ToolCallDelta
        var reason: String
    }

    private static func availableTools(
        from tools: [AnyToolSpec],
        searchCalls: Int
    ) -> [AnyToolSpec] {
        guard searchCalls >= maxSearchCalls else { return tools }
        return tools.filter { $0.name != "web.search" }
    }

    private static func executableToolCalls(
        from toolCalls: [ToolCallDelta],
        remainingToolCalls: Int,
        remainingSearchCalls: Int,
        repeatedToolCalls: inout [String: Int]
    ) -> (executable: [ToolCallDelta], skipped: [SkippedToolCall]) {
        var executable = [ToolCallDelta]()
        var skipped = [SkippedToolCall]()
        var searchCalls = 0

        for toolCall in toolCalls {
            guard executable.count < remainingToolCalls else {
                skipped.append(SkippedToolCall(toolCall: toolCall, reason: "Skipped \(toolCall.name) because the agent reached the tool-call budget."))
                continue
            }
            if toolCall.name == "web.search" {
                guard searchCalls < remainingSearchCalls else {
                    skipped.append(SkippedToolCall(toolCall: toolCall, reason: "Skipped web.search because the agent already used the 3-search refinement budget."))
                    continue
                }
                searchCalls += 1
            }

            let repeatKey = "\(toolCall.name)::\(toolCall.argumentsFragment)"
            repeatedToolCalls[repeatKey, default: 0] += 1
            guard repeatedToolCalls[repeatKey, default: 0] <= 2 else {
                skipped.append(SkippedToolCall(toolCall: toolCall, reason: "Skipped repeated \(toolCall.name) call because it was not making progress."))
                continue
            }
            executable.append(toolCall)
        }

        return (executable, skipped)
    }

    func run(
        session: AgentSession,
        request: ChatRequest,
        provider: any InferenceProvider
    ) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var messages = request.messages
                let executionContext = request.executionContext
                let isAgentContext = executionContext == .agent

                do {
                    var step = 0
                    var toolCalls = 0
                    var searchCalls = 0
                    var repeatedToolCalls = [String: Int]()
                    let startedAt = Date()
                    let toolRunContext = AgentToolRunContext(messages: request.messages)

                    func enforceWallTimeLimit() throws {
                        guard Date().timeIntervalSince(startedAt) <= TimeInterval(session.policy.maxWallTimeSeconds) else {
                            throw AgentError.wallTimeExceeded
                        }
                    }

                    func synthesizeFinalAnswer(reason: String) async throws {
                        guard isAgentContext else {
                            throw AgentError.toolLimitExceeded
                        }
                        try enforceWallTimeLimit()
                        var synthesisMessages = messages
                        synthesisMessages.insert(
                            ChatMessage(
                                role: .system,
                                content: """
                                Agent final response required. Do not call tools. Answer the user's inquiry using only the gathered tool evidence in this conversation. Write a processed response, not raw tool output. Cite source URLs when available. If the evidence is incomplete, say what is known and what could not be verified. Reason: \(reason)
                                """
                            ),
                            at: 0
                        )
                        let synthesisRequest = ChatRequest(
                            id: request.id,
                            modelID: request.modelID,
                            messages: synthesisMessages,
                            sampling: request.sampling,
                            webSearchOptions: request.webSearchOptions,
                            allowsTools: false,
                            availableTools: [],
                            vaultContextIDs: request.vaultContextIDs,
                            executionContext: executionContext
                        )
                        var finalText = ""
                        do {
                            let stream = try await provider.streamEvents(synthesisRequest)
                            for try await event in stream {
                                try enforceWallTimeLimit()
                                switch event {
                                case let .token(delta):
                                    finalText += delta.text
                                    continuation.yield(event)
                                case let .finish(finish):
                                    if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        let fallback = Self.fallbackAnswer(from: messages, request: request)
                                        finalText = fallback
                                        continuation.yield(.token(TokenDelta(text: fallback, tokenCount: 1)))
                                    }
                                    continuation.yield(.finish(finish.reason == .cancelled ? finish : InferenceFinish(reason: .stop, providerMetadata: finish.providerMetadata)))
                                    continuation.finish()
                                    return
                                case .toolCall:
                                    continue
                                case let .metrics(metrics):
                                    continuation.yield(.metrics(metrics))
                                case let .failure(failure):
                                    if Self.hasToolEvidence(messages) {
                                        throw AgentError.toolLimitExceeded
                                    }
                                    continuation.yield(.failure(failure))
                                    continuation.finish()
                                    return
                                }
                            }
                        } catch is CancellationError {
                            throw InferenceError.cancelled
                        } catch InferenceError.cancelled {
                            throw InferenceError.cancelled
                        } catch {
                            guard Self.hasToolEvidence(messages) else {
                                throw error
                            }
                            let fallback = Self.fallbackAnswer(from: messages, request: request)
                            continuation.yield(.token(TokenDelta(text: fallback, tokenCount: 1)))
                            continuation.yield(.finish(InferenceFinish(reason: .stop)))
                            continuation.finish()
                            return
                        }

                        if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            guard Self.hasToolEvidence(messages) else {
                                continuation.yield(
                                    .failure(
                                        InferenceStreamFailure(
                                            code: "agent_empty_final_response",
                                            message: "The agent could not produce a final response.",
                                            recoverable: true
                                        )
                                    )
                                )
                                continuation.finish()
                                return
                            }
                            let fallback = Self.fallbackAnswer(from: messages, request: request)
                            continuation.yield(.token(TokenDelta(text: fallback, tokenCount: 1)))
                        }
                        continuation.yield(.finish(InferenceFinish(reason: .stop)))
                        continuation.finish()
                    }

                    while step < session.policy.maxSteps {
                        try enforceWallTimeLimit()
                        step += 1
                        var completedToolCalls = [ToolCallDelta]()
                        var assistantText = ""
                        var bufferedTokenEvents = [TokenDelta]()
                        var pendingFinish: InferenceFinish?
                        let availableTools = isAgentContext
                            ? Self.availableTools(from: request.availableTools, searchCalls: searchCalls)
                            : request.availableTools
                        guard !isAgentContext || toolCalls < session.policy.maxToolCalls else {
                            try await synthesizeFinalAnswer(reason: "The agent reached the tool-call budget.")
                            return
                        }
                        let currentRequest = ChatRequest(
                            id: request.id,
                            modelID: request.modelID,
                            messages: messages,
                            sampling: request.sampling,
                            webSearchOptions: request.webSearchOptions,
                            allowsTools: request.allowsTools,
                            availableTools: availableTools,
                            vaultContextIDs: request.vaultContextIDs,
                            executionContext: executionContext
                        )
                        let stream = try await provider.streamEvents(currentRequest)

                        for try await event in stream {
                            try enforceWallTimeLimit()
                            switch event {
                            case let .token(delta):
                                assistantText += delta.text
                                if isAgentContext {
                                    bufferedTokenEvents.append(delta)
                                } else {
                                    continuation.yield(event)
                                }
                            case let .toolCall(toolCall) where toolCall.isComplete:
                                if !completedToolCalls.contains(where: { $0.id == toolCall.id }) {
                                    completedToolCalls.append(toolCall)
                                }
                                continuation.yield(event)
                            case let .finish(finish):
                                pendingFinish = finish
                            case let .failure(failure):
                                if isAgentContext, Self.hasToolEvidence(messages) {
                                    try await synthesizeFinalAnswer(reason: "The model stopped after gathering evidence: \(failure.message)")
                                    return
                                }
                                continuation.yield(.failure(failure))
                                continuation.finish()
                                return
                            default:
                                continuation.yield(event)
                            }
                        }

                        guard !completedToolCalls.isEmpty else {
                            if isAgentContext {
                                for delta in bufferedTokenEvents {
                                    continuation.yield(.token(delta))
                                }
                            }
                            continuation.yield(.finish(pendingFinish ?? InferenceFinish(reason: .stop)))
                            continuation.finish()
                            return
                        }

                        let selection: (executable: [ToolCallDelta], skipped: [SkippedToolCall])
                        if isAgentContext {
                            selection = Self.executableToolCalls(
                                from: completedToolCalls,
                                remainingToolCalls: max(0, session.policy.maxToolCalls - toolCalls),
                                remainingSearchCalls: max(0, Self.maxSearchCalls - searchCalls),
                                repeatedToolCalls: &repeatedToolCalls
                            )
                        } else {
                            selection = (executable: completedToolCalls, skipped: [])
                        }
                        for skipped in selection.skipped {
                            await activityHandler(
                                Self.activityEvent(
                                    id: UUID(),
                                    toolCall: skipped.toolCall,
                                    status: .denied,
                                    argumentsJSON: skipped.toolCall.argumentsFragment,
                                    detailOverride: skipped.reason,
                                    startedAt: Date(),
                                    completedAt: Date()
                                )
                            )
                        }
                        guard !selection.executable.isEmpty else {
                            try await synthesizeFinalAnswer(reason: selection.skipped.first?.reason ?? "The agent could not run more tools.")
                            return
                        }
                        toolCalls += selection.executable.count
                        searchCalls += selection.executable.filter { $0.name == "web.search" }.count

                        messages.append(
                            ChatMessage(
                                role: .assistant,
                                content: assistantText,
                                toolCalls: selection.executable,
                                providerMetadata: pendingFinish?.providerMetadata ?? [:]
                            )
                        )

                        for toolCall in selection.executable {
                            try enforceWallTimeLimit()
                            guard let spec = await toolRegistry.spec(named: toolCall.name) else {
                                throw ToolRegistryError.toolNotFound(name: toolCall.name)
                            }
                            let activityID = UUID()
                            let activityStartedAt = Date()
                            let plannedActivity = Self.activityEvent(
                                id: activityID,
                                toolCall: toolCall,
                                status: .running,
                                argumentsJSON: toolCall.argumentsFragment,
                                startedAt: activityStartedAt
                            )
                            let invocation = ToolInvocation(
                                toolName: toolCall.name,
                                argumentsJSON: toolCall.argumentsFragment,
                                reason: plannedActivity.detail,
                                expectedOutput: "Tool result for the next reasoning step.",
                                privacyImpact: spec.permissions.map(\.rawValue).sorted().joined(separator: ", ")
                            )
                            try policyGate.validate(invocation: invocation, spec: spec, policy: session.policy)

                            if spec.permissions.contains(.network) || spec.permissions.contains(.browser) || spec.sideEffect != .none {
                                await activityHandler(
                                    Self.activityEvent(
                                        id: activityID,
                                        toolCall: toolCall,
                                        status: .waitingForApproval,
                                        argumentsJSON: toolCall.argumentsFragment,
                                        startedAt: activityStartedAt
                                    )
                                )
                                let approval = await approvalHandler(ToolApprovalRequest(sessionID: session.id, invocation: invocation))
                                guard approval == .approved else {
                                    await activityHandler(
                                        Self.activityEvent(
                                            id: activityID,
                                            toolCall: toolCall,
                                            status: .denied,
                                            argumentsJSON: toolCall.argumentsFragment,
                                            detailOverride: "The tool call was denied.",
                                            startedAt: activityStartedAt,
                                            completedAt: Date()
                                        )
                                    )
                                    throw AgentError.permissionDenied("Tool \(toolCall.name) was not approved.")
                                }
                            }

                            await activityHandler(
                                Self.activityEvent(
                                    id: activityID,
                                    toolCall: toolCall,
                                    status: .running,
                                    argumentsJSON: toolCall.argumentsFragment,
                                    startedAt: activityStartedAt
                                )
                            )
                            let rawOutputJSON: String
                            do {
                                rawOutputJSON = try await AgentToolExecutionContext.$current.withValue(toolRunContext) {
                                    try await toolRegistry.callRaw(toolCall.name, inputJSON: toolCall.argumentsFragment)
                                }
                            } catch {
                                rawOutputJSON = Self.toolErrorJSON(error)
                            }
                            try enforceWallTimeLimit()
                            let outputJSON = Self.modelVisibleToolOutput(
                                invocation: invocation,
                                spec: spec,
                                rawOutputJSON: rawOutputJSON,
                                provider: provider,
                                executionContext: executionContext
                            )
                            try await auditRepository?.append(
                                AuditEvent(
                                    category: .tool,
                                    summary: rawOutputJSON.contains(#""error""#) ? "Tool \(toolCall.name) returned an error" : "Ran \(toolCall.name)",
                                    toolName: toolCall.name,
                                    networkDomains: Self.networkDomains(from: spec)
                                )
                            )
                            await activityHandler(
                                Self.activityEvent(
                                    id: activityID,
                                    toolCall: toolCall,
                                    status: Self.rawOutputIndicatesError(rawOutputJSON) ? .failed : .completed,
                                    argumentsJSON: toolCall.argumentsFragment,
                                    rawOutputJSON: rawOutputJSON,
                                    startedAt: activityStartedAt,
                                    completedAt: Date()
                                )
                            )
                            messages.append(
                                ChatMessage(
                                    role: .tool,
                                    content: outputJSON,
                                    toolCallID: toolCall.id,
                                    toolName: toolCall.name
                                )
                            )
                        }
                        if let skippedReason = selection.skipped.first?.reason {
                            try await synthesizeFinalAnswer(reason: skippedReason)
                            return
                        }
                    }

                    try await synthesizeFinalAnswer(reason: "The agent reached the step limit.")
                } catch is CancellationError {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch InferenceError.cancelled {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch {
                    if isAgentContext, Self.hasToolEvidence(messages) {
                        let fallback = Self.fallbackAnswer(from: messages, request: request)
                        continuation.yield(.token(TokenDelta(text: fallback, tokenCount: 1)))
                        continuation.yield(.finish(InferenceFinish(reason: .stop)))
                        continuation.finish()
                        return
                    }
                    continuation.yield(
                        .failure(
                            InferenceStreamFailure(
                                code: "agent_run_failed",
                                message: error.localizedDescription,
                                recoverable: false
                            )
                        )
                    )
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func activityEvent(
        id: UUID,
        toolCall: ToolCallDelta,
        status: AgentActivityStatus,
        argumentsJSON: String,
        rawOutputJSON: String? = nil,
        detailOverride: String? = nil,
        startedAt: Date,
        completedAt: Date? = nil
    ) -> AgentActivityEvent {
        let arguments = jsonObject(argumentsJSON)
        let toolName = toolCall.name
        let title = activityTitle(toolName: toolName, arguments: arguments)
        let detail = detailOverride ?? activityDetail(
            toolName: toolName,
            arguments: arguments,
            status: status,
            rawOutputJSON: rawOutputJSON
        )
        return AgentActivityEvent(
            id: id,
            toolCallID: toolCall.id,
            toolName: toolName,
            title: title,
            detail: detail,
            status: status,
            links: activityLinks(toolName: toolName, arguments: arguments, rawOutputJSON: rawOutputJSON),
            startedAt: startedAt,
            completedAt: completedAt
        )
    }

    private static func activityTitle(toolName: String, arguments: [String: Any]) -> String {
        switch toolName {
        case "web.search":
            "Search the web"
        case "browser.observe":
            "Read page"
        case "browser.action":
            browserActionTitle(kind: arguments["kind"] as? String)
        case CalculatorTool.name:
            "Calculate"
        default:
            toolName.hasPrefix("mcp.") ? "Use MCP tool" : "Use tool"
        }
    }

    private static func browserActionTitle(kind: String?) -> String {
        switch kind {
        case "navigate":
            "Open page"
        case "click":
            "Click page element"
        case "typeText":
            "Type into page"
        case "submit":
            "Submit page form"
        case "screenshot":
            "Capture page"
        case "stop":
            "Stop page loading"
        default:
            "Use browser"
        }
    }

    private static func activityDetail(
        toolName: String,
        arguments: [String: Any],
        status: AgentActivityStatus,
        rawOutputJSON: String?
    ) -> String {
        if status == .failed, let message = errorMessage(from: rawOutputJSON) {
            return message
        }

        switch toolName {
        case "web.search":
            let query = arguments["query"] as? String ?? "the web"
            if status == .completed, let count = searchResultCount(from: rawOutputJSON) {
                return "Found \(count) result\(count == 1 ? "" : "s") for \"\(query)\"."
            }
            return status == .waitingForApproval ? "Waiting to search for \"\(query)\"." : "Searching for \"\(query)\"."
        case "browser.observe":
            let url = arguments["url"] as? String ?? "the current page"
            return status == .completed ? "Read \(url)." : "Reading \(url)."
        case "browser.action":
            if status == .completed, let summary = browserSummary(from: rawOutputJSON), !summary.isEmpty {
                return summary
            }
            if let url = arguments["url"] as? String, !url.isEmpty {
                return status == .waitingForApproval ? "Waiting to open \(url)." : "Opening \(url)."
            }
            if let selector = arguments["selector"] as? String, !selector.isEmpty {
                return "\(browserActionVerb(kind: arguments["kind"] as? String)) \(selector)."
            }
            return "Using the isolated browser."
        case CalculatorTool.name:
            let expression = arguments["expression"] as? String ?? "expression"
            return status == .completed ? "Calculated \(expression)." : "Calculating \(expression)."
        default:
            return status == .completed ? "Tool finished." : "Running \(toolName)."
        }
    }

    private static func browserActionVerb(kind: String?) -> String {
        switch kind {
        case "click":
            "Clicking"
        case "typeText":
            "Typing into"
        case "submit":
            "Submitting"
        default:
            "Using"
        }
    }

    private static func activityLinks(
        toolName: String,
        arguments: [String: Any],
        rawOutputJSON: String?
    ) -> [AgentActivityLink] {
        switch toolName {
        case "web.search":
            return searchLinks(from: rawOutputJSON)
        case "browser.observe", "browser.action":
            guard let url = arguments["url"] as? String, !url.isEmpty else { return [] }
            return [AgentActivityLink(title: urlHostOrAbsolute(url), url: url)]
        default:
            return []
        }
    }

    private static func searchLinks(from rawOutputJSON: String?) -> [AgentActivityLink] {
        guard let resultsJSON = outputString(named: "resultsJSON", from: rawOutputJSON),
              let data = resultsJSON.data(using: .utf8),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return results.prefix(5).compactMap { result in
            guard let url = result["url"] as? String, !url.isEmpty else { return nil }
            let title = (result["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? urlHostOrAbsolute(url)
            return AgentActivityLink(title: title, url: url)
        }
    }

    private static func searchResultCount(from rawOutputJSON: String?) -> Int? {
        guard let resultsJSON = outputString(named: "resultsJSON", from: rawOutputJSON),
              let data = resultsJSON.data(using: .utf8),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return results.count
    }

    private static func browserSummary(from rawOutputJSON: String?) -> String? {
        outputString(named: "summary", from: rawOutputJSON)
    }

    private static func errorMessage(from rawOutputJSON: String?) -> String? {
        outputString(named: "message", from: rawOutputJSON)
    }

    private static func outputString(named key: String, from rawOutputJSON: String?) -> String? {
        guard let rawOutputJSON,
              let data = rawOutputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[key] as? String
    }

    private static func rawOutputIndicatesError(_ rawOutputJSON: String) -> Bool {
        guard let data = rawOutputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return rawOutputJSON.contains(#""error""#) }
        return object["error"] as? Bool == true
    }

    private static func jsonObject(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private static func urlHostOrAbsolute(_ value: String) -> String {
        URL(string: value)?.host ?? value
    }

    private static func modelVisibleToolOutput(
        invocation: ToolInvocation,
        spec: AnyToolSpec,
        rawOutputJSON: String,
        provider: any InferenceProvider,
        executionContext: ChatRequest.ExecutionContext
    ) -> String {
        if executionContext == .agent,
           provider.capabilities.local,
           ["web.search", WebFetchTool.name, "browser.observe", "browser.action"].contains(spec.name) {
            return AgentEvidenceFormatter.modelVisibleOutput(
                toolName: spec.name,
                rawOutputJSON: rawOutputJSON
            )
        }
        let untrusted = spec.permissions.contains(.network) || spec.permissions.contains(.browser) || spec.name.hasPrefix("mcp.")
        guard untrusted else {
            return rawOutputJSON
        }
        let envelope = ToolResultEnvelope(
            invocationID: invocation.id,
            toolName: invocation.toolName,
            outputJSON: rawOutputJSON,
            untrusted: true,
            networkDomains: networkDomains(from: spec)
        )
        do {
            return String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
        } catch {
            return rawOutputJSON
        }
    }

    private static func fallbackAnswer(from messages: [ChatMessage], request: ChatRequest) -> String {
        let userRequest = request.messages.last(where: { $0.role == .user })?.content ?? ""
        return AgentEvidenceFormatter.fallbackAnswer(from: messages, userRequest: userRequest)
    }

    private static func hasToolEvidence(_ messages: [ChatMessage]) -> Bool {
        messages.contains { message in
            message.role == .tool && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func toolErrorJSON(_ error: any Error) -> String {
        let payload: [String: Any] = [
            "error": true,
            "message": error.localizedDescription,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return #"{"error":true,"message":"Tool failed."}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func networkDomains(from spec: AnyToolSpec) -> [String] {
        switch spec.networkPolicy {
        case .allowListedDomains(let domains):
            domains
        case .noNetwork, .userApproved:
            []
        }
    }
}
