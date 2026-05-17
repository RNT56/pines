import Foundation
import PinesCore

struct AgentRunner {
    let toolRegistry: ToolRegistry
    let policyGate: ToolPolicyGate
    let auditRepository: (any AuditEventRepository)?
    let approvalHandler: @Sendable (ToolApprovalRequest) async -> ToolApprovalStatus

    init(
        toolRegistry: ToolRegistry,
        policyGate: ToolPolicyGate,
        auditRepository: (any AuditEventRepository)?,
        approvalHandler: @escaping @Sendable (ToolApprovalRequest) async -> ToolApprovalStatus = { _ in .denied }
    ) {
        self.toolRegistry = toolRegistry
        self.policyGate = policyGate
        self.auditRepository = auditRepository
        self.approvalHandler = approvalHandler
    }

    func run(
        session: AgentSession,
        request: ChatRequest,
        provider: any InferenceProvider
    ) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var messages = request.messages
                    var step = 0
                    var toolCalls = 0
                    let startedAt = Date()

                    func enforceWallTimeLimit() throws {
                        guard Date().timeIntervalSince(startedAt) <= TimeInterval(session.policy.maxWallTimeSeconds) else {
                            throw AgentError.wallTimeExceeded
                        }
                    }

                    while step < session.policy.maxSteps {
                        try enforceWallTimeLimit()
                        step += 1
                        var completedToolCalls = [ToolCallDelta]()
                        var assistantText = ""
                        var pendingFinish: InferenceFinish?
                        let currentRequest = ChatRequest(
                            id: request.id,
                            modelID: request.modelID,
                            messages: messages,
                            sampling: request.sampling,
                            allowsTools: request.allowsTools,
                            availableTools: request.availableTools,
                            vaultContextIDs: request.vaultContextIDs
                        )
                        let stream = try await provider.streamEvents(currentRequest)

                        for try await event in stream {
                            try enforceWallTimeLimit()
                            switch event {
                            case let .token(delta):
                                assistantText += delta.text
                                continuation.yield(event)
                            case let .toolCall(toolCall) where toolCall.isComplete:
                                if !completedToolCalls.contains(where: { $0.id == toolCall.id }) {
                                    completedToolCalls.append(toolCall)
                                }
                                continuation.yield(event)
                            case let .finish(finish):
                                pendingFinish = finish
                            case .failure:
                                continuation.yield(event)
                                continuation.finish()
                                return
                            default:
                                continuation.yield(event)
                            }
                        }

                        guard !completedToolCalls.isEmpty else {
                            continuation.yield(.finish(pendingFinish ?? InferenceFinish(reason: .stop)))
                            continuation.finish()
                            return
                        }

                        guard toolCalls + completedToolCalls.count <= session.policy.maxToolCalls else {
                            throw AgentError.toolLimitExceeded
                        }
                        toolCalls += completedToolCalls.count

                        messages.append(
                            ChatMessage(
                                role: .assistant,
                                content: assistantText,
                                toolCalls: completedToolCalls,
                                providerMetadata: pendingFinish?.providerMetadata ?? [:]
                            )
                        )

                        for toolCall in completedToolCalls {
                            try enforceWallTimeLimit()
                            guard let spec = await toolRegistry.spec(named: toolCall.name) else {
                                throw ToolRegistryError.toolNotFound(name: toolCall.name)
                            }
                            let invocation = ToolInvocation(
                                toolName: toolCall.name,
                                argumentsJSON: toolCall.argumentsFragment,
                                reason: "Model requested \(toolCall.name).",
                                expectedOutput: "Tool result for the next reasoning step.",
                                privacyImpact: spec.permissions.map(\.rawValue).sorted().joined(separator: ", ")
                            )
                            try policyGate.validate(invocation: invocation, spec: spec, policy: session.policy)

                            if spec.permissions.contains(.network) || spec.permissions.contains(.browser) || spec.sideEffect != .none {
                                let approval = await approvalHandler(ToolApprovalRequest(sessionID: session.id, invocation: invocation))
                                guard approval == .approved else {
                                    throw AgentError.permissionDenied("Tool \(toolCall.name) was not approved.")
                                }
                            }

                            let outputJSON = try await toolRegistry.callRaw(toolCall.name, inputJSON: toolCall.argumentsFragment)
                            try enforceWallTimeLimit()
                            try await auditRepository?.append(
                                AuditEvent(
                                    category: .tool,
                                    summary: "Ran \(toolCall.name)",
                                    toolName: toolCall.name,
                                    networkDomains: Self.networkDomains(from: spec)
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
                    }

                    throw AgentError.stepLimitExceeded
                } catch is CancellationError {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch InferenceError.cancelled {
                    continuation.yield(.finish(InferenceFinish(reason: .cancelled)))
                    continuation.finish()
                } catch {
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

    private static func networkDomains(from spec: AnyToolSpec) -> [String] {
        switch spec.networkPolicy {
        case .allowListedDomains(let domains):
            domains
        case .noNetwork, .userApproved:
            []
        }
    }
}
