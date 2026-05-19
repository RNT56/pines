import Foundation
import PinesCore

@MainActor
extension PinesAppModel {
    func startOpenAIDeepResearch(
        _ request: OpenAIDeepResearchRequest,
        services: PinesAppServices,
        pollUntilTerminal: Bool = false
    ) async throws -> ProviderResearchRunRecord {
        let orchestrator = try await openAIDeepResearchOrchestrator(providerID: request.providerID, services: services)
        let run = try await orchestrator.start(request)
        applyOpenAIDeepResearchRun(run)
        if pollUntilTerminal {
            let completed = try await orchestrator.poll(run, untilTerminal: true)
            applyOpenAIDeepResearchRun(completed)
            await refreshProviderLifecycleState(services: services)
            return completed
        }
        return run
    }

    func refreshOpenAIDeepResearchRun(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderResearchRunRecord {
        let orchestrator = try await openAIDeepResearchOrchestrator(providerID: providerID, services: services)
        let run = try await orchestrator.retrieve(runID: id)
        applyOpenAIDeepResearchRun(run)
        if run.openAIBackgroundStatus.isTerminal {
            await refreshProviderLifecycleState(services: services)
        }
        return run
    }

    func cancelOpenAIDeepResearchRun(
        id: String,
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> ProviderResearchRunRecord {
        let orchestrator = try await openAIDeepResearchOrchestrator(providerID: providerID, services: services)
        let run = try await orchestrator.cancel(runID: id)
        applyOpenAIDeepResearchRun(run)
        return run
    }

    func resumeOpenAIDeepResearchRuns(
        providerID: ProviderID,
        services: PinesAppServices,
        pollUntilTerminal: Bool = false
    ) async throws -> OpenAIDeepResearchResumeResult {
        let orchestrator = try await openAIDeepResearchOrchestrator(providerID: providerID, services: services)
        let result = try await orchestrator.resumeStoredRuns(untilTerminal: pollUntilTerminal)
        for run in result.refreshedRuns {
            applyOpenAIDeepResearchRun(run)
        }
        if pollUntilTerminal || result.refreshedRuns.contains(where: { $0.openAIBackgroundStatus.isTerminal }) {
            await refreshProviderLifecycleState(services: services)
        }
        return result
    }

    func openAIDeepResearchSummaries(
        providerID: ProviderID,
        services: PinesAppServices,
        status: OpenAIBackgroundResponseStatus? = nil
    ) async throws -> [OpenAIDeepResearchRunSummary] {
        let orchestrator = try await openAIDeepResearchOrchestrator(providerID: providerID, services: services)
        return try await orchestrator.summaries(providerID: providerID, status: status)
    }

    private func openAIDeepResearchOrchestrator(
        providerID: ProviderID,
        services: PinesAppServices
    ) async throws -> OpenAIDeepResearchOrchestrator {
        guard let provider = try await openAIProvider(id: providerID, services: services) else {
            throw InferenceError.invalidRequest("OpenAI provider \(providerID.rawValue) was not found.")
        }
        guard let cloudProviderService = services.cloudProviderService else {
            throw InferenceError.invalidRequest("Cloud provider service is unavailable.")
        }
        let coordinator = cloudProviderService.openAILifecycleCoordinator(
            for: provider,
            repositories: services.openAIProviderLifecycleRepositories
        )
        return OpenAIDeepResearchOrchestrator(coordinator: coordinator)
    }

    private func openAIProvider(id providerID: ProviderID, services: PinesAppServices) async throws -> CloudProviderConfiguration? {
        if let provider = cloudProviders.first(where: { $0.id == providerID && $0.kind == .openAI }) {
            return provider
        }
        guard let repository = services.cloudProviderRepository else { return nil }
        return try await repository.listProviders().first { provider in
            provider.id == providerID && provider.kind == .openAI
        }
    }

    private func applyOpenAIDeepResearchRun(_ run: ProviderResearchRunRecord) {
        var runs = providerResearchRuns
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.append(run)
        }
        runs.sort { $0.updatedAt > $1.updatedAt }
        providerResearchRuns = runs
        providerResearchRunPreviews = runs.map(Self.deepResearchPreview)
        providerLifecycleError = nil
    }

    private static func deepResearchPreview(from record: ProviderResearchRunRecord) -> PinesProviderResearchRunPreview {
        let summary = record.openAIDeepResearchSummary
        let detailParts = [
            record.depth,
            record.reportFormat,
            summary.finalReportArtifactID == nil ? nil : "report saved",
        ].compactMap { $0 }
        return PinesProviderResearchRunPreview(
            id: record.id,
            providerID: record.providerID,
            providerKind: record.providerKind,
            title: record.title,
            modelID: record.modelID,
            status: summary.statusText,
            detail: detailParts.joined(separator: " - "),
            activitySummary: summary.activityText,
            updatedLabel: RelativeDateTimeFormatter.shortLabel(for: record.updatedAt)
        )
    }
}
