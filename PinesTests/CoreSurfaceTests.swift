import Foundation
import XCTest
import PinesCore

final class CoreSurfaceTests: XCTestCase {
    func testCloudContextApprovalRequestRoundTrips() throws {
        let request = CloudContextApprovalRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            providerID: ProviderID(rawValue: "openai"),
            modelID: ModelID(rawValue: "gpt-test"),
            documentIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000002")!],
            mcpResourceIDs: ["mcp://server/resource"],
            estimatedContextBytes: 4096,
            createdAt: Date(timeIntervalSinceReferenceDate: 42)
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CloudContextApprovalRequest.self, from: encoded)

        XCTAssertEqual(decoded, request)
    }

    func testVaultSearchOptionsNormalizeUnsafeValues() {
        let options = VaultSearchOptions(
            lexicalCandidateCount: 0,
            semanticBatchSize: 1,
            semanticRerankCount: 0,
            timeoutMilliseconds: 250
        )

        XCTAssertEqual(options.lexicalCandidateCount, 1)
        XCTAssertEqual(options.semanticBatchSize, 32)
        XCTAssertEqual(options.semanticRerankCount, 1)
        XCTAssertEqual(options.timeoutMilliseconds, 250)
    }

    func testAppOptsIntoHighRefreshRendering() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = repoRoot.appendingPathComponent("Pines/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        let info = try XCTUnwrap(plist as? [String: Any])

        XCTAssertEqual(info["CADisableMinimumFrameDurationOnPhone"] as? Bool, true)

        let rootView = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesRootView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(rootView.contains(".pinesHighRefreshRate()"))

        let refreshSupport = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/PinesRefreshRateSupport.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(refreshSupport.contains("UIUpdateLink"))
        XCTAssertTrue(refreshSupport.contains("preferredFrameRateRange"))
        XCTAssertFalse(refreshSupport.contains("requiresContinuousUpdates"))
    }

    func testArtifactsTabRoutesToExtractedWorkspace() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootView = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(rootView.contains("ArtifactsWorkspaceView()"))
        XCTAssertFalse(rootView.contains("private struct ProviderWorkspaceView"))
        XCTAssertFalse(rootView.contains("ProviderLifecycleDashboard"))
    }

    func testArtifactsWorkspaceDefinesFocusedModesAndConfirmations() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspace = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Artifacts/ArtifactsWorkspaceView.swift"),
            encoding: .utf8
        )
        let models = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Artifacts/ArtifactsModels.swift"),
            encoding: .utf8
        )

        for mode in ["Library", "Generate", "Research", "Storage", "Jobs"] {
            XCTAssertTrue(workspace.contains(mode), "Missing artifacts workspace mode \(mode)")
        }
        XCTAssertTrue(workspace.contains("ArtifactsMediaModelOption"))
        XCTAssertTrue(workspace.contains("ArtifactsResearchModelOption"))
        XCTAssertTrue(workspace.contains("ArtifactsWorkspaceModePicker"))
        XCTAssertTrue(workspace.contains("Research Console"))
        XCTAssertFalse(workspace.contains("LazyVGrid(columns: [GridItem(.adaptive(minimum: 148)"))
        XCTAssertTrue(workspace.contains("ArtifactsMenuPill"))
        XCTAssertTrue(workspace.contains("This removes only Pines' local lifecycle record"))
        XCTAssertTrue(models.contains("enum ArtifactsWorkspaceMode"))
        XCTAssertTrue(models.contains("static func counts"))
        XCTAssertTrue(models.contains("researchTimeline"))
        XCTAssertTrue(models.contains("researchSources"))
        XCTAssertTrue(models.contains("gpt-image-2"))
        XCTAssertTrue(models.contains("sora-2"))
        XCTAssertTrue(models.contains("gemini-3.1-flash-image-preview"))
        XCTAssertTrue(models.contains("veo-3.1-generate-preview"))
        XCTAssertTrue(models.contains("gemini-3.1-flash-tts-preview"))
        XCTAssertTrue(models.contains("Provider-hosted"))
        XCTAssertTrue(models.contains("Local copy"))
        XCTAssertTrue(models.contains("Vault-importable"))
    }
}
