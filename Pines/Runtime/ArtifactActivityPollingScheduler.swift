import Foundation
import PinesCore

struct ArtifactActivityPollOperation: Hashable, Identifiable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case openAIVideo
        case geminiMedia
        case openAIResearch
        case geminiResearch
    }

    let id: String
    let remoteID: String
    let providerID: ProviderID
    let kind: Kind

    init?(artifact: ProviderArtifactRecord) {
        guard artifact.artifactOperationState.isActive,
              let providerID = artifact.providerID
        else {
            return nil
        }

        let kind: Kind
        let remoteID: String
        switch (artifact.providerKind, artifact.kind.lowercased()) {
        case (.openAI, "video_job"):
            kind = .openAIVideo
            remoteID = artifact.providerFileID ?? artifact.id
        case (.gemini, "media_operation"):
            kind = .geminiMedia
            remoteID = artifact.responseID ?? artifact.id
        default:
            return nil
        }

        self.id = "\(kind.rawValue):\(providerID.rawValue):\(artifact.id)"
        self.remoteID = remoteID
        self.providerID = providerID
        self.kind = kind
    }

    init?(researchRun: ProviderResearchRunRecord) {
        guard !researchRun.status.providerIsTerminal else { return nil }

        let kind: Kind
        switch researchRun.providerKind {
        case .openAI:
            kind = .openAIResearch
        case .gemini:
            kind = .geminiResearch
        default:
            return nil
        }

        id = "\(kind.rawValue):\(researchRun.providerID.rawValue):\(researchRun.id)"
        remoteID = researchRun.id
        providerID = researchRun.providerID
        self.kind = kind
    }

    init(id: String, remoteID: String, providerID: ProviderID, kind: Kind) {
        self.id = id
        self.remoteID = remoteID
        self.providerID = providerID
        self.kind = kind
    }

    static func stableSignature(for operations: [Self]) -> [String] {
        Array(Set(operations.map { "\($0.id)|\($0.remoteID)" })).sorted()
    }
}

enum ArtifactActivityPollOutcome: Equatable, Sendable {
    case active
    case terminal
}

struct ArtifactActivityPollingConfiguration: Sendable {
    var cadenceByKind: [ArtifactActivityPollOperation.Kind: TimeInterval]
    var maximumBackoff: TimeInterval
    var jitterFraction: Double

    init(
        cadenceByKind: [ArtifactActivityPollOperation.Kind: TimeInterval] = [
            .openAIVideo: 6,
            .geminiMedia: 6,
            .openAIResearch: 6,
            .geminiResearch: 6,
        ],
        maximumBackoff: TimeInterval = 60,
        jitterFraction: Double = 0.1
    ) {
        self.cadenceByKind = cadenceByKind.mapValues { max(0, $0) }
        self.maximumBackoff = max(0, maximumBackoff)
        self.jitterFraction = min(max(0, jitterFraction), 1)
    }

    func cadence(for operation: ArtifactActivityPollOperation) -> TimeInterval {
        cadenceByKind[operation.kind] ?? 6
    }
}

struct ArtifactActivityPollingScheduler: Sendable {
    typealias Poll = @Sendable (ArtifactActivityPollOperation) async throws -> ArtifactActivityPollOutcome
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void
    typealias RandomUnit = @Sendable () -> Double

    private let configuration: ArtifactActivityPollingConfiguration
    private let sleeper: Sleeper
    private let randomUnit: RandomUnit

    init(
        configuration: ArtifactActivityPollingConfiguration = .init(),
        sleeper: @escaping Sleeper = { interval in
            try await Task.sleep(for: .seconds(interval))
        },
        randomUnit: @escaping RandomUnit = { Double.random(in: 0 ... 1) }
    ) {
        self.configuration = configuration
        self.sleeper = sleeper
        self.randomUnit = randomUnit
    }

    /// Runs one structured, cancellable loop for each distinct operation.
    /// A loop never starts its next request until the previous request has returned.
    func run(
        operations: [ArtifactActivityPollOperation],
        poll: @escaping Poll
    ) async {
        let uniqueOperations = Dictionary(
            operations.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        .values
        .sorted { $0.id < $1.id }

        await withTaskGroup(of: Void.self) { group in
            for operation in uniqueOperations {
                group.addTask {
                    await runLoop(for: operation, poll: poll)
                }
            }
            await group.waitForAll()
        }
    }

    private func runLoop(
        for operation: ArtifactActivityPollOperation,
        poll: @escaping Poll
    ) async {
        var nextDelay: TimeInterval?
        var consecutiveFailures = 0

        while !Task.isCancelled {
            if let nextDelay {
                do {
                    try await sleeper(jittered(nextDelay))
                    try Task.checkCancellation()
                } catch {
                    return
                }
            }

            do {
                let interval = PinesRuntimeMetrics.shared.begin(.providerPollCycle)
                let outcome: ArtifactActivityPollOutcome
                do {
                    outcome = try await poll(operation)
                    PinesRuntimeMetrics.shared.end(interval)
                } catch {
                    PinesRuntimeMetrics.shared.end(interval)
                    throw error
                }
                consecutiveFailures = 0
                guard outcome == .active else { return }
                nextDelay = configuration.cadence(for: operation)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                consecutiveFailures += 1
                nextDelay = backoffDelay(
                    cadence: configuration.cadence(for: operation),
                    consecutiveFailures: consecutiveFailures
                )
            }
        }
    }

    private func backoffDelay(
        cadence: TimeInterval,
        consecutiveFailures: Int
    ) -> TimeInterval {
        let exponent = min(max(0, consecutiveFailures - 1), 8)
        let delay = cadence * pow(2, Double(exponent))
        return min(configuration.maximumBackoff, delay)
    }

    private func jittered(_ interval: TimeInterval) -> TimeInterval {
        guard interval > 0, configuration.jitterFraction > 0 else { return max(0, interval) }
        let unit = min(max(0, randomUnit()), 1)
        let centeredUnit = (unit * 2) - 1
        let multiplier = 1 + (centeredUnit * configuration.jitterFraction)
        return max(0, interval * multiplier)
    }
}
