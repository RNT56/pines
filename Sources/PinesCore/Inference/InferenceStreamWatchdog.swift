import Foundation

public enum InferenceStreamWatchdogTimeoutStage: String, Hashable, Codable, Sendable {
    case firstEvent = "first_event"
    case progress
}

public struct InferenceStreamWatchdogConfiguration: Hashable, Sendable {
    public var firstEventTimeoutSeconds: TimeInterval
    public var progressTimeoutSeconds: TimeInterval
    public var pollIntervalSeconds: TimeInterval
    public var code: String
    public var firstEventMessage: String
    public var progressMessage: String

    public init(
        firstEventTimeoutSeconds: TimeInterval,
        progressTimeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 2,
        code: String = "inference_stream_watchdog_timeout",
        firstEventMessage: String = "The inference stream stalled before producing output.",
        progressMessage: String = "The inference stream stopped making progress."
    ) {
        self.firstEventTimeoutSeconds = max(0.1, firstEventTimeoutSeconds)
        self.progressTimeoutSeconds = max(0.1, progressTimeoutSeconds)
        self.pollIntervalSeconds = max(0.05, pollIntervalSeconds)
        self.code = code
        self.firstEventMessage = firstEventMessage
        self.progressMessage = progressMessage
    }

    public static let localGeneration = InferenceStreamWatchdogConfiguration(
        firstEventTimeoutSeconds: 90,
        progressTimeoutSeconds: 45,
        pollIntervalSeconds: 2,
        code: "local_generation_watchdog_timeout",
        firstEventMessage: "Local generation stalled before the model produced output. The runtime was cancelled and unloaded so the device can recover.",
        progressMessage: "Local generation stopped making progress. The runtime was cancelled and unloaded so the device can recover."
    )

    public func finish(for timeout: InferenceStreamWatchdogTimeout) -> InferenceFinish {
        InferenceFinish(
            reason: .error,
            message: timeout.stage == .firstEvent ? firstEventMessage : progressMessage,
            providerMetadata: [
                LocalProviderMetadataKeys.generationWatchdogCode: code,
                LocalProviderMetadataKeys.generationWatchdogStage: timeout.stage.rawValue,
                LocalProviderMetadataKeys.generationWatchdogElapsedSeconds: String(timeout.elapsedSeconds),
            ]
        )
    }
}

public struct InferenceStreamWatchdogTimeout: Hashable, Sendable {
    public var stage: InferenceStreamWatchdogTimeoutStage
    public var elapsedSeconds: TimeInterval

    public init(stage: InferenceStreamWatchdogTimeoutStage, elapsedSeconds: TimeInterval) {
        self.stage = stage
        self.elapsedSeconds = elapsedSeconds
    }
}

public enum InferenceStreamWatchdog {
    public static func guarded(
        _ source: AsyncThrowingStream<InferenceStreamEvent, Error>,
        configuration: InferenceStreamWatchdogConfiguration
    ) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let state = InferenceStreamWatchdogState()
            let consumerTask = Task {
                do {
                    for try await event in source {
                        try Task.checkCancellation()
                        await state.mark(event)
                        continuation.yield(event)
                        if event.isTerminal {
                            continuation.finish()
                            return
                        }
                    }
                    await state.finish()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch {
                    await state.finish()
                    continuation.finish(throwing: error)
                }
            }
            let watchdogTask = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(configuration.pollIntervalSeconds * 1_000_000_000))
                    } catch {
                        return
                    }
                    guard let timeout = await state.timeout(configuration: configuration) else {
                        continue
                    }
                    continuation.yield(.finish(configuration.finish(for: timeout)))
                    continuation.finish()
                    consumerTask.cancel()
                    return
                }
            }

            continuation.onTermination = { _ in
                consumerTask.cancel()
                watchdogTask.cancel()
            }
        }
    }
}

private actor InferenceStreamWatchdogState {
    private let startedAt = Date()
    private var lastProgressAt = Date()
    private var didReceiveEvent = false
    private var finished = false

    func mark(_ event: InferenceStreamEvent) {
        didReceiveEvent = true
        lastProgressAt = Date()
        if event.isTerminal {
            finished = true
        }
    }

    func finish() {
        finished = true
    }

    func timeout(configuration: InferenceStreamWatchdogConfiguration, now: Date = Date()) -> InferenceStreamWatchdogTimeout? {
        guard !finished else { return nil }
        if !didReceiveEvent {
            let elapsed = now.timeIntervalSince(startedAt)
            guard elapsed >= configuration.firstEventTimeoutSeconds else { return nil }
            finished = true
            return InferenceStreamWatchdogTimeout(stage: .firstEvent, elapsedSeconds: elapsed)
        }

        let elapsed = now.timeIntervalSince(lastProgressAt)
        guard elapsed >= configuration.progressTimeoutSeconds else { return nil }
        finished = true
        return InferenceStreamWatchdogTimeout(stage: .progress, elapsedSeconds: elapsed)
    }
}

private extension InferenceStreamEvent {
    var isTerminal: Bool {
        switch self {
        case .finish, .failure:
            true
        case .token, .toolCall, .metrics:
            false
        }
    }
}
