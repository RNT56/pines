import Foundation
import XCTest
import PinesCore

final class CoreSurfaceTests: XCTestCase {
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
        XCTAssertTrue(runtime.contains("ModelLifecycleService.installedModelDirectory(for: install)"))
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
        XCTAssertTrue(runtime.contains("Local generation was cancelled because the device became too hot"))
        XCTAssertTrue(runtime.contains("mlx.thermal_pressure.cancel_unload"))
        XCTAssertTrue(runtime.contains("Memory.cacheLimit = mlxCacheLimit(for: profile)"))
        XCTAssertTrue(runtime.contains("Memory.clearCache()"))
        XCTAssertTrue(runtime.contains("resetMLXPeakMemory()"))
        XCTAssertTrue(runtime.contains("#if targetEnvironment(simulator)"))
        XCTAssertTrue(runtime.contains("mlx_cache_memory_bytes"))
        XCTAssertTrue(runtimeTypes.contains("mlxCacheMemoryBytes"))
        XCTAssertTrue(runtimeTypes.contains("constrainedModeActive"))
        XCTAssertTrue(runtimeTypes.contains("requiresImmediateUnload: false"))
        XCTAssertTrue(monitor.contains("MLX.Memory.snapshot()"))
        XCTAssertTrue(monitor.contains("#if targetEnvironment(simulator)"))
        XCTAssertTrue(metrics.contains("mlx_cache="))
        XCTAssertTrue(metrics.contains("thermal_pressure physical="))
        XCTAssertTrue(stress.contains("stress.iteration.memory_pressure_recovered"))
        XCTAssertTrue(stress.contains("stress.iteration.memory_pressure_cooldown"))
        XCTAssertTrue(stress.contains("stress.iteration.thermal_pressure_recovered"))
        XCTAssertTrue(stress.contains("stress.iteration.thermal_pressure_cooldown"))
        XCTAssertTrue(stress.contains("settledLastAssistantMessage"))
        XCTAssertTrue(stress.contains("Recovered from memory-pressure cancellation"))
        XCTAssertTrue(diagnostics.contains("PINES_STRESS_RECOVERY_COOLDOWN_SECONDS"))
        XCTAssertTrue(script.contains("PINES_STRESS_RECOVERY_COOLDOWN_SECONDS"))
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

        for mode in ["Library", "Create", "Research"] {
            XCTAssertTrue(workspace.contains(mode), "Missing artifacts workspace mode \(mode)")
        }
        XCTAssertFalse(workspace.contains("case .storage"))
        XCTAssertFalse(workspace.contains("case .jobs"))
        XCTAssertTrue(workspace.contains("ArtifactsMediaModelOption"))
        XCTAssertTrue(workspace.contains("ArtifactsResearchModelOption"))
        XCTAssertTrue(workspace.contains("ArtifactsWorkspaceModePicker"))
        XCTAssertTrue(workspace.contains("Deep Research"))
        XCTAssertFalse(workspace.contains("Research Console"))
        XCTAssertFalse(workspace.contains("Research Chat"))
        XCTAssertTrue(workspace.contains("researchChatTranscript"))
        XCTAssertTrue(workspace.contains("researchChatComposer"))
        XCTAssertTrue(workspace.contains("ArtifactsResearchSourcesMessage"))
        XCTAssertTrue(workspace.contains("Ask a research question"))
        XCTAssertTrue(workspace.contains("Ask follow-up or clarify"))
        XCTAssertTrue(workspace.contains("Report saved. Open the full report"))
        XCTAssertTrue(workspace.contains("derivedResearchTitle"))
        XCTAssertFalse(workspace.contains("LazyVGrid(columns: [GridItem(.adaptive(minimum: 148)"))
        XCTAssertTrue(workspace.contains("ArtifactsArtifactGallery"))
        XCTAssertTrue(workspace.contains("ArtifactsMenuPill"))
        XCTAssertTrue(workspace.contains("This removes only Pines' local lifecycle record"))
        XCTAssertTrue(models.contains("enum ArtifactsWorkspaceMode"))
        XCTAssertTrue(models.contains("isVisibleInArtifactsGallery"))
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

    func testAdvancedKeySaveSurfacesProviderAndModelCatalogState() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Settings/SettingsDetailView.swift"),
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

        XCTAssertTrue(settings.contains("@State private var providerEnabled = true"))
        XCTAssertTrue(settings.contains("providerSaveConfirmation"))
        XCTAssertTrue(settings.contains("Saved \\(savedName). Validating the key and refreshing models."))
        XCTAssertTrue(settings.contains("Use for agents"))
        XCTAssertTrue(settings.contains("Default model"))
        XCTAssertTrue(settings.contains("provider.defaultModelID"))
        XCTAssertTrue(appModel.contains("finishSavedCloudProviderActivation"))
        XCTAssertTrue(appModel.contains("applyCloudProviderValidationResult"))
        XCTAssertTrue(appModel.contains("recordFirstCloudModelIfNeeded"))
        XCTAssertTrue(appModel.contains("replaceCloudModelCatalog"))
        XCTAssertTrue(appModel.contains("models.isEmpty ? nil : models"))
        XCTAssertTrue(appModel.contains("var nextCatalog = cloudModelCatalog.filter"))
        XCTAssertTrue(appModel.contains("recordRecoverableIssue(\"cloud.model_catalog.refresh.\\(provider.id.rawValue)\""))
        XCTAssertTrue(appModel.contains("func setCloudProviderEnabled"))
        XCTAssertTrue(chats.contains("No agent models"))
        XCTAssertTrue(chats.contains("no curated agent models"))
        XCTAssertTrue(chats.contains("Saved Providers"))
    }
}
