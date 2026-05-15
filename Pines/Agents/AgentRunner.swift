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

                    while step < session.policy.maxSteps {
                        step += 1
                        var nextToolCall: ToolCallDelta?
                        let currentRequest = ChatRequest(
                            id: request.id,
                            modelID: request.modelID,
                            messages: messages,
                            sampling: request.sampling,
                            allowsTools: request.allowsTools,
                            vaultContextIDs: request.vaultContextIDs
                        )
                        let stream = try await provider.streamEvents(currentRequest)

                        for try await event in stream {
                            continuation.yield(event)
                            if case let .toolCall(toolCall) = event, toolCall.isComplete {
                                nextToolCall = toolCall
                            }
                        }

                        guard let toolCall = nextToolCall else {
                            continuation.yield(.finish(InferenceFinish(reason: .stop)))
                            continuation.finish()
                            return
                        }

                        guard toolCalls < session.policy.maxToolCalls else {
                            throw AgentError.toolLimitExceeded
                        }
                        toolCalls += 1

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
                                toolCallID: toolCall.id
                            )
                        )
                    }

                    throw AgentError.stepLimitExceeded
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
                    continuation.finish(throwing: error)
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
