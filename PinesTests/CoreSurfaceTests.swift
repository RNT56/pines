import Foundation
import SwiftUI
import XCTest
import PinesCore
@testable import pines

final class CoreSurfaceTests: XCTestCase {
    func testAgentRunnerBlocksRegisteredToolThatWasNotAdvertised() async throws {
        let registry = ToolRegistry()
        let invocationCounter = AgentToolInvocationCounter()
        let advertised = try AnyToolSpec(
            name: "advertised_tool",
            description: "The only tool offered to the model.",
            inputJSONSchema: .objectSchema(),
            explanationRequired: false
        )
        let secret = try AnyToolSpec(
            name: "secret_tool",
            description: "A registered tool that is deliberately not offered.",
            inputJSONSchema: .objectSchema(),
            explanationRequired: false
        )
        try await registry.registerRaw(advertised) { _ in #"{"ok":true}"# }
        try await registry.registerRaw(secret) { _ in
            await invocationCounter.increment()
            return #"{"executed":true}"#
        }

        let provider = UnadvertisedToolCallProvider()
        let runner = AgentRunner(
            toolRegistry: registry,
            policyGate: ToolPolicyGate(),
            auditRepository: nil
        )
        let request = ChatRequest(
            modelID: "test-model",
            messages: [ChatMessage(role: .user, content: "Help")],
            sampling: ChatSampling(maxTokens: 256),
            allowsTools: true,
            availableTools: [advertised],
            executionContext: .agent,
            contextWindowTokens: 4_096
        )
        let session = AgentSession(
            title: "Authorization regression",
            policy: AgentPolicy(
                maxSteps: 2,
                maxToolCalls: 2,
                requiresConsentForNetwork: false,
                requiresConsentForBrowser: false
            )
        )

        var text = ""
        var finish: InferenceFinish?
        for try await event in runner.run(session: session, request: request, provider: provider) {
            switch event {
            case let .token(delta):
                text += delta.text
            case let .finish(value):
                finish = value
            case .toolCall, .metrics, .failure:
                break
            }
        }

        let invocationCount = await invocationCounter.value()
        let providerRequestCount = await provider.requestCount()
        XCTAssertEqual(invocationCount, 0)
        XCTAssertEqual(text, "Safe final response")
        XCTAssertEqual(finish?.reason, .stop)
        XCTAssertEqual(providerRequestCount, 2)
    }

    func testAgentRunnerCompletesPersistedParallelToolExchangeBeforeFallback() async throws {
        let registry = ToolRegistry()
        let localTool = try AnyToolSpec(
            name: "local_tool",
            description: "Returns local evidence.",
            inputJSONSchema: .objectSchema(),
            explanationRequired: false
        )
        let approvalTool = try AnyToolSpec(
            name: "approval_tool",
            description: "Requires approval.",
            inputJSONSchema: .objectSchema(),
            permissions: [.network],
            networkPolicy: .userApproved,
            explanationRequired: false
        )
        try await registry.registerRaw(localTool) { _ in #"{"fact":"kept"}"# }
        try await registry.registerRaw(approvalTool) { _ in #"{"unexpected":true}"# }
        let recorder = AgentTranscriptRecorder()
        let runner = AgentRunner(
            toolRegistry: registry,
            policyGate: ToolPolicyGate(),
            auditRepository: nil,
            approvalHandler: { _ in .denied },
            transcriptHandler: { message in await recorder.append(message) }
        )
        let request = ChatRequest(
            modelID: "test-model",
            messages: [ChatMessage(role: .user, content: "Gather both facts")],
            sampling: ChatSampling(maxTokens: 256),
            allowsTools: true,
            availableTools: [localTool, approvalTool],
            executionContext: .agent,
            contextWindowTokens: 4_096
        )
        let session = AgentSession(
            title: "Parallel persistence regression",
            policy: AgentPolicy(
                maxSteps: 2,
                maxToolCalls: 2,
                requiresConsentForNetwork: false,
                requiresConsentForBrowser: false
            )
        )

        for try await _ in runner.run(session: session, request: request, provider: TwoToolCallProvider()) {}

        let transcript = await recorder.messages()
        let assistant = try XCTUnwrap(transcript.first(where: { $0.role == .assistant }))
        let results = transcript.filter { $0.role == .tool }
        XCTAssertEqual(assistant.toolCalls.map(\.id), ["call-local", "call-approval"])
        XCTAssertEqual(Set(results.compactMap(\.toolCallID)), ["call-local", "call-approval"])
        XCTAssertTrue(results.first(where: { $0.toolCallID == "call-approval" })?.content.contains("stopped before this call completed") == true)
    }

    func testLocalContextAdapterPreservesToolCallAndUntrustedResultSemantics() {
        let call = ToolCallDelta(
            id: "call-1",
            name: "lookup",
            argumentsFragment: #"{"query":"pines"}"#,
            isComplete: true
        )
        let assistant = ChatMessage(role: .assistant, content: "", toolCalls: [call])
        let tool = ChatMessage(
            role: .tool,
            content: #"{"answer":"facts"}"#,
            toolCallID: call.id,
            toolName: call.name
        )

        let assistantContext = MLXRuntimeBridge.localContextContent(for: assistant)
        let toolContext = MLXRuntimeBridge.localContextContent(for: tool)
        XCTAssertTrue(assistantContext.hasPrefix("tool_calls="))
        XCTAssertTrue(assistantContext.contains("lookup"))
        XCTAssertTrue(assistantContext.contains("call-1"))
        XCTAssertTrue(toolContext.hasPrefix("untrusted_tool_result[call-1,lookup]="))
        XCTAssertTrue(toolContext.contains("facts"))
    }

    @MainActor
    func testMCPAttachmentRejectsEncodedOversizeAndRemovesTemporaryFile() throws {
        let maximumDecodedBytes = 10 * 1_024 * 1_024
        let maximumEncodedBytes = ((maximumDecodedBytes + 2) / 3) * 4 + 8
        let oversized = String(repeating: "A", count: maximumEncodedBytes + 1)
        XCTAssertThrowsError(
            try PinesAppModel.mcpAttachment(
                fromBase64: oversized,
                mimeType: "image/png",
                fileNameHint: "oversized.png"
            )
        )

        let attachment = try PinesAppModel.mcpAttachment(
            fromBase64: Data("safe".utf8).base64EncodedString(),
            mimeType: "image/png",
            fileNameHint: "safe.png"
        )
        let localURL = try XCTUnwrap(attachment.localURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path))

        PinesAppModel.removeTemporaryMCPAttachments([attachment])
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
    }

    @MainActor
    func testMCPNestedToolResultPreservesAndCleansAttachment() throws {
        let encoded = Data("nested-image".utf8).base64EncodedString()
        let converted = try PinesAppModel.textAndAttachments(
            from: [
                .toolResult(
                    toolUseID: "call-1",
                    content: [.image(data: encoded, mimeType: "image/png")]
                ),
            ]
        )
        let attachment = try XCTUnwrap(converted.attachments.first)
        let localURL = try XCTUnwrap(attachment.localURL)
        XCTAssertEqual(converted.attachments.count, 1)
        XCTAssertTrue(converted.text.contains("Tool result call-1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path))

        PinesAppModel.removeTemporaryMCPAttachments(converted.attachments)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localURL.path))
    }

    @MainActor
    func testMCPSamplingRejectsAggregateAttachmentCountBeforeMaterialization() throws {
        let encoded = Data("tiny-image".utf8).base64EncodedString()
        let request = MCPSamplingRequest(
            id: "aggregate-attachment-limit",
            serverID: "test-server",
            messages: [
                MCPPromptMessage(
                    role: .user,
                    content: (0 ..< 9).map { _ in
                        .image(data: encoded, mimeType: "image/png")
                    }
                ),
            ]
        )

        XCTAssertThrowsError(try PinesAppModel.validateMCPSamplingPayload(request)) { error in
            XCTAssertTrue(error.localizedDescription.contains("aggregate size or count limit"))
        }
    }

    @MainActor
    func testMCPSamplingRejectsExcessiveContentNesting() throws {
        var nested: [MCPMessageContent] = [.text("leaf")]
        for index in 0 ..< 18 {
            nested = [.toolResult(toolUseID: "call-\(index)", content: nested)]
        }
        let request = MCPSamplingRequest(
            id: "nested-content-limit",
            serverID: "test-server",
            messages: [MCPPromptMessage(role: .user, content: nested)]
        )

        XCTAssertThrowsError(try PinesAppModel.validateMCPSamplingPayload(request)) { error in
            XCTAssertTrue(error.localizedDescription.contains("nesting depth"))
        }
    }

    @MainActor
    func testMCPMaterializationCleansFilesWhenAggregateCountIsExceeded() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        func mcpTemporaryFiles() throws -> Set<String> {
            Set(
                try FileManager.default.contentsOfDirectory(
                    at: temporaryDirectory,
                    includingPropertiesForKeys: nil
                )
                .map(\.lastPathComponent)
                .filter { $0.hasPrefix("mcp-") }
            )
        }

        let filesBefore = try mcpTemporaryFiles()
        let encoded = Data("tiny-image".utf8).base64EncodedString()
        let contents: [MCPMessageContent] = (0 ..< 9).map { _ in
            .image(data: encoded, mimeType: "image/png")
        }

        XCTAssertThrowsError(try PinesAppModel.textAndAttachments(from: contents))
        XCTAssertEqual(try mcpTemporaryFiles(), filesBefore)
    }

    func testInferenceWatchdogGuardsStalledFirstEventStream() async throws {
        let source = AsyncThrowingStream<InferenceStreamEvent, Error> { continuation in
            let task = Task {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    continuation.yield(.token(TokenDelta(text: "late", tokenCount: 1)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: InferenceError.cancelled)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        let guarded = InferenceStreamWatchdog.guarded(
            source,
            configuration: InferenceStreamWatchdogConfiguration(
                firstEventTimeoutSeconds: 0.1,
                progressTimeoutSeconds: 1,
                pollIntervalSeconds: 0.05
            )
        )
        var events = [InferenceStreamEvent]()
        for try await event in guarded {
            events.append(event)
        }

        guard case let .finish(finish)? = events.last else {
            XCTFail("Expected watchdog finish event.")
            return
        }
        XCTAssertEqual(finish.reason, .error)
        XCTAssertEqual(
            finish.providerMetadata[LocalProviderMetadataKeys.generationWatchdogStage],
            InferenceStreamWatchdogTimeoutStage.firstEvent.rawValue
        )
    }

    func testInferenceWatchdogGuardsStalledProgressStream() async throws {
        let source = AsyncThrowingStream<InferenceStreamEvent, Error> { continuation in
            continuation.yield(.token(TokenDelta(text: "hello", tokenCount: 1)))
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        let guarded = InferenceStreamWatchdog.guarded(
            source,
            configuration: InferenceStreamWatchdogConfiguration(
                firstEventTimeoutSeconds: 1,
                progressTimeoutSeconds: 0.1,
                pollIntervalSeconds: 0.05
            )
        )
        var events = [InferenceStreamEvent]()
        for try await event in guarded {
            events.append(event)
        }

        XCTAssertTrue(events.contains(.token(TokenDelta(text: "hello", tokenCount: 1))))
        guard case let .finish(finish)? = events.last else {
            XCTFail("Expected watchdog finish event.")
            return
        }
        XCTAssertEqual(finish.reason, .error)
        XCTAssertEqual(
            finish.providerMetadata[LocalProviderMetadataKeys.generationWatchdogStage],
            InferenceStreamWatchdogTimeoutStage.progress.rawValue
        )
    }

    func testInferenceWatchdogFinishesStalledFirstEventStream() async throws {
        let configuration = InferenceStreamWatchdogConfiguration(
            firstEventTimeoutSeconds: 0.15,
            progressTimeoutSeconds: 0.15,
            pollIntervalSeconds: 0.05,
            code: "unit_test_watchdog",
            firstEventMessage: "Unit test first event timeout.",
            progressMessage: "Unit test progress timeout."
        )
        let finish = configuration.finish(
            for: InferenceStreamWatchdogTimeout(stage: .firstEvent, elapsedSeconds: 0.15)
        )

        XCTAssertEqual(finish.reason, .error)
        XCTAssertEqual(finish.message, "Unit test first event timeout.")
        XCTAssertEqual(finish.providerMetadata[LocalProviderMetadataKeys.generationWatchdogCode], "unit_test_watchdog")
        XCTAssertEqual(finish.providerMetadata[LocalProviderMetadataKeys.generationWatchdogStage], InferenceStreamWatchdogTimeoutStage.firstEvent.rawValue)
    }

    func testInferenceWatchdogFinishesStalledProgressStream() async throws {
        let configuration = InferenceStreamWatchdogConfiguration(
            firstEventTimeoutSeconds: 0.5,
            progressTimeoutSeconds: 0.15,
            pollIntervalSeconds: 0.05,
            code: "unit_test_watchdog",
            firstEventMessage: "Unit test first event timeout.",
            progressMessage: "Unit test progress timeout."
        )
        let finish = configuration.finish(
            for: InferenceStreamWatchdogTimeout(stage: .progress, elapsedSeconds: 0.15)
        )

        XCTAssertEqual(finish.reason, .error)
        XCTAssertEqual(finish.message, "Unit test progress timeout.")
        XCTAssertEqual(finish.providerMetadata[LocalProviderMetadataKeys.generationWatchdogStage], InferenceStreamWatchdogTimeoutStage.progress.rawValue)
    }

    func testInterruptedChatRunRepairFailsStreamingAssistantAndStripsInternalStatus() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000A111")!
        let message = ChatMessage(
            id: id,
            role: .assistant,
            content: "",
            providerMetadata: [
                ChatTranscriptMetadataKeys.persistedMessageStatus: MessageStatus.streaming.rawValue,
                "visible": "kept",
            ]
        )

        let repair = try XCTUnwrap(InterruptedChatRunRepair.repair(for: message, reason: "unit_test"))

        XCTAssertEqual(repair.messageID, id)
        XCTAssertEqual(repair.status, .failed)
        XCTAssertEqual(repair.content, InterruptedChatRunRepair.defaultInterruptedAssistantMessage)
        XCTAssertEqual(repair.providerMetadata["visible"], "kept")
        XCTAssertNil(repair.providerMetadata[ChatTranscriptMetadataKeys.persistedMessageStatus])
        XCTAssertEqual(repair.providerMetadata[ChatTranscriptMetadataKeys.interruptedRunRepairReason], "unit_test")
        XCTAssertEqual(repair.providerMetadata[ChatTranscriptMetadataKeys.interruptedRunOriginalStatus], MessageStatus.streaming.rawValue)
    }

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
        XCTAssertTrue(refreshSupport.contains("highMotionMinimumFramesPerSecond = 80"))
        XCTAssertFalse(refreshSupport.contains("requiresContinuousUpdates"))
    }

    func testHighRefreshPolicyRequestsHighMotionCadence() {
        let range = PinesRefreshRatePolicy.preferredFrameRateRange(maximumFramesPerSecond: 120)

        XCTAssertEqual(range.minimum, 80)
        XCTAssertEqual(range.maximum, 120)
        XCTAssertEqual(range.preferred, 120)
    }

    func testContinuousHapticsDoNotReprepareEveryFeedbackPulse() {
        XCTAssertFalse(PinesHapticEvent.scrollUp.preparesFollowingPlayback)
        XCTAssertFalse(PinesHapticEvent.scrollDown.preparesFollowingPlayback)
        XCTAssertFalse(PinesHapticEvent.streamPulse.preparesFollowingPlayback)
        XCTAssertTrue(PinesHapticEvent.primaryAction.preparesFollowingPlayback)
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
        XCTAssertTrue(rootView.contains("pinesFixedTabBarStyle"))
        XCTAssertTrue(rootView.contains("tabViewStyle(.tabBarOnly)"))
        XCTAssertFalse(rootView.contains("tabViewStyle(.sidebarAdaptable)"))
        XCTAssertFalse(rootView.contains("private struct ProviderWorkspaceView"))
        XCTAssertFalse(rootView.contains("ProviderLifecycleDashboard"))
    }

    func testArtifactsLibraryCreateAndDetailUseDedicatedSurfaces() throws {
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

        XCTAssertTrue(models.contains("enum ArtifactsAssetKindFilter"))
        XCTAssertTrue(models.contains("struct ArtifactsLibraryQuery"))
        XCTAssertTrue(models.contains("struct ArtifactLibraryItem"))
        XCTAssertTrue(models.contains("isVisibleInArtifactsGallery"))
        XCTAssertTrue(workspace.contains("ArtifactsLibraryView"))
        XCTAssertTrue(workspace.contains("ArtifactLibraryRow"))
        XCTAssertTrue(workspace.contains("ArtifactGalleryTile"))
        XCTAssertTrue(workspace.contains("private var activityStrip"))
        XCTAssertTrue(workspace.contains("private var newArtifactMenu"))
        XCTAssertTrue(workspace.contains("private var filterMenu"))
        XCTAssertTrue(workspace.contains(".searchable(text: $query.text"))
        XCTAssertTrue(workspace.contains("ArtifactQuickLookView"))
        XCTAssertTrue(workspace.contains("ArtifactCreateView"))
        XCTAssertTrue(workspace.contains("private var imageStudio"))
        XCTAssertTrue(workspace.contains("private var imagePromptDock"))
        XCTAssertTrue(workspace.contains("pines.artifacts.create.prompt"))
        XCTAssertTrue(workspace.contains("private var researchComposer"))
        XCTAssertTrue(workspace.contains("pines.artifacts.research.prompt"))
        XCTAssertTrue(workspace.contains("pines.artifacts.research.send"))
        XCTAssertTrue(workspace.contains("safeAreaInset(edge: .bottom"))
        XCTAssertTrue(workspace.contains("This session"))
        XCTAssertTrue(workspace.contains("New \\(mediaKind.title)"))
        XCTAssertTrue(workspace.contains("Generate \\(mediaKind.title.lowercased())"))
        XCTAssertFalse(workspace.contains("ArtifactCommandDeck"))
        XCTAssertFalse(workspace.contains("private var commandStrip"))
        XCTAssertFalse(workspace.contains(".inspector("))
        XCTAssertFalse(workspace.contains("ArtifactsLibraryFilterSheet"))
        XCTAssertFalse(workspace.contains("ArtifactCategoryChip"))
        XCTAssertFalse(workspace.contains("ArtifactMediaTile"))
        XCTAssertFalse(workspace.contains("Create (mediaKind.title)"))
        XCTAssertFalse(workspace.contains("Generate (mediaKind.title.lowercased())"))
        XCTAssertFalse(workspace.contains("PinesCardSection(\"Generate Media\""))
        XCTAssertFalse(workspace.contains("PinesCardSection(\"Gallery\""))
        XCTAssertFalse(workspace.contains(".background(.ultraThinMaterial)"))
    }

    func testArtifactSurfacesUsePinesThemePrimitivesEndToEnd() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspace = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Artifacts/ArtifactsWorkspaceView.swift"),
            encoding: .utf8
        )
        let sharedPanels = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Artifacts/ArtifactsRowsAndPanels.swift"),
            encoding: .utf8
        )
        let artifactSources = workspace + sharedPanels

        XCTAssertTrue(workspace.contains(".pinesNavigationChrome()"))
        XCTAssertTrue(workspace.contains(".pinesAppBackground()"))
        XCTAssertTrue(workspace.contains(".pinesSurface(.chrome"))
        XCTAssertTrue(workspace.contains("PinesDivider()"))
        XCTAssertTrue(artifactSources.contains(".pinesProgressTint()"))
        XCTAssertTrue(artifactSources.contains(".pinesBareButtonStyle()"))
        XCTAssertTrue(workspace.contains("private var mediaCreationSettings"))
        XCTAssertTrue(workspace.contains("Shape the voice"))
        XCTAssertTrue(workspace.contains("Configure the render"))
        XCTAssertFalse(artifactSources.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(artifactSources.contains(".font(.system"))
        XCTAssertFalse(artifactSources.contains("lineWidth: 0.5"))
        XCTAssertFalse(artifactSources.contains(".foregroundStyle(.red"))
        XCTAssertFalse(artifactSources.contains(".foregroundStyle(.blue"))
        XCTAssertFalse(artifactSources.contains(".foregroundStyle(.green"))
    }

    func testEveryPinesThemeResolvesForArtifactLightAndDarkAppearances() {
        for template in PinesThemeTemplate.allCases {
            for mode in [PinesInterfaceMode.light, .dark] {
                let theme = PinesTheme.resolve(template: template, mode: mode, systemScheme: .light)

                XCTAssertEqual(theme.template, template)
                XCTAssertEqual(theme.mode, mode)
                XCTAssertEqual(theme.colorScheme, mode == .dark ? .dark : .light)
                XCTAssertGreaterThan(theme.spacing.contentMaxWidth, 0)
                XCTAssertGreaterThan(theme.radius.control, 0)
                XCTAssertGreaterThan(theme.radius.panel, 0)
                XCTAssertGreaterThan(theme.radius.sheet, 0)
                XCTAssertGreaterThan(theme.stroke.hairline, 0)
                XCTAssertGreaterThan(theme.dashboard.actionMinHeight, 0)
            }
        }
    }

    func testArtifactLibraryProjectionUsesPromptAndLifecycleState() {
        let artifact = ProviderArtifactRecord(
            id: "artifact-1",
            providerKind: .openAI,
            kind: "video_job",
            fileName: "video_01.mp4",
            contentType: "video/mp4",
            content: .object([
                "pines_prompt": .string("A quiet cabin beneath tall pines"),
                "status": .string("processing"),
            ])
        )

        let item = ArtifactLibraryItem(
            artifact: artifact,
            providers: [],
            researchRuns: []
        )

        XCTAssertEqual(item.title, "A quiet cabin beneath tall pines")
        XCTAssertEqual(item.contentKind, .video)
        XCTAssertEqual(item.operationState, .processing)
        XCTAssertEqual(item.availability, .embedded)
        XCTAssertTrue(item.isActive)
    }

    func testArtifactLibraryHidesInternalLifecycleRecords() {
        let internalRecord = ProviderArtifactRecord(
            id: "tool-output",
            providerKind: .openAI,
            kind: "tool_output",
            content: .object(["status": .string("completed")])
        )
        let report = ProviderArtifactRecord(
            id: "report",
            providerKind: .gemini,
            kind: "deep_research_report",
            text: "# Findings"
        )

        XCTAssertFalse(internalRecord.isVisibleInArtifactsGallery)
        XCTAssertTrue(report.isVisibleInArtifactsGallery)
        XCTAssertEqual(report.artifactContentKind, .report)
        XCTAssertEqual(report.artifactOperationState, .ready)
    }

    func testArtifactsRemixWiringUsesProviderEditAndReferenceImagePayloads() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appArtifacts = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModel+Artifacts.swift"),
            encoding: .utf8
        )
        let openAILifecycle = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Cloud/OpenAIProviderLifecycleCoordinator.swift"),
            encoding: .utf8
        )
        let geminiLifecycle = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModel+GeminiLifecycle.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appArtifacts.contains("func remixOpenAIImageArtifact"))
        XCTAssertTrue(openAILifecycle.contains("func createImageEditArtifacts"))
        XCTAssertTrue(openAILifecycle.contains("createImageEdit("))
        XCTAssertTrue(openAILifecycle.contains("pines_remix"))
        XCTAssertTrue(geminiLifecycle.contains("func remixGeminiImageArtifact"))
        XCTAssertTrue(geminiLifecycle.contains("geminiImageReferencePart"))
        XCTAssertTrue(geminiLifecycle.contains("referenceParts"))
        XCTAssertTrue(geminiLifecycle.contains("method: .generateContent"))
        XCTAssertTrue(geminiLifecycle.contains("func refreshGeminiGeneratedMediaOperation"))
        XCTAssertTrue(geminiLifecycle.contains("func cancelGeminiGeneratedMediaOperation"))
    }

    func testMemoryWarningDoesNotDirectlyCancelActiveChatRun() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootView = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesRootView.swift"),
            encoding: .utf8
        )

        guard let warningRange = rootView.range(of: ".onPinesMemoryWarning") else {
            XCTFail("Missing memory warning handler.")
            return
        }
        let warningHandler = rootView[warningRange.lowerBound...]
            .prefix(while: { $0 != "}" })

        XCTAssertTrue(warningHandler.contains("services.handleMemoryPressure()"))
        XCTAssertFalse(warningHandler.contains("stopCurrentRun()"))

        guard let thermalRange = rootView.range(of: "ProcessInfo.thermalStateDidChangeNotification") else {
            XCTFail("Missing thermal pressure handler.")
            return
        }
        let thermalHandler = rootView[thermalRange.lowerBound...]
            .prefix(600)

        XCTAssertTrue(thermalHandler.contains("services.handleThermalPressure()"))
        XCTAssertFalse(thermalHandler.contains("stopCurrentRun()"))
    }

    func testInstalledModelResolutionRepairsStaleContainerPaths() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let lifecycle = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/ModelLifecycleService.swift"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/MLXRuntimeBridge.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(lifecycle.contains("static func installedModelDirectory(for install: ModelInstall) throws -> URL?"))
        XCTAssertTrue(lifecycle.contains("currentDirectory"))
        XCTAssertTrue(lifecycle.contains("legacyDirectory"))
        XCTAssertTrue(lifecycle.contains("repaired.localURL = resolvedURL"))
        XCTAssertTrue(lifecycle.contains("refreshLocalMetadata"))
        XCTAssertTrue(lifecycle.contains("localPreflightInput"))
        XCTAssertTrue(lifecycle.contains("classifier.classify(input)"))
        XCTAssertTrue(runtime.contains("ModelLifecycleService.installedModelDirectory(for: install)"))
    }

    func testFailedLocalModelReplacementRestoresPreviousRuntime() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtime = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/MLXRuntimeBridge.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(runtime.contains("LocalModelReplacementTransaction.perform"))
        XCTAssertTrue(runtime.contains("cleanupFailedReplacement:"))
        XCTAssertTrue(runtime.contains("restoreCurrent:"))
        XCTAssertNotNil(
            runtime.range(
                of: #"commitLoadedGenerationModel\(\s*restoredModel"#,
                options: .regularExpression
            )
        )
        XCTAssertTrue(runtime.contains("let restoredModelID = await state.loadedModelID()"))
        XCTAssertTrue(runtime.contains("await supervisor.markReady(modelID: restoredModelID)"))
    }

    func testTurboQuantProfileLookupCarriesModelMetadataAndUsesConservativeFallback() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtime = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/MLXRuntimeBridge.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(runtime.contains("modelType: install.modelType"))
        XCTAssertTrue(runtime.contains("textConfigModelType: install.textConfigModelType"))
        XCTAssertTrue(runtime.contains("modality: Self.turboQuantModality(for: install)"))
        XCTAssertTrue(runtime.contains("parameterCountB: Self.parameterCountBillionScale(for: install)"))
        XCTAssertTrue(runtime.contains("routedExperts: install.routedExperts"))
        XCTAssertTrue(runtime.contains("expertsPerToken: install.expertsPerToken"))
        XCTAssertTrue(runtime.contains("keyHeadDimension: install.keyHeadDimension"))
        XCTAssertTrue(runtime.contains("valueHeadDimension: install.valueHeadDimension"))
        XCTAssertTrue(runtime.contains("contextLength: contextLength"))
        XCTAssertTrue(runtime.contains("let identifiers = [install.repository, install.modelID.rawValue, install.displayName]"))
        XCTAssertTrue(runtime.contains("preset: .conservativeFallback"))
        XCTAssertTrue(runtime.contains("profileSource: \"generic_conservative_fallback\""))
        XCTAssertTrue(runtime.contains("LocalProviderMetadataKeys.turboQuantProfileSource"))
        XCTAssertTrue(runtime.contains("LocalProviderMetadataKeys.turboQuantProfileID"))

        guard let valueBitsLookup = runtime.range(of: "private static func resolvedTurboQuantValueBits") else {
            XCTFail("Missing TurboQuant value-bit resolver.")
            return
        }
        let resolverBody = runtime[valueBitsLookup.lowerBound...].prefix(1200)
        XCTAssertTrue(resolverBody.contains("modelType: install.modelType"))
        XCTAssertTrue(resolverBody.contains("textConfigModelType: install.textConfigModelType"))
        XCTAssertTrue(resolverBody.contains("modality: install.effectiveTurboQuantModalities.contains(.vision) ? .visionText : .text"))
        XCTAssertTrue(resolverBody.contains("parameterCountB: install.resolvedParameterCount.map { Double($0) / 1_000_000_000 }"))
        XCTAssertTrue(resolverBody.contains("routedExperts: install.routedExperts"))
        XCTAssertTrue(resolverBody.contains("expertsPerToken: install.expertsPerToken"))
        XCTAssertTrue(resolverBody.contains("keyHeadDimension: install.keyHeadDimension"))
        XCTAssertTrue(resolverBody.contains("valueHeadDimension: install.valueHeadDimension"))
    }

    func testModelInstallPersistenceCarriesHeadDimensionMetadata() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let schema = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/PinesCore/Persistence/DatabaseSchema.swift"),
            encoding: .utf8
        )
        let store = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Persistence/GRDBPinesStore.swift"),
            encoding: .utf8
        )
        let mapping = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Persistence/GRDBPinesStore+Mapping.swift"),
            encoding: .utf8
        )
        let lifecycle = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/ModelLifecycleService.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(schema.contains("ALTER TABLE model_installs ADD COLUMN key_head_dimension INTEGER;"))
        XCTAssertTrue(schema.contains("ALTER TABLE model_installs ADD COLUMN value_head_dimension INTEGER;"))
        XCTAssertTrue(schema.contains("ALTER TABLE model_installs ADD COLUMN text_config_model_type TEXT;"))
        XCTAssertTrue(schema.contains("ALTER TABLE model_installs ADD COLUMN routed_experts INTEGER;"))
        XCTAssertTrue(schema.contains("ALTER TABLE model_installs ADD COLUMN experts_per_token INTEGER;"))
        XCTAssertTrue(schema.contains("ALTER TABLE model_installs ADD COLUMN cache_topology TEXT NOT NULL DEFAULT 'standardAttention';"))
        XCTAssertTrue(schema.contains("ALTER TABLE model_installs ADD COLUMN turbo_quant_family_support TEXT NOT NULL DEFAULT 'attentionKVFull';"))
        XCTAssertTrue(store.contains("text_config_model_type, processor_class, key_head_dimension, value_head_dimension, routed_experts, experts_per_token, cache_topology, turbo_quant_family_support"))
        XCTAssertTrue(store.contains("text_config_model_type = excluded.text_config_model_type"))
        XCTAssertTrue(store.contains("key_head_dimension = excluded.key_head_dimension"))
        XCTAssertTrue(store.contains("value_head_dimension = excluded.value_head_dimension"))
        XCTAssertTrue(store.contains("routed_experts = excluded.routed_experts"))
        XCTAssertTrue(store.contains("experts_per_token = excluded.experts_per_token"))
        XCTAssertTrue(store.contains("cache_topology = excluded.cache_topology"))
        XCTAssertTrue(store.contains("turbo_quant_family_support = excluded.turbo_quant_family_support"))
        XCTAssertTrue(store.contains("install.textConfigModelType"))
        XCTAssertTrue(store.contains("install.keyHeadDimension"))
        XCTAssertTrue(store.contains("install.valueHeadDimension"))
        XCTAssertTrue(store.contains("install.routedExperts"))
        XCTAssertTrue(store.contains("install.expertsPerToken"))
        XCTAssertTrue(mapping.contains("textConfigModelType: row[\"text_config_model_type\"] as String?"))
        XCTAssertTrue(mapping.contains("keyHeadDimension: row[\"key_head_dimension\"] as Int?"))
        XCTAssertTrue(mapping.contains("valueHeadDimension: row[\"value_head_dimension\"] as Int?"))
        XCTAssertTrue(mapping.contains("routedExperts: row[\"routed_experts\"] as Int?"))
        XCTAssertTrue(mapping.contains("expertsPerToken: row[\"experts_per_token\"] as Int?"))
        XCTAssertTrue(lifecycle.contains("textConfigModelType: result.textConfigModelType"))
        XCTAssertTrue(lifecycle.contains("keyHeadDimension: result.keyHeadDimension"))
        XCTAssertTrue(lifecycle.contains("valueHeadDimension: result.valueHeadDimension"))
        XCTAssertTrue(lifecycle.contains("routedExperts: result.routedExperts"))
        XCTAssertTrue(lifecycle.contains("expertsPerToken: result.expertsPerToken"))
        XCTAssertTrue(lifecycle.contains("set(\\.modelType, result.modelType)"))
        XCTAssertTrue(lifecycle.contains("set(\\.textConfigModelType, result.textConfigModelType)"))
        XCTAssertTrue(lifecycle.contains("set(\\.parameterCount, result.parameterCount)"))
        XCTAssertTrue(lifecycle.contains("localModelFiles(in: resolvedURL)"))
    }

    func testMemoryPressureCancellationIsTypedAndRecoverableInStressHarness() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let inferenceTypes = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/PinesCore/Inference/InferenceTypes.swift"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/MLXRuntimeBridge.swift"),
            encoding: .utf8
        )
        let runtimeTypes = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/PinesCore/Inference/RuntimeTypes.swift"),
            encoding: .utf8
        )
        let monitor = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/DeviceRuntimeMonitor.swift"),
            encoding: .utf8
        )
        let metrics = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/PinesRuntimeMetrics.swift"),
            encoding: .utf8
        )
        let rootView = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesRootView.swift"),
            encoding: .utf8
        )
        let appModel = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModel.swift"),
            encoding: .utf8
        )
        let stress = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModel+Stress.swift"),
            encoding: .utf8
        )
        let diagnostics = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesStressDiagnostics.swift"),
            encoding: .utf8
        )
        let script = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/diagnostics/run-ios-freeze-stress.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(inferenceTypes.contains("generationCancellationReason"))
        XCTAssertTrue(runtime.contains("generationCancellationReason"))
        XCTAssertTrue(runtime.contains("Local generation was cancelled because iOS reported memory pressure."))
        XCTAssertTrue(runtime.contains("Local generation was cancelled because iOS reported critical thermal pressure"))
        XCTAssertTrue(runtime.contains("MLX.withError"))
        XCTAssertTrue(runtime.contains("validateLocalChatAssets"))
        XCTAssertTrue(runtime.contains("tokenizerSource: nil"))
        XCTAssertTrue(runtime.contains("mlx.memory_pressure.soft_recover"))
        XCTAssertTrue(runtime.contains("mlx.memory_pressure.in_generation_soft_recover"))
        XCTAssertTrue(runtime.contains("maxSoftMemoryWarningsPerGeneration"))
        XCTAssertTrue(runtime.contains("activeGenerationEmergencyMinimumAvailableBytes"))
        XCTAssertTrue(runtime.contains("activeGenerationHasEmergencyHeadroom"))
        XCTAssertTrue(runtimeTypes.contains("LocalGenerationPipelinePlan"))
        XCTAssertTrue(runtime.contains("LocalGenerationPipelinePlan("))
        XCTAssertTrue(runtime.contains("initialGenerationAvailableMemoryBytes"))
        XCTAssertTrue(runtime.contains("generationPlan.fitPreparedPrompt"))
        XCTAssertTrue(runtime.contains("generationPlan.providerMetadata()"))
        XCTAssertTrue(runtimeTypes.contains("generationInitialAvailableMemoryBytes"))
        XCTAssertTrue(runtimeTypes.contains("generationPressureCompletionLimit"))
        XCTAssertTrue(runtimeTypes.contains("generationEffectiveMaxKVSize"))
        XCTAssertTrue(runtimeTypes.contains("generationMaxKVSizeClamped"))
        XCTAssertTrue(runtimeTypes.contains("defaultKVCacheSizeFloorTokens"))
        XCTAssertTrue(runtimeTypes.contains("LocalRuntimeSafetyPolicy.constrainedAvailableMemoryBytes"))
        XCTAssertTrue(runtimeTypes.contains("availableMemoryBytes < 1_000_000_000"))
        XCTAssertTrue(runtimeTypes.contains("pressureLimit = 128"))
        XCTAssertTrue(runtimeTypes.contains("headroomLimit = 128"))
        XCTAssertTrue(runtime.contains("mlx.thermal_pressure.cancel_unload"))
        XCTAssertTrue(runtime.contains("MLXCachePressureController.shared.configureActive(limit: mlxCacheLimit(for: profile))"))
        XCTAssertTrue(runtime.contains("profile.quantization.runtimePressureReason == .lowMemory"))
        XCTAssertTrue(runtime.contains("Self.configureMLXMemoryPolicy(profile: profile)"))
        XCTAssertTrue(runtime.contains("Memory.clearCache()"))
        XCTAssertTrue(runtime.contains("applySoftMemoryPressureMLXPolicy"))
        XCTAssertTrue(runtime.contains("resetMLXPeakMemory()"))
        XCTAssertTrue(runtime.contains("waitForActiveGenerationCancellationToDrain"))
        XCTAssertTrue(runtime.contains("pressureUnloadDrainTimeoutSeconds"))
        XCTAssertTrue(runtime.contains("memoryPressureSoftRecoveryMinimumAvailableBytes"))
        XCTAssertTrue(runtime.contains("generationSafety.constrainedRuntimeProfile(activeProfile)"))
        XCTAssertTrue(runtime.contains("maxTokensOverride"))
        XCTAssertTrue(runtime.contains("maxKVSizeOverride"))
        XCTAssertTrue(runtimeTypes.contains("generationMaxTokensClamped"))
        XCTAssertTrue(runtime.contains("#if targetEnvironment(simulator)"))
        XCTAssertTrue(runtime.contains("mlx_cache_memory_bytes"))
        XCTAssertTrue(runtime.contains("process_physical_footprint_bytes"))
        XCTAssertTrue(runtimeTypes.contains("mlxCacheMemoryBytes"))
        XCTAssertTrue(runtimeTypes.contains("processPhysicalFootprintBytes"))
        XCTAssertTrue(runtimeTypes.contains("constrainedModeActive"))
        XCTAssertTrue(runtimeTypes.contains("constrained.quantization.runtimePressureReason = pressureReason"))
        XCTAssertTrue(runtimeTypes.contains("minimumAvailableMemoryBytes: Int64 = 900_000_000"))
        XCTAssertTrue(runtimeTypes.contains("constrainedAvailableMemoryBytes: Int64 = 1_500_000_000"))
        XCTAssertTrue(runtimeTypes.contains("let downshift = criticalThermal || thinThermal"))
        XCTAssertFalse(runtimeTypes.contains("let severelyThermal = thermal == \"serious\" || thermal == \"critical\""))
        XCTAssertTrue(runtimeTypes.contains("let criticallyThermal = thermal == \"critical\""))
        XCTAssertTrue(runtimeTypes.contains("requiresImmediateUnload: false"))
        XCTAssertTrue(monitor.contains("MLX.Memory.snapshot()"))
        XCTAssertTrue(monitor.contains("task_vm_info_data_t"))
        XCTAssertTrue(monitor.contains("#if targetEnvironment(simulator)"))
        XCTAssertTrue(metrics.contains("mlx_cache="))
        XCTAssertTrue(metrics.contains("thermal_pressure physical="))
        XCTAssertTrue(rootView.contains("ProcessInfo.processInfo.thermalState == .critical"))
        XCTAssertFalse(rootView.contains("ProcessInfo.processInfo.thermalState == .serious"))
        XCTAssertTrue(stress.contains("stress.iteration.memory_pressure_recovered"))
        XCTAssertTrue(stress.contains("stress.iteration.memory_pressure_cooldown"))
        XCTAssertTrue(stress.contains("stress.iteration.thermal_pressure_recovered"))
        XCTAssertTrue(stress.contains("stress.iteration.thermal_pressure_cooldown"))
        XCTAssertTrue(stress.contains("recoverableLocalStressPressureReason(from message: ChatMessage?)"))
        XCTAssertTrue(stress.contains("settledLastAssistantMessage"))
        XCTAssertTrue(stress.contains("Recovered from memory-pressure cancellation"))
        XCTAssertTrue(diagnostics.contains("PINES_STRESS_RECOVERY_COOLDOWN_SECONDS"))
        XCTAssertTrue(diagnostics.contains("PINES_STRESS_CONTEXT_MODE"))
        XCTAssertTrue(diagnostics.contains("case suite"))
        XCTAssertTrue(diagnostics.contains("requiresRuntimeContextWindow"))
        XCTAssertTrue(stress.contains("context_plan_preview"))
        XCTAssertTrue(stress.contains("runtimeMaxContextTokens"))
        XCTAssertTrue(stress.contains("targetContextTokens"))
        XCTAssertTrue(stress.contains("\"model_type\": install.modelType"))
        XCTAssertTrue(stress.contains("\"key_head_dimension\": install.keyHeadDimension"))
        XCTAssertTrue(stress.contains("\"value_head_dimension\": install.valueHeadDimension"))
        XCTAssertTrue(stress.contains("stress.installed_models"))
        XCTAssertTrue(stress.contains("selectedStressInstall"))
        XCTAssertTrue(stress.contains("localStressOutputQualityFailure"))
        XCTAssertTrue(stress.contains("allowPressureRecovery"))
        XCTAssertTrue(stress.contains("disable_turboquant"))
        XCTAssertTrue(appModel.contains("stressDisablesTurboQuant"))
        XCTAssertTrue(appModel.contains("stress_plain_kv_control"))
        XCTAssertTrue(diagnostics.contains("PINES_STRESS_MODEL_ID"))
        XCTAssertTrue(diagnostics.contains("PINES_STRESS_ALLOW_PRESSURE_RECOVERY"))
        XCTAssertTrue(diagnostics.contains("PINES_STRESS_DISABLE_TURBOQUANT"))
        XCTAssertTrue(script.contains("PINES_STRESS_RECOVERY_COOLDOWN_SECONDS"))
        XCTAssertTrue(script.contains("PINES_STRESS_MODEL_ID"))
        XCTAssertTrue(script.contains("PINES_STRESS_ALLOW_PRESSURE_RECOVERY"))
        XCTAssertTrue(script.contains("PINES_STRESS_DISABLE_TURBOQUANT"))
        XCTAssertTrue(script.contains("PINES_STRESS_CONTEXT_MODE"))
        XCTAssertTrue(script.contains("off|sweep|high|max|suite"))
        XCTAssertTrue(script.contains("PINES_STRESS_CONTEXT_TARGET_TOKENS"))
        XCTAssertTrue(script.contains("PINES_STRESS_CONTEXT_RESERVE_TOKENS"))
        XCTAssertTrue(script.contains("PINES_STRESS_XCODEBUILD_SETTINGS"))
        XCTAssertTrue(script.contains("shlex.split(extra_build_settings)"))
        XCTAssertTrue(script.contains("app_process_alive"))
        XCTAssertTrue(script.contains("--signal 0"))
        XCTAssertTrue(script.contains("app process $pid exited"))
    }

    func testLocalRuntimeTreatsTokenCapCancellationAsLengthCompletion() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtime = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Runtime/MLXRuntimeBridge.swift"),
            encoding: .utf8
        )
        let appModel = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModel.swift"),
            encoding: .utf8
        )
        let stress = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModel+Stress.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(runtime.contains("generatedTokens: completionInfo.generationTokenCount"))
        XCTAssertTrue(runtime.contains("emittedTokenCount: tokenCount"))
        XCTAssertTrue(runtime.contains("maxTokens: generationPlan.effectiveMaxTokens"))
        XCTAssertTrue(runtime.contains("max(generatedTokens, emittedTokenCount) >= maxTokens"))
        XCTAssertTrue(runtime.contains("return .length"))
        XCTAssertTrue(appModel.contains("case .length:"))
        XCTAssertTrue(appModel.contains("status = .failed"))
        XCTAssertTrue(stress.contains("if status != .complete"))
    }

    func testArtifactsWorkspaceUsesZeroNavigationGalleryAndQuickLookSheets() throws {
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

        XCTAssertTrue(models.contains("enum ArtifactsRoute"))
        XCTAssertTrue(models.contains("case artifact(String)"))
        XCTAssertTrue(models.contains("case create(kind: ArtifactsMediaKind"))
        XCTAssertTrue(models.contains("case research(threadID: String?)"))
        XCTAssertTrue(workspace.contains("private enum ArtifactSheet"))
        XCTAssertTrue(workspace.contains("ArtifactGalleryTile"))
        XCTAssertTrue(workspace.contains("ArtifactQuickLookView"))
        XCTAssertTrue(workspace.contains("private var newArtifactMenu"))
        XCTAssertTrue(workspace.contains("private var filterMenu"))
        XCTAssertTrue(workspace.contains("private var activityStrip"))
        XCTAssertTrue(workspace.contains(".sheet(item: $presentedSheet)"))
        XCTAssertFalse(workspace.contains("ArtifactCommandDeck"))
        XCTAssertFalse(workspace.contains(".inspector("))
        XCTAssertFalse(workspace.contains("private var commandStrip"))
        XCTAssertFalse(workspace.contains("private var scopeMenu"))
        XCTAssertFalse(workspace.contains("private var workQueue"))
        XCTAssertFalse(workspace.contains("NavigationStack(path: $path)"))
        XCTAssertFalse(workspace.contains("ArtifactCategoryChip"))
        XCTAssertFalse(workspace.contains("ArtifactsResearchHistoryView"))
        XCTAssertTrue(workspace.contains("ArtifactCreateView"))
        XCTAssertTrue(workspace.contains("ArtifactResearchView"))
        XCTAssertTrue(workspace.contains("Image Studio"))
        XCTAssertTrue(workspace.contains("Turn a question into a sourced brief"))
        XCTAssertTrue(workspace.contains("Shape the Brief"))
        XCTAssertTrue(workspace.contains("private var imageStudioSettings"))
        XCTAssertTrue(workspace.contains("private var researchSettings"))
        XCTAssertFalse(workspace.contains("PinesWorkspaceSwitcher"))
        XCTAssertFalse(workspace.contains("ArtifactsStorageWorkspace"))
        XCTAssertFalse(workspace.contains("ArtifactsFilesWorkspace"))
        XCTAssertFalse(workspace.contains("ArtifactsBatchesWorkspace"))
        XCTAssertFalse(workspace.contains("ArtifactsRealtimeWorkspace"))
        XCTAssertFalse(workspace.contains("ArtifactsCapabilitiesWorkspace"))
        XCTAssertTrue(workspace.contains("Deep Research"))
        XCTAssertTrue(workspace.contains("conversation"))
        XCTAssertTrue(workspace.contains("composer"))
        XCTAssertTrue(workspace.contains("PinesMessageBubble"))
        XCTAssertTrue(workspace.contains("Ask a research question"))
        XCTAssertTrue(workspace.contains("Ask a follow-up"))
        XCTAssertTrue(workspace.contains("derivedResearchTitle"))
        XCTAssertTrue(workspace.contains("cancelMediaOperation"))
        XCTAssertTrue(workspace.contains("usesProviderFiles"))
        XCTAssertTrue(workspace.contains(".webOnly()"))
        XCTAssertTrue(workspace.contains("This removes only Pines' local record"))
        XCTAssertFalse(models.contains("enum ArtifactsWorkspaceMode"))
        XCTAssertTrue(models.contains("isVisibleInArtifactsGallery"))
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

    func testAdvancedKeySaveSurfacesProviderAndModelCatalogState() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Settings/CloudProvidersSettingsPage.swift"),
            encoding: .utf8
        )
        let appModel = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModel.swift"),
            encoding: .utf8
        )
        let chats = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Chats/ChatsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settings.contains("@State private var enabledForAgents: Bool"))
        XCTAssertTrue(settings.contains("let provider: CloudProviderConfiguration?"))
        XCTAssertTrue(settings.contains("@State private var saveError: String?"))
        XCTAssertTrue(settings.contains("saveCloudProvider("))
        XCTAssertTrue(settings.contains("New API key (optional)"))
        XCTAssertTrue(settings.contains("Edit Provider"))
        XCTAssertTrue(settings.contains("CloudProviderEditorSheet(provider:"))
        XCTAssertTrue(settings.contains("OpenRouter routing & usage"))
        XCTAssertTrue(settings.contains("Web search engine"))
        XCTAssertTrue(settings.contains("Require zero data retention"))
        XCTAssertTrue(settings.contains("savePolicy()"))
        XCTAssertTrue(settings.contains("pines.settings.openrouter.routing"))
        XCTAssertTrue(settings.contains("Use for agents"))
        XCTAssertTrue(settings.contains("provider.defaultModelID"))
        XCTAssertTrue(settings.contains("compactModelName(model.rawValue)"))
        XCTAssertTrue(appModel.contains("finishSavedCloudProviderActivation"))
        XCTAssertTrue(appModel.contains("providerID: ProviderID? = nil"))
        XCTAssertTrue(appModel.contains("let resolvedProviderID = providerID ?? Self.makeCloudProviderID(kind: kind)"))
        XCTAssertTrue(appModel.contains("The provider being edited no longer exists"))
        XCTAssertTrue(appModel.contains("Another cloud provider already uses that display name"))
        XCTAssertTrue(appModel.contains("keychainAccount: existing?.keychainAccount ?? resolvedProviderID.rawValue"))
        XCTAssertTrue(appModel.contains("cloudProviderRequiresValidation"))
        XCTAssertTrue(appModel.contains("openRouterRequestOptions"))
        XCTAssertTrue(appModel.contains("openRouterProviderPreferences: openRouterProviderPreferences"))
        XCTAssertTrue(appModel.contains("applyCloudProviderValidationResult"))
        XCTAssertTrue(appModel.contains("recordFirstCloudModelIfNeeded"))
        XCTAssertTrue(appModel.contains("replaceCloudModelCatalog"))
        XCTAssertTrue(appModel.contains("models.isEmpty ? nil : models"))
        XCTAssertTrue(appModel.contains("var nextSnapshots = cloudModelCatalogSnapshots.filter"))
        XCTAssertTrue(appModel.contains("hydrateCloudModelCatalogSnapshots"))
        XCTAssertTrue(appModel.contains("snapshot.isFresh(at: now)"))
        XCTAssertTrue(appModel.contains("cloud.model_catalog.persist"))
        XCTAssertTrue(appModel.contains("recordRecoverableIssue(\"cloud.model_catalog.refresh.\\(provider.id.rawValue)\""))
        XCTAssertTrue(appModel.contains("func setCloudProviderEnabled"))
        XCTAssertTrue(chats.contains("No agent models"))
        XCTAssertTrue(chats.contains("no curated agent models"))
        XCTAssertTrue(chats.contains("Saved Providers"))
    }

    func testSettingsUsesTypedDestinationsAndFocusedPages() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let types = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModelTypes.swift"),
            encoding: .utf8
        )
        let detail = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Settings/SettingsDetailView.swift"),
            encoding: .utf8
        )
        let settingsView = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Settings/SettingsView.swift"),
            encoding: .utf8
        )

        for destination in [
            "appearance", "aiModels", "cloudProviders", "privacyData",
            "toolsIntegrations", "diagnostics",
        ] {
            XCTAssertTrue(types.contains("case \(destination)"), "Missing typed settings destination \(destination)")
        }

        for page in [
            "AppearanceSettingsPage", "AIModelsSettingsPage", "CloudProvidersSettingsPage",
            "PrivacyDataSettingsPage", "ToolsIntegrationsSettingsPage", "DiagnosticsSettingsPage",
        ] {
            XCTAssertTrue(detail.contains(page), "Settings dispatcher does not route to \(page)")
        }

        XCTAssertTrue(settingsView.contains("Section(\"Support\")"))
        XCTAssertTrue(settingsView.contains("section.destination.rawValue"))
        XCTAssertFalse(detail.contains("case \"Design\""))
        XCTAssertFalse(detail.contains("PinesCardSection"))
    }

    func testCloudProviderEditIdentityAndValidationSemantics() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1"))
        let changedURL = try XCTUnwrap(URL(string: "https://example.com/openrouter/v1"))
        let provider = CloudProviderConfiguration(
            id: "openrouter-stable-id",
            kind: .openRouter,
            displayName: "OpenRouter",
            baseURL: originalURL,
            validationStatus: .valid,
            keychainAccount: "openrouter-stable-key"
        )
        let firstID = PinesAppModel.makeCloudProviderID(
            kind: .openRouter,
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let secondID = PinesAppModel.makeCloudProviderID(
            kind: .openRouter,
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )

        XCTAssertEqual(firstID.rawValue, "openRouter-00000000-0000-0000-0000-000000000001")
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertFalse(
            PinesAppModel.cloudProviderRequiresValidation(
                existing: provider,
                updatedBaseURL: originalURL,
                replacementAPIKey: ""
            )
        )
        XCTAssertTrue(
            PinesAppModel.cloudProviderRequiresValidation(
                existing: provider,
                updatedBaseURL: changedURL,
                replacementAPIKey: ""
            )
        )
        XCTAssertTrue(
            PinesAppModel.cloudProviderRequiresValidation(
                existing: provider,
                updatedBaseURL: originalURL,
                replacementAPIKey: "new-secret"
            )
        )
    }

    func testCloudKitSyncHealthIsUserVisibleAndRetryable() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appState = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppState.swift"),
            encoding: .utf8
        )
        let appModel = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/App/PinesAppModel.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Settings/PrivacyDataSettingsPage.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appState.contains("struct PinesCloudKitSyncStatus: Equatable"))
        XCTAssertTrue(appState.contains("@Published var cloudKitSyncStatus"))
        XCTAssertTrue(appModel.contains("phase: .syncing"))
        XCTAssertTrue(appModel.contains("phase: .succeeded"))
        XCTAssertTrue(appModel.contains("phase: .failed"))
        XCTAssertTrue(appModel.contains("services.redactor.redact(error.localizedDescription)"))
        XCTAssertTrue(settings.contains("cloudKitSyncSummary"))
        XCTAssertTrue(settings.contains("reason: \"manual_settings\""))
        XCTAssertTrue(settings.contains("pines.settings.icloud.sync-now"))
        XCTAssertTrue(settings.contains("pines.settings.icloud.error"))
    }
}

private actor AgentToolInvocationCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private actor AgentTranscriptRecorder {
    private var stored = [ChatMessage]()

    func append(_ message: ChatMessage) {
        stored.append(message)
    }

    func messages() -> [ChatMessage] {
        stored
    }
}

private actor UnadvertisedToolCallProvider: InferenceProvider {
    nonisolated let id: ProviderID = "unadvertised-tool-test"
    nonisolated let capabilities = ProviderCapabilities(
        local: true,
        toolCalling: true,
        maxContextTokens: 4_096,
        maxOutputTokens: 512
    )
    private var requests = 0

    func requestCount() -> Int {
        requests
    }

    func streamEvents(
        _ request: ChatRequest
    ) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        requests += 1
        let requestNumber = requests
        return AsyncThrowingStream { continuation in
            if requestNumber == 1 {
                continuation.yield(
                    .toolCall(
                        ToolCallDelta(
                            id: "secret-call",
                            name: "secret_tool",
                            argumentsFragment: "{}",
                            isComplete: true
                        )
                    )
                )
                continuation.yield(.finish(InferenceFinish(reason: .toolCall)))
            } else {
                continuation.yield(.token(TokenDelta(text: "Safe final response", tokenCount: 3)))
                continuation.yield(.finish(InferenceFinish(reason: .stop)))
            }
            continuation.finish()
        }
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        EmbeddingResult(modelID: request.modelID, vectors: [])
    }
}

private struct TwoToolCallProvider: InferenceProvider {
    let id: ProviderID = "two-tool-test"
    let capabilities = ProviderCapabilities(
        local: true,
        toolCalling: true,
        maxContextTokens: 4_096,
        maxOutputTokens: 512
    )

    func streamEvents(
        _ request: ChatRequest
    ) async throws -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .toolCall(
                    ToolCallDelta(
                        id: "call-local",
                        name: "local_tool",
                        argumentsFragment: "{}",
                        isComplete: true
                    )
                )
            )
            continuation.yield(
                .toolCall(
                    ToolCallDelta(
                        id: "call-approval",
                        name: "approval_tool",
                        argumentsFragment: "{}",
                        isComplete: true
                    )
                )
            )
            continuation.yield(.finish(InferenceFinish(reason: .toolCall)))
            continuation.finish()
        }
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        EmbeddingResult(modelID: request.modelID, vectors: [])
    }
}
