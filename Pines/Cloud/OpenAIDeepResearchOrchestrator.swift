import Foundation
import PinesCore

struct OpenAIDeepResearchRunSummary: Hashable, Sendable {
    var id: String
    var providerID: ProviderID
    var modelID: ModelID
    var title: String
    var status: OpenAIBackgroundResponseStatus
    var statusText: String
    var progressFraction: Double
    var activityText: String
    var finalReportArtifactID: String?
    var responseID: String?
    var lastError: String?
    var updatedAt: Date
}

struct OpenAIDeepResearchResumeResult: Sendable {
    var refreshedRuns: [ProviderResearchRunRecord]
    var failedRuns: [ProviderResearchRunRecord]
    var errors: [String: String]
}

struct OpenAIDeepResearchOrchestrator: Sendable {
    var coordinator: OpenAIProviderLifecycleCoordinator
    var pollInterval: Duration = .seconds(30)

    func start(_ request: OpenAIDeepResearchRequest) async throws -> ProviderResearchRunRecord {
        try await coordinator.createDeepResearchRun(request)
    }

    func retrieve(runID: String) async throws -> ProviderResearchRunRecord {
        let run = try await storedRun(id: runID)
        return try await coordinator.refreshDeepResearchRun(run)
    }

    func cancel(runID: String) async throws -> ProviderResearchRunRecord {
        let run = try await storedRun(id: runID)
        return try await coordinator.cancelDeepResearchRun(run)
    }

    func poll(
        _ run: ProviderResearchRunRecord,
        untilTerminal: Bool = false,
        timeout: Duration? = nil
    ) async throws -> ProviderResearchRunRecord {
        var current = run
        let deadline = timeout.map { Date().addingTimeInterval(TimeInterval($0.components.seconds)) }

        while true {
            current = try await coordinator.refreshDeepResearchRun(current)
            if !untilTerminal || current.openAIBackgroundStatus.isTerminal {
                return current
            }
            if let deadline, Date() >= deadline {
                return current
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    func resumeStoredRuns(
        statuses: [OpenAIBackgroundResponseStatus] = [.queued, .inProgress, .requiresAction],
        untilTerminal: Bool = false
    ) async throws -> OpenAIDeepResearchResumeResult {
        guard let repository = coordinator.repositories.researchRuns else {
            return OpenAIDeepResearchResumeResult(refreshedRuns: [], failedRuns: [], errors: [:])
        }

        let resumableStatuses = Set(statuses)
        let candidates = try await repository
            .listProviderResearchRuns(providerID: coordinator.providerID, status: nil)
            .filter { resumableStatuses.contains($0.openAIBackgroundStatus) }

        var refreshed = [ProviderResearchRunRecord]()
        var failed = [ProviderResearchRunRecord]()
        var errors = [String: String]()
        for run in candidates where !run.openAIBackgroundStatus.isTerminal {
            do {
                refreshed.append(try await poll(run, untilTerminal: untilTerminal))
            } catch {
                failed.append(run)
                errors[run.id] = error.localizedDescription
            }
        }
        return OpenAIDeepResearchResumeResult(refreshedRuns: refreshed, failedRuns: failed, errors: errors)
    }

    func summaries(providerID: ProviderID? = nil, status: OpenAIBackgroundResponseStatus? = nil) async throws -> [OpenAIDeepResearchRunSummary] {
        guard let repository = coordinator.repositories.researchRuns else { return [] }
        return try await repository
            .listProviderResearchRuns(providerID: providerID ?? coordinator.providerID, status: status?.rawValue)
            .map(\.openAIDeepResearchSummary)
    }

    private func storedRun(id: String) async throws -> ProviderResearchRunRecord {
        guard let repository = coordinator.repositories.researchRuns else {
            throw InferenceError.invalidRequest("OpenAI Deep Research runs cannot be loaded because no research run repository is configured.")
        }
        guard let run = try await repository
            .listProviderResearchRuns(providerID: coordinator.providerID, status: nil)
            .first(where: { $0.id == id })
        else {
            throw InferenceError.invalidRequest("OpenAI Deep Research run \(id) was not found.")
        }
        return run
    }
}

extension ProviderResearchRunRecord {
    var openAIBackgroundStatus: OpenAIBackgroundResponseStatus {
        OpenAIBackgroundResponseStatus(providerStatus: status)
    }

    var openAIDeepResearchSummary: OpenAIDeepResearchRunSummary {
        let resolvedStatus = openAIBackgroundStatus
        return OpenAIDeepResearchRunSummary(
            id: id,
            providerID: providerID,
            modelID: modelID,
            title: title,
            status: resolvedStatus,
            statusText: resolvedStatus.deepResearchStatusText,
            progressFraction: deepResearchProgressFraction(status: resolvedStatus),
            activityText: deepResearchActivityText,
            finalReportArtifactID: finalReportArtifactID,
            responseID: responseID,
            lastError: lastError,
            updatedAt: updatedAt
        )
    }

    private var deepResearchActivityText: String {
        var parts = ["\(citationCount) citations", "\(toolCallCount) tool calls"]
        if let finalReportArtifactID, !finalReportArtifactID.isEmpty {
            parts.append("report saved")
        }
        return parts.joined(separator: ", ")
    }

    private func deepResearchProgressFraction(status: OpenAIBackgroundResponseStatus) -> Double {
        switch status {
        case .queued:
            return 0.05
        case .inProgress:
            let activityProgress = Double(min(12, citationCount + toolCallCount)) * 0.05
            return min(0.85, 0.20 + activityProgress)
        case .requiresAction:
            return 0.50
        case .completed, .failed, .cancelled, .expired:
            return 1.0
        }
    }
}

private extension OpenAIBackgroundResponseStatus {
    var deepResearchStatusText: String {
        switch self {
        case .queued:
            return "Queued"
        case .inProgress:
            return "Researching"
        case .requiresAction:
            return "Needs action"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .expired:
            return "Expired"
        }
    }
}
