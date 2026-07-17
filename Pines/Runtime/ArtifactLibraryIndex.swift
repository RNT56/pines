import Foundation
import PinesCore

/// A reusable, immutable projection of provider-backed artifact inputs.
///
/// Provider and research metadata are indexed once here rather than joined with
/// every artifact from SwiftUI's body. Query projections can then be rebuilt
/// independently without revisiting those source collections.
struct ArtifactLibraryIndex: Sendable {
    struct BuildMetrics: Equatable, Sendable {
        let artifactRecordsVisited: Int
        let providerRecordsVisited: Int
        let researchRecordsVisited: Int
        let visibleArtifactRecords: Int
    }

    static let empty = ArtifactLibraryIndex(
        items: [],
        itemsByID: [:],
        researchThreads: [],
        activityOperations: [],
        buildMetrics: .init(
            artifactRecordsVisited: 0,
            providerRecordsVisited: 0,
            researchRecordsVisited: 0,
            visibleArtifactRecords: 0
        )
    )

    let items: [ArtifactLibraryItem]
    let itemsByID: [String: ArtifactLibraryItem]
    let researchThreads: [ArtifactsResearchThread]
    let activityOperations: [ArtifactActivityPollOperation]
    let buildMetrics: BuildMetrics

    static func build(
        artifacts: [ProviderArtifactRecord],
        providers: [CloudProviderConfiguration],
        researchRuns: [ProviderResearchRunRecord]
    ) -> ArtifactLibraryIndex {
        var providerNamesByID = [ProviderID: String](minimumCapacity: providers.count)
        for provider in providers {
            providerNamesByID[provider.id] = provider.displayName
        }

        // Preserve the existing first-match behavior when multiple runs happen
        // to reference the same final report artifact.
        var researchTitlesByArtifactID = [String: String](minimumCapacity: researchRuns.count)
        for run in researchRuns {
            guard let artifactID = run.finalReportArtifactID,
                  researchTitlesByArtifactID[artifactID] == nil
            else {
                continue
            }
            researchTitlesByArtifactID[artifactID] = run.title
        }

        var items = [ArtifactLibraryItem]()
        items.reserveCapacity(artifacts.count)
        var itemsByID = [String: ArtifactLibraryItem](minimumCapacity: artifacts.count)

        for artifact in artifacts where artifact.isVisibleInArtifactsGallery {
            let providerName = artifact.providerID.flatMap { providerNamesByID[$0] }
                ?? artifact.providerKind.pinesLifecycleTitle
            let item = ArtifactLibraryItem(
                artifact: artifact,
                providerName: providerName,
                researchTitle: researchTitlesByArtifactID[artifact.id]
            )
            items.append(item)
            itemsByID[artifact.id] = item
        }

        let artifactOperations = items
            .sorted(by: ArtifactLibraryProjection.sorter(.newest))
            .compactMap { ArtifactActivityPollOperation(artifact: $0.artifact) }
            .prefix(6)
        let researchOperations = researchRuns
            .compactMap(ArtifactActivityPollOperation.init(researchRun:))
            .prefix(6)

        return ArtifactLibraryIndex(
            items: items,
            itemsByID: itemsByID,
            researchThreads: ArtifactsResearchThread.threads(from: researchRuns),
            activityOperations: Array(artifactOperations) + Array(researchOperations),
            buildMetrics: .init(
                artifactRecordsVisited: artifacts.count,
                providerRecordsVisited: providers.count,
                researchRecordsVisited: researchRuns.count,
                visibleArtifactRecords: items.count
            )
        )
    }

    func project(query: ArtifactsLibraryQuery) -> ArtifactLibraryProjection {
        let normalizedQuery = query.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scopedItems = items.filter {
            query.category.matches($0.artifact)
                && query.providerScope.includes($0.artifact.providerID)
        }
        let activeItems = scopedItems
            .filter(\.isActive)
            .sorted(by: ArtifactLibraryProjection.sorter(.newest))
        let matchingItems = scopedItems
            .filter { $0.matches(normalizedQuery: normalizedQuery) }
            .sorted(by: ArtifactLibraryProjection.sorter(query.sort))
        let activeResearchThreads: [ArtifactsResearchThread]
        if query.category == .all || query.category == .reports {
            activeResearchThreads = researchThreads
                .filter { $0.runs.contains(where: { !$0.status.providerIsTerminal }) }
                .filter { query.providerScope.includes($0.latestRun.providerID) }
        } else {
            activeResearchThreads = []
        }

        return ArtifactLibraryProjection(
            matchingItemCount: matchingItems.count,
            completedItems: matchingItems.filter { !$0.isActive },
            activeItems: activeItems,
            activeResearchThreads: activeResearchThreads
        )
    }
}

struct ArtifactLibraryProjection: Sendable {
    static let empty = ArtifactLibraryProjection(
        matchingItemCount: 0,
        completedItems: [],
        activeItems: [],
        activeResearchThreads: []
    )

    let matchingItemCount: Int
    let completedItems: [ArtifactLibraryItem]
    let activeItems: [ArtifactLibraryItem]
    let activeResearchThreads: [ArtifactsResearchThread]

    static func sorter(_ sort: ArtifactsSort) -> (ArtifactLibraryItem, ArtifactLibraryItem) -> Bool {
        { lhs, rhs in
            switch sort {
            case .newest:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            case .oldest:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            case .provider:
                let comparison = lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            case .kind:
                let comparison = lhs.contentKind.title.localizedCaseInsensitiveCompare(rhs.contentKind.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            }
            return lhs.id < rhs.id
        }
    }
}

actor ArtifactLibraryDerivationEngine {
    static let shared = ArtifactLibraryDerivationEngine()

    func buildIndex(
        artifacts: [ProviderArtifactRecord],
        providers: [CloudProviderConfiguration],
        researchRuns: [ProviderResearchRunRecord]
    ) -> ArtifactLibraryIndex {
        ArtifactLibraryIndex.build(
            artifacts: artifacts,
            providers: providers,
            researchRuns: researchRuns
        )
    }

    func project(
        index: ArtifactLibraryIndex,
        query: ArtifactsLibraryQuery
    ) -> ArtifactLibraryProjection {
        index.project(query: query)
    }
}
