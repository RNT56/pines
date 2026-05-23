import Foundation
import PinesCore

#if DEBUG
struct PinesUITestInferenceProvider: InferenceProvider {
    let scenario: PinesUITestLaunchConfiguration.InferenceScenario
    let localProviderID: ProviderID

    var id: ProviderID {
        scenario == .syntheticWatchdogFinish ? localProviderID : ProviderID(rawValue: "pines-ui-test-provider")
    }

    var modelID: ModelID {
        scenario == .syntheticWatchdogFinish
            ? ModelID(rawValue: "pines-ui-test-local-model")
            : ModelID(rawValue: "pines-ui-test-model")
    }

    var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            local: scenario == .syntheticWatchdogFinish,
            streaming: true,
            textGeneration: true,
            toolCalling: false,
            maxContextTokens: 8_192,
            maxOutputTokens: 512
        )
    }

    func streamEvents(_ request: ChatRequest) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch scenario {
                    case .streaming:
                        for event in Self.responseEvents(for: request) {
                            try Task.checkCancellation()
                            continuation.yield(event)
                            try await Task.sleep(nanoseconds: 50_000_000)
                        }
                        continuation.yield(.finish(InferenceFinish(reason: .stop)))
                        continuation.finish()
                    case .slowStreaming:
                        for event in Self.responseEvents(for: request) {
                            try Task.checkCancellation()
                            continuation.yield(event)
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                        }
                        continuation.yield(
                            .metrics(
                                InferenceMetrics(
                                    promptTokens: request.messages.count * 8,
                                    completionTokens: 8,
                                    completionTokensPerSecond: 12
                                )
                            )
                        )
                        continuation.yield(.finish(InferenceFinish(reason: .stop)))
                        continuation.finish()
                    case .empty:
                        continuation.yield(.finish(InferenceFinish(reason: .stop)))
                        continuation.finish()
                    case .error:
                        continuation.yield(
                            .failure(
                                InferenceStreamFailure(
                                    code: "ui_test_provider_error",
                                    message: "UI test provider failure."
                                )
                            )
                        )
                        continuation.finish()
                    case .syntheticWatchdogFinish:
                        try await Task.sleep(nanoseconds: 500_000_000)
                        let configuration = PinesUITestLaunchConfiguration.localGenerationWatchdogConfiguration ?? .localGeneration
                        continuation.yield(
                            .finish(
                                configuration.finish(
                                    for: InferenceStreamWatchdogTimeout(
                                        stage: .firstEvent,
                                        elapsedSeconds: configuration.firstEventTimeoutSeconds
                                    )
                                )
                            )
                        )
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let dimensions = max(1, request.dimensions ?? 8)
        return EmbeddingResult(
            modelID: request.modelID,
            vectors: request.inputs.map { _ in Array(repeating: Float(0.125), count: dimensions) }
        )
    }

    private static func responseEvents(for request: ChatRequest) -> [InferenceStreamEvent] {
        let turnCount = request.messages.filter { $0.role == .user }.count
        let latestUserText = request.messages.last(where: { $0.role == .user })?.content ?? "prompt"
        let response = "UI test response \(turnCount): \(latestUserText)"
        let midpoint = response.index(response.startIndex, offsetBy: response.count / 2)
        return [
            .token(TokenDelta(text: String(response[..<midpoint]), tokenCount: 4)),
            .token(TokenDelta(text: String(response[midpoint...]), tokenCount: 4)),
        ]
    }
}
#endif
