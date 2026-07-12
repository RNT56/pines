import Foundation
import XCTest
import PinesCore
@testable import pines

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
        XCTAssertFalse(rootView.contains("private struct ProviderWorkspaceView"))
        XCTAssertFalse(rootView.contains("ProviderLifecycleDashboard"))
    }

    func testArtifactsCreateAndLibraryUseDedicatedAssetStudioSurfaces() throws {
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
        XCTAssertTrue(models.contains("static func assetViewModels"))
        XCTAssertTrue(models.contains("isVisibleInArtifactsGallery"))
        XCTAssertTrue(workspace.contains("ArtifactsAssetGrid"))
        XCTAssertTrue(workspace.contains("ArtifactsAssetInspector"))
        XCTAssertTrue(workspace.contains("ArtifactsCreateComposer"))
        XCTAssertTrue(workspace.contains("ArtifactsCreateOutputRail"))
        XCTAssertFalse(workspace.contains("PinesCardSection(\"Generate Media\""))
        XCTAssertFalse(workspace.contains("PinesCardSection(\"Gallery\""))
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
        XCTAssertTrue(workspace.contains("PinesWorkspaceSwitcher"))
        XCTAssertTrue(workspace.contains("Deep Research"))
        XCTAssertFalse(workspace.contains("Research Console"))
        XCTAssertFalse(workspace.contains("Research Chat"))
        XCTAssertTrue(workspace.contains("researchConversation"))
        XCTAssertTrue(workspace.contains("researchComposer"))
        XCTAssertFalse(workspace.contains("ArtifactsResearchChatWorkspace"))
        XCTAssertTrue(workspace.contains("PinesMessageBubble"))
        XCTAssertTrue(workspace.contains("Ask a research question"))
        XCTAssertTrue(workspace.contains("Ask a follow-up"))
        XCTAssertTrue(workspace.contains("Report saved. Open the full report"))
        XCTAssertTrue(workspace.contains("derivedResearchTitle"))
        XCTAssertTrue(workspace.contains("cancelMediaOperation"))
        XCTAssertFalse(workspace.contains("LazyVGrid(columns: [GridItem(.adaptive(minimum: 148)"))
        XCTAssertTrue(workspace.contains("ArtifactsAssetGrid"))
        XCTAssertTrue(workspace.contains("PinesMenuChip"))
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
        XCTAssertTrue(settings.contains("@State private var editingProviderID: ProviderID?"))
        XCTAssertTrue(settings.contains("providerSaveConfirmation"))
        XCTAssertTrue(settings.contains("Saved \\(savedName). Validating the key and refreshing models."))
        XCTAssertTrue(settings.contains("New API key (optional)"))
        XCTAssertTrue(settings.contains("Update provider"))
        XCTAssertTrue(settings.contains("beginProviderEditing(provider)"))
        XCTAssertTrue(settings.contains("cancelProviderEditing()"))
        XCTAssertTrue(settings.contains("OpenRouter routing and privacy"))
        XCTAssertTrue(settings.contains("Require zero data retention"))
        XCTAssertTrue(settings.contains("Save routing policy"))
        XCTAssertTrue(settings.contains("pines.settings.openrouter.routing"))
        XCTAssertTrue(settings.contains("Use for agents"))
        XCTAssertTrue(settings.contains("Default model"))
        XCTAssertTrue(settings.contains("provider.defaultModelID"))
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
        XCTAssertTrue(appModel.contains("var nextCatalog = cloudModelCatalog.filter"))
        XCTAssertTrue(appModel.contains("recordRecoverableIssue(\"cloud.model_catalog.refresh.\\(provider.id.rawValue)\""))
        XCTAssertTrue(appModel.contains("func setCloudProviderEnabled"))
        XCTAssertTrue(chats.contains("No agent models"))
        XCTAssertTrue(chats.contains("no curated agent models"))
        XCTAssertTrue(chats.contains("Saved Providers"))
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
            contentsOf: repoRoot.appendingPathComponent("Pines/Views/Settings/SettingsDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appState.contains("struct PinesCloudKitSyncStatus: Equatable"))
        XCTAssertTrue(appState.contains("@Published var cloudKitSyncStatus"))
        XCTAssertTrue(appModel.contains("phase: .syncing"))
        XCTAssertTrue(appModel.contains("phase: .succeeded"))
        XCTAssertTrue(appModel.contains("phase: .failed"))
        XCTAssertTrue(appModel.contains("services.redactor.redact(error.localizedDescription)"))
        XCTAssertTrue(settings.contains("cloudKitSyncChipStatus"))
        XCTAssertTrue(settings.contains("cloudKitSyncSummary"))
        XCTAssertTrue(settings.contains("reason: \"manual_settings\""))
        XCTAssertTrue(settings.contains("pines.settings.icloud.sync-now"))
        XCTAssertTrue(settings.contains("pines.settings.icloud.error"))
    }
}
