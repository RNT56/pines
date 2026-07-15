import Foundation
import PinesCore
import XCTest
@testable import pines

final class ArtifactLibraryIndexTests: XCTestCase {
    func testBuildIndexesProviderAndResearchMetadataInOneSourcePass() throws {
        let providers = [
            makeProvider(id: "provider-a", name: "Alpha Cloud", kind: .openAI),
            makeProvider(id: "provider-b", name: "Beta Cloud", kind: .gemini),
        ]
        let artifacts = [
            makeArtifact(id: "report", providerID: "provider-a", kind: "deep_research_report"),
            makeArtifact(id: "image", providerID: "provider-b", kind: "image"),
            makeArtifact(id: "hidden", providerID: "provider-a", kind: "tool_output"),
        ]
        let runs = [
            makeResearchRun(
                id: "research",
                providerID: "provider-a",
                title: "Indexed research title",
                artifactID: "report"
            ),
        ]

        let index = ArtifactLibraryIndex.build(
            artifacts: artifacts,
            providers: providers,
            researchRuns: runs
        )

        XCTAssertEqual(
            index.buildMetrics,
            .init(
                artifactRecordsVisited: 3,
                providerRecordsVisited: 2,
                researchRecordsVisited: 1,
                visibleArtifactRecords: 2
            )
        )
        XCTAssertEqual(index.itemsByID["report"]?.providerName, "Alpha Cloud")
        XCTAssertEqual(index.itemsByID["report"]?.title, "Indexed research title")
        XCTAssertEqual(index.itemsByID["image"]?.providerName, "Beta Cloud")
        XCTAssertNil(index.itemsByID["hidden"])
    }

    func testQueryProjectionsReusePrecomputedSearchTextAndPreserveActivitySemantics() {
        let provider = makeProvider(id: "provider", name: "Pine Needle Cloud", kind: .openAI)
        let ready = makeArtifact(
            id: "ready",
            providerID: provider.id,
            kind: "image",
            text: "A distant mountain",
            status: "completed"
        )
        let active = makeArtifact(
            id: "active",
            providerID: provider.id,
            kind: "video_job",
            text: "Ocean render",
            status: "processing"
        )
        let index = ArtifactLibraryIndex.build(
            artifacts: [ready, active],
            providers: [provider],
            researchRuns: []
        )

        let providerMatch = index.project(query: .init(text: "needle"))
        let contentMatch = index.project(query: .init(text: "mountain"))

        XCTAssertEqual(providerMatch.completedItems.map(\.id), ["ready"])
        XCTAssertEqual(providerMatch.activeItems.map(\.id), ["active"])
        XCTAssertEqual(contentMatch.completedItems.map(\.id), ["ready"])
        // Running work intentionally remains visible while a text query is active.
        XCTAssertEqual(contentMatch.activeItems.map(\.id), ["active"])
        XCTAssertEqual(index.buildMetrics.providerRecordsVisited, 1)
        XCTAssertEqual(index.buildMetrics.researchRecordsVisited, 0)
    }

    func testAllSortModesUseDeterministicTieBreakers() {
        let date = Date(timeIntervalSince1970: 1_000)
        let provider = makeProvider(id: "provider", name: "Same Provider", kind: .openAI)
        let artifacts = ["c", "a", "b"].map {
            makeArtifact(
                id: $0,
                providerID: provider.id,
                kind: "image",
                createdAt: date
            )
        }
        let index = ArtifactLibraryIndex.build(
            artifacts: artifacts,
            providers: [provider],
            researchRuns: []
        )

        for sort in ArtifactsSort.allCases {
            let projection = index.project(query: .init(sort: sort))
            XCTAssertEqual(projection.completedItems.map(\.id), ["a", "b", "c"], "Unstable \(sort) ordering")
        }
    }

    func testLargeIndexDerivationBenchmark() {
        let providers = (0 ..< 40).map {
            makeProvider(id: ProviderID(rawValue: "provider-\($0)"), name: "Provider \($0)", kind: .openAI)
        }
        let artifacts = (0 ..< 2_000).map { index in
            makeArtifact(
                id: "artifact-\(index)",
                providerID: providers[index % providers.count].id,
                kind: index.isMultiple(of: 4) ? "deep_research_report" : "image",
                text: "Searchable artifact payload \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        measure {
            let index = ArtifactLibraryIndex.build(
                artifacts: artifacts,
                providers: providers,
                researchRuns: []
            )
            XCTAssertEqual(index.items.count, artifacts.count)
        }
    }

    private func makeProvider(
        id: ProviderID,
        name: String,
        kind: CloudProviderKind
    ) -> CloudProviderConfiguration {
        CloudProviderConfiguration(
            id: id,
            kind: kind,
            displayName: name,
            baseURL: URL(string: "https://example.com")!,
            keychainAccount: id.rawValue
        )
    }

    private func makeArtifact(
        id: String,
        providerID: ProviderID,
        kind: String,
        text: String? = nil,
        status: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 100)
    ) -> ProviderArtifactRecord {
        var content = [String: JSONValue]()
        if let status {
            content["status"] = .string(status)
        }
        return ProviderArtifactRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            kind: kind,
            fileName: "\(id).dat",
            text: text,
            content: content.isEmpty ? nil : .object(content),
            createdAt: createdAt
        )
    }

    private func makeResearchRun(
        id: String,
        providerID: ProviderID,
        title: String,
        artifactID: String
    ) -> ProviderResearchRunRecord {
        ProviderResearchRunRecord(
            id: id,
            providerID: providerID,
            providerKind: .openAI,
            modelID: "research-model",
            title: title,
            prompt: "Research prompt",
            depth: "standard",
            sourcePolicy: .object([:]),
            reportFormat: "markdown",
            serviceTier: "default",
            status: "completed",
            finalReportArtifactID: artifactID
        )
    }
}
