import Foundation
import PinesCore
import Testing

@Suite("Core contracts")
struct CoreContractTests {
    @Test
    func turboQuantSchemaRegistryExposesCanonicalWave0Names() {
        #expect(TurboQuantSchemaRegistry.versionsByName[.admissionPlan] == 1)
        #expect(TurboQuantSchemaRegistry.versionsByName[.runtimeMemoryZones] == 1)
        #expect(TurboQuantSchemaRegistry.versionsByName[.runDecision] == 1)
        #expect(TurboQuantSchemaRegistry.versionsByName[.failureEvent] == 1)
        #expect(TurboQuantSchemaRegistry.versionsByName[.modelProfile] == 2)
        #expect(TurboQuantSchemaRegistry.versionsByName[.turboQuantLayout] == 4)
        #expect(TurboQuantSchemaRegistry.versionsByName[.turboQuantLayoutNext] == 5)
        #expect(TurboQuantSchemaRegistry.versionsByName[.speculativeDecode] == 1)
        #expect(TurboQuantSchemaRegistry.versionsByName[.platformFeatureGate] == 1)
    #expect(TurboQuantSchemaRegistry.versionsByName[.platformUnlockPolicy] == 1)
    #expect(TurboQuantSchemaRegistry.versionsByName[.openKVFormat] == 1)
    #expect(TurboQuantSchemaRegistry.versionsByName[.platformEvidenceDimensions] == 1)
        #expect(TurboQuantSchemaRegistry.allDefinitions.count == TurboQuantSchemaName.allCases.count)
    }

    @Test
    func versionedEnvelopeCarriesProducerAndCompatibilityMetadata() throws {
        let envelope = VersionedEnvelope(
            schemaName: TurboQuantSchemaName.failureEvent.rawValue,
            schemaVersion: TurboQuantSchemaRegistry.failureEvent.version,
            producer: SchemaProducer(repo: "pines", commit: "abc123"),
            compatibility: SchemaCompatibility(
                minReaderVersion: 1,
                maxTestedReaderVersion: 1,
                failClosedIfNewer: true
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            payload: ["kind": "memoryAdmissionFailed"]
        )

        let encoded = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(VersionedEnvelope<[String: String]>.self, from: encoded)

        #expect(decoded.schemaName == "FailureEvent")
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.producer.repo == "pines")
        #expect(decoded.compatibility.failClosedIfNewer)
        #expect(decoded.payload["kind"] == "memoryAdmissionFailed")
    }

    @Test
    func localInferenceFailureKindsMatchCanonicalFailureMatrixNames() {
        let expected: [LocalInferenceFailureKind] = [
            .memoryAdmissionFailed,
            .turboQuantPathUnavailable,
            .turboQuantFallbackUnavailable,
            .fallbackBudgetExceeded,
            .modelProfileUnverified,
            .modelProfileMismatch,
            .unsupportedAttentionShape,
            .unsupportedAttentionMask,
            .unsupportedTensorDType,
            .cacheLayoutInvalid,
            .cacheLifecycleInvalid,
            .contextWindowExceeded,
            .snapshotInvalid,
            .snapshotCorrupt,
            .schemaIncompatible,
            .mlxRuntimeFailure,
            .cloudRouteDisallowed,
        ]

        #expect(LocalInferenceFailureKind.allCases == expected)
        #expect(LocalInferenceFailureMatrix.canonicalRules.count == expected.count)
        #expect(Set(LocalInferenceFailureMatrix.rulesByKind.keys) == Set(expected))
    }

    @Test
    func localInferenceFailureEventEncodesSchemaVersionAndKind() throws {
        let event = LocalInferenceFailureEvent(
            kind: .unsupportedAttentionMask,
            sourceRepo: "mlx-swift-lm",
            sourceType: "AttentionMaskError",
            message: "Mask rank is unsupported.",
            recoverable: true,
            recommendedAction: "Retry with an exact fallback path.",
            admissionPlanID: "admission-1",
            runDecisionID: "run-1"
        )

        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(LocalInferenceFailureEvent.self, from: encoded)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.kind == .unsupportedAttentionMask)
        #expect(decoded.sourceRepo == "mlx-swift-lm")
        #expect(decoded.recoverable)
        #expect(decoded.admissionPlanID == "admission-1")
        #expect(decoded.runDecisionID == "run-1")
    }

    @Test
    func localInferenceFailureMatrixKeepsProductMessagesTyped() throws {
        let rule = try #require(LocalInferenceFailureMatrix.rulesByKind[.fallbackBudgetExceeded])

        #expect(rule.behaviors.contains(.typedError))
        #expect(rule.productMessage == "Fallback would exceed memory budget.")
    }

    @Test
    func turboQuantProductDTOsRemainMLXIndependentAndCodable() throws {
        let zones = TurboQuantRuntimeMemoryZones(
            availableAppMemoryBytes: 6_000_000_000,
            runtimeBudgetBytes: 4_000_000_000,
            mlxActiveBytes: 128_000_000,
            mlxCacheBytes: 64_000_000,
            modelResidentBytes: 2_500_000_000,
            compressedKVBytes: 512_000_000,
            rawShadowBytes: 0,
            fallbackReserveBytes: 256_000_000,
            scratchBytes: 128_000_000,
            promptAndTokenizerBytes: 64_000_000,
            uiReserveBytes: 256_000_000,
            safetyReserveBytes: 512_000_000
        )
        let plan = TurboQuantMemoryPlan(
            requestedContextLength: 128_000,
            admittedContextLength: 96_000,
            requestedMode: .maxContext,
            effectiveMode: .balanced,
            preset: .turbo3_5,
            valueBits: 4,
            groupSize: 64,
            fallbackPolicy: .packedAllowed,
            rawBytesPerToken: 1_024,
            packedFallbackBytesPerToken: 256,
            compressedBytesPerToken: 128,
            usesRawShadow: false,
            packedFallbackEnabled: true,
            usesRollingSummaryMemory: true,
            runtimeZones: zones
        )
        let admission = TurboQuantAdmission(
            admitted: true,
            requestedContextLength: 128_000,
            admittedContextLength: 96_000,
            requestedMode: .maxContext,
            selectedMode: .balanced,
            memoryPlan: plan,
            downgradeReasons: [
                TurboQuantAdmissionDowngrade(
                    reason: .reducedContext,
                    message: "Reduced context to preserve memory headroom."
                )
            ],
            rejectedPaths: [
                RejectedPath(path: "onlineFused", reason: "unsupported head dimension")
            ],
            userMessage: "96K tokens are available for this local run."
        )

        let encoded = try JSONEncoder().encode(admission)
        let decoded = try JSONDecoder().decode(TurboQuantAdmission.self, from: encoded)

        #expect(decoded == admission)
        #expect(decoded.memoryPlan?.runtimeZones.totalRuntimeBytes == zones.totalRuntimeBytes)
        #expect(decoded.selectedMode == .balanced)
    }

    @Test
    func turboQuantEightBitPresetRoundTripsThroughCoreContracts() throws {
        #expect(TurboQuantPreset(rawValue: "turbo8") == .turbo8)
        #expect(TurboQuantPreset.turbo8.effectiveBits == 8)
        #expect(TurboQuantPreset.turbo8.baseBits == 8)
        #expect(TurboQuantPreset.turbo8.outlierBits == 8)
        #expect(TurboQuantPreset.turbo8.defaultValueBits == 8)

        let encoded = try JSONEncoder().encode(TurboQuantPreset.turbo8)
        let decoded = try JSONDecoder().decode(TurboQuantPreset.self, from: encoded)
        #expect(decoded == .turbo8)
    }

    @Test
    func chatContextPackerAnchorsCurrentUserAndDropsStaleFutureTurns() {
        let anchorID = UUID()
        let staleID = UUID()
        let messages = [
            ChatMessage(role: .system, content: "System instruction"),
            ChatMessage(role: .user, content: "Earlier question"),
            ChatMessage(role: .assistant, content: "Earlier answer"),
            ChatMessage(id: anchorID, role: .user, content: "Current question"),
      ChatMessage(
        id: staleID, role: .assistant, content: "Stale answer after the regenerated turn"),
        ]

        let result = ChatContextPacker.pack(
            messages,
            policy: ChatContextPackingPolicy(
                maxContextTokens: 512,
                reservedCompletionTokens: 64,
                safetyMarginTokens: 64,
                maximumMessages: 16,
                anchorMessageID: anchorID
            )
        )

        #expect(result.messages.contains { $0.id == anchorID })
        #expect(!result.messages.contains { $0.id == staleID })
        #expect(result.summary.droppedMessageCount >= 1)
        #expect(result.summary.providerMetadata[ChatContextMetadataKeys.truncationApplied] == "true")
    }

    @Test
    func chatContextPackerClipsOversizedAnchorWithinBudget() {
        let anchorID = UUID()
        let oversized = String(repeating: "abcd ", count: 2_000)

        let result = ChatContextPacker.pack(
            [ChatMessage(id: anchorID, role: .user, content: oversized)],
            policy: ChatContextPackingPolicy(
                maxContextTokens: 1_024,
                reservedCompletionTokens: 128,
                safetyMarginTokens: 64,
                maximumMessages: 8,
                anchorMessageID: anchorID
            )
        )

        #expect(result.messages.count == 1)
        #expect(result.messages[0].id == anchorID)
        #expect(result.messages[0].content.count < oversized.count)
        #expect(result.summary.clippedMessageCount == 1)
        #expect(result.summary.estimatedInputTokens <= result.summary.inputBudgetTokens)
    }

    @Test
    func chatContextPackerAddsRollingHandoffForDroppedOlderTurns() {
        let anchorID = UUID()
        var messages = [ChatMessage(role: .system, content: "System instruction")]
        for index in 0..<18 {
      messages.append(
        ChatMessage(
          role: .user,
          content: "Earlier user decision \(index): " + String(repeating: "context ", count: 40)))
      messages.append(
        ChatMessage(
          role: .assistant,
          content: "Earlier assistant result \(index): " + String(repeating: "detail ", count: 40)))
        }
        messages.append(ChatMessage(id: anchorID, role: .user, content: "Current question"))

        let result = ChatContextPacker.pack(
            messages,
            policy: ChatContextPackingPolicy(
                maxContextTokens: 1_024,
                reservedCompletionTokens: 128,
                safetyMarginTokens: 64,
                maximumMessages: 12,
                anchorMessageID: anchorID,
                rollingSummaryBudgetTokens: 256
            )
        )

        #expect(result.messages.contains { $0.id == anchorID })
    #expect(
      result.messages.contains {
        $0.role == .system && $0.content.contains("Earlier conversation handoff summary")
      })
        #expect(result.summary.rollingSummaryApplied)
        #expect(result.summary.rollingSummaryMessageCount > 0)
    #expect(
      result.summary.providerMetadata[ChatContextMetadataKeys.rollingSummaryApplied] == "true")
        #expect(result.summary.estimatedInputTokens <= result.summary.inputBudgetTokens)
    }

    @Test
    func chatTranscriptSanitizerDropsIncompleteAssistantRowsFromContinuedChats() {
        let latestUserID = UUID()
        let messages = [
            ChatMessage(role: .user, content: "Earlier question").withPersistedMessageStatus(.complete),
      ChatMessage(role: .assistant, content: "Earlier answer").withPersistedMessageStatus(
        .complete),
            ChatMessage(role: .assistant, content: "").withPersistedMessageStatus(.streaming),
      ChatMessage(role: .assistant, content: "The previous run failed.").withPersistedMessageStatus(
        .failed),
      ChatMessage(id: latestUserID, role: .user, content: "Continue from here")
        .withPersistedMessageStatus(.complete),
        ]

        let result = ChatTranscriptSanitizer.messagesForProviderRequest(
            messages,
            requiredUserMessageIDs: [latestUserID]
        )

        #expect(result.messages.map(\.role) == [.user, .assistant, .user])
    #expect(
      result.messages.map(\.content) == [
        "Earlier question", "Earlier answer", "Continue from here",
      ])
        #expect(result.summary.droppedIncompleteAssistantCount == 2)
        #expect(result.summary.droppedMessageCount == 2)
        #expect(result.summary.providerMetadata[ChatTranscriptMetadataKeys.droppedMessageCount] == "2")
    }

    @Test
    func chatTranscriptSanitizerStripsInternalStatusMetadataBeforeProviderRequest() {
    var assistant = ChatMessage(role: .assistant, content: "Ready.").withPersistedMessageStatus(
      .complete)
        assistant.providerMetadata[CloudProviderMetadataKeys.openAIResponseID] = "resp_123"

        let result = ChatTranscriptSanitizer.messagesForProviderRequest([assistant])

        #expect(result.messages.count == 1)
    #expect(
      result.messages[0].providerMetadata[ChatTranscriptMetadataKeys.persistedMessageStatus] == nil)
    #expect(
      result.messages[0].providerMetadata[CloudProviderMetadataKeys.openAIResponseID] == "resp_123")
    }

    @Test
    func chatTranscriptSanitizerDropsEmptyAssistantButKeepsCurrentAttachmentOnlyUserTurn() {
        let latestUserID = UUID()
        let attachment = ChatAttachment(
            kind: .document,
            fileName: "notes.txt",
            contentType: "text/plain",
            byteCount: 42
        )
        let messages = [
            ChatMessage(role: .assistant, content: "").withPersistedMessageStatus(.complete),
      ChatMessage(id: latestUserID, role: .user, content: "", attachments: [attachment])
        .withPersistedMessageStatus(.complete),
        ]

        let result = ChatTranscriptSanitizer.messagesForProviderRequest(
            messages,
            requiredUserMessageIDs: [latestUserID]
        )

        #expect(result.messages.count == 1)
        #expect(result.messages[0].id == latestUserID)
        #expect(result.messages[0].attachments == [attachment])
        #expect(result.summary.droppedEmptyAssistantCount == 1)
    }

    @Test
    func freezeBreadcrumbJournalIsExplicitlyEnabledForStressRuns() {
        #expect(FreezeBreadcrumbJournal.isEnabled(environment: ["PINES_FREEZE_BREADCRUMBS": "1"]))
    #expect(
      FreezeBreadcrumbJournal.isEnabled(environment: ["PINES_STRESS_MODE": "local-generation"]))
    #expect(
      FreezeBreadcrumbJournal.isEnabled(
        arguments: ["pines", "--pines-stress-local-generation"], environment: [:]))
        #expect(!FreezeBreadcrumbJournal.isEnabled(arguments: ["pines"], environment: [:]))
    }

    @Test
    func freezeBreadcrumbJournalKeepsBoundedJsonlHistory() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pines-freeze-breadcrumb-\(UUID().uuidString)")
            .appendingPathExtension("jsonl")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let journal = FreezeBreadcrumbJournal(fileURL: fileURL, maximumEvents: 2)

        await journal.record(stage: "one", enabled: true)
        await journal.record(stage: "two", enabled: true)
        await journal.record(stage: "three", enabled: true)

        let events = await journal.events()
        #expect(events.map(\.stage) == ["two", "three"])

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.split(separator: "\n").count == 2)
        #expect(contents.contains("\"stage\":\"three\""))
    }

    @Test
    func interruptedChatRunRepairMarksStaleStreamingAssistantMessagesFailed() {
    let streaming = ChatMessage(role: .assistant, content: "").withPersistedMessageStatus(
      .streaming)
        let pendingTool = ChatMessage(
            role: .tool,
            content: "partial",
            toolCallID: "tool_1",
            toolName: "search"
        ).withPersistedMessageStatus(.pending)
    let complete = ChatMessage(role: .assistant, content: "done").withPersistedMessageStatus(
      .complete)

        let repairs = InterruptedChatRunRepair.repairs(
            for: [streaming, pendingTool, complete],
            reason: "app_launch"
        )

        #expect(repairs.count == 2)
        #expect(repairs[0].messageID == streaming.id)
        #expect(repairs[0].status == .failed)
        #expect(repairs[0].content == InterruptedChatRunRepair.defaultInterruptedAssistantMessage)
        #expect(repairs[0].providerMetadata[ChatTranscriptMetadataKeys.persistedMessageStatus] == nil)
    #expect(
      repairs[0].providerMetadata[ChatTranscriptMetadataKeys.interruptedRunOriginalStatus]
        == MessageStatus.streaming.rawValue)
        #expect(repairs[1].toolName == "search")
        #expect(repairs[1].content == "partial")
    #expect(
      repairs[1].providerMetadata[ChatTranscriptMetadataKeys.interruptedRunOriginalStatus]
        == MessageStatus.pending.rawValue)
    }

    @Test
    func inferenceStreamWatchdogFailsWhenFirstEventStalls() async throws {
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

    guard case .finish(let finish)? = events.last else {
            Issue.record("Expected watchdog finish event.")
            return
        }
        #expect(finish.reason == .error)
    #expect(
      finish.providerMetadata[LocalProviderMetadataKeys.generationWatchdogStage]
        == InferenceStreamWatchdogTimeoutStage.firstEvent.rawValue)
    }

    @Test
    func inferenceStreamWatchdogFailsWhenProgressStalls() async throws {
        let source = AsyncThrowingStream<InferenceStreamEvent, Error> { continuation in
            let task = Task {
                do {
                    continuation.yield(.token(TokenDelta(text: "hello", tokenCount: 1)))
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    continuation.yield(.finish(InferenceFinish(reason: .stop)))
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
                firstEventTimeoutSeconds: 1,
                progressTimeoutSeconds: 0.1,
                pollIntervalSeconds: 0.05
            )
        )
        var events = [InferenceStreamEvent]()
        for try await event in guarded {
            events.append(event)
        }

        #expect(events.contains(.token(TokenDelta(text: "hello", tokenCount: 1))))
    guard case .finish(let finish)? = events.last else {
            Issue.record("Expected watchdog finish event.")
            return
        }
        #expect(finish.reason == .error)
    #expect(
      finish.providerMetadata[LocalProviderMetadataKeys.generationWatchdogStage]
        == InferenceStreamWatchdogTimeoutStage.progress.rawValue)
    }

    @Test
    func inferenceStreamWatchdogAllowsHealthyStream() async throws {
        let source = AsyncThrowingStream<InferenceStreamEvent, Error> { continuation in
            continuation.yield(.token(TokenDelta(text: "ok", tokenCount: 1)))
            continuation.yield(.finish(InferenceFinish(reason: .stop)))
            continuation.finish()
        }

        let guarded = InferenceStreamWatchdog.guarded(
            source,
            configuration: InferenceStreamWatchdogConfiguration(
                firstEventTimeoutSeconds: 1,
                progressTimeoutSeconds: 1,
                pollIntervalSeconds: 0.05
            )
        )
        var events = [InferenceStreamEvent]()
        for try await event in guarded {
            events.append(event)
        }

    #expect(
      events == [
            .token(TokenDelta(text: "ok", tokenCount: 1)),
            .finish(InferenceFinish(reason: .stop)),
        ])
    }

    private static func vaultChunk(id: String, documentID: UUID, text: String) -> VaultChunk {
        VaultChunk(
            id: id,
            sourceID: documentID.uuidString,
            ordinal: 0,
            text: text,
            startOffset: 0,
            endOffset: text.count,
            checksum: id
        )
    }

  private static func vaultSearchItem(documentID: UUID, title: String, text: String)
    -> VaultSearchItem
  {
        VaultSearchItem(
            documentID: documentID.uuidString,
            documentTitle: title,
            sourceType: "text",
            chunkID: "\(documentID.uuidString)-0",
            ordinal: 0,
            score: 1,
            snippet: text
        )
    }

    @Test
    func executionRouterDoesNotSilentlyFallbackToCloudInLocalOnlyMode() {
        let decision = ExecutionRouter().routeChat(
            mode: .localOnly,
            local: nil,
            cloud: (
                ProviderID(rawValue: "cloud"),
                ProviderCapabilities(local: false, textGeneration: true, toolCalling: true)
            ),
            requiredInputs: .init(),
            requiresTools: true
        )

    #expect(
      decision.destination
        == .denied(reason: .unsupportedCapability("No local model satisfies this request.")))
    }

    @Test
    func executionRouterPrefersMatchingLocalProvider() {
        let localID = ProviderID(rawValue: "local")
        let decision = ExecutionRouter().routeChat(
            mode: .preferLocal,
            local: (
                localID,
        ProviderCapabilities(
          local: true, textGeneration: true, vision: true, imageInputs: true, toolCalling: true)
            ),
            cloud: (
                ProviderID(rawValue: "cloud"),
        ProviderCapabilities(
          local: false, textGeneration: true, vision: true, imageInputs: true, toolCalling: true)
            ),
            requiredInputs: .init(requiresImages: true),
            requiresTools: true
        )

        #expect(decision.destination == .local(localID))
    }

    @Test
    func executionRouterUsesManagedProOnlyWhenAccessModeAllowsIt() {
        let managedID = ManagedCloudPolicy.providerID
        let byokID = ProviderID(rawValue: "byok")
        let decision = ExecutionRouter().routeChat(
            mode: .cloudAllowed,
            cloudAccessMode: .managedPro,
            local: nil,
            managedCloud: (managedID, ManagedCloudPolicy.defaultCapabilities),
      byokCloud: (
        byokID, ProviderCapabilities(local: false, textGeneration: true, toolCalling: true)
      ),
            requiredInputs: .init(),
            requiresTools: true
        )

        #expect(decision.destination == .cloud(managedID))
    }

    @Test
    func executionRouterDoesNotUseBYOKAsImplicitManagedProFallback() {
        let byokID = ProviderID(rawValue: "byok")
        let decision = ExecutionRouter().routeChat(
            mode: .cloudRequired,
            cloudAccessMode: .managedProWithBYOKOverride,
            local: nil,
            managedCloud: nil,
      byokCloud: (
        byokID, ProviderCapabilities(local: false, textGeneration: true, toolCalling: true)
      ),
            requiredInputs: .init(),
            requiresTools: true
        )

    #expect(
      decision.destination
        == .denied(
          reason: .unsupportedCapability("No configured cloud provider satisfies this request.")))
    }

    @Test
    func executionRouterUsesExplicitBYOKOverrideBeforeManagedPro() {
        let managedID = ManagedCloudPolicy.providerID
        let byokID = ProviderID(rawValue: "byok")
        let decision = ExecutionRouter().routeChat(
            mode: .cloudRequired,
            cloudAccessMode: .managedProWithBYOKOverride,
            local: nil,
            managedCloud: (managedID, ManagedCloudPolicy.defaultCapabilities),
      byokCloud: (
        byokID, ProviderCapabilities(local: false, textGeneration: true, toolCalling: true)
      ),
            requiredInputs: .init(),
            requiresTools: true,
            prefersBYOKOverride: true
        )

        #expect(decision.destination == .cloud(byokID))
    }

    @Test
    func executionRouterKeepsBYOKAvailableForProUsers() {
        let managedID = ManagedCloudPolicy.providerID
        let byokID = ProviderID(rawValue: "byok")
        let decision = ExecutionRouter().routeChat(
            mode: .cloudAllowed,
            cloudAccessMode: .byok,
            local: nil,
            managedCloud: (managedID, ManagedCloudPolicy.defaultCapabilities),
      byokCloud: (
        byokID, ProviderCapabilities(local: false, textGeneration: true, toolCalling: true)
      ),
            requiredInputs: .init(),
            requiresTools: true
        )

        #expect(decision.destination == .cloud(byokID))
    }

    @Test
    func providerInputRequirementsRouteByAttachmentSupport() {
        let imageRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "describe",
          attachments: [
            ChatAttachment(kind: .image, fileName: "image.png", contentType: "image/png")
          ]
        )
            ]
        )
        #expect(imageRequirements.requiresImages)

        let heicRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "describe",
          attachments: [
            ChatAttachment(kind: .image, fileName: "photo.heic", contentType: "image/heic")
          ]
        )
            ]
        )
        #expect(heicRequirements.requiresImages)
    #expect(
      ChatAttachment(kind: .image, fileName: "photo.heif", contentType: "").cloudInputKind == .image
    )
    #expect(
      ChatAttachment(kind: .image, fileName: "sequence.heics", contentType: "")
        .normalizedContentType == "image/heic-sequence")

        let mediaRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "analyze",
                    attachments: [
                        ChatAttachment(kind: .audio, fileName: "clip.mp3", contentType: ""),
                        ChatAttachment(kind: .video, fileName: "scene.mov", contentType: ""),
                    ]
        )
            ]
        )
    #expect(
      ChatAttachment(kind: .audio, fileName: "clip.wav", contentType: "").cloudMediaInputKind
        == .audio)
    #expect(
      ChatAttachment(kind: .video, fileName: "scene.webm", contentType: "").cloudMediaInputKind
        == .video)
        #expect(mediaRequirements.requiresAudio)
        #expect(mediaRequirements.requiresVideo)
    #expect(
      !mediaRequirements.isSatisfied(by: ProviderCapabilities(local: false, audioInputs: true)))
    #expect(
      mediaRequirements.isSatisfied(
        by: ProviderCapabilities(local: false, audioInputs: true, videoInputs: true)))

        let pdfRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "summarize",
          attachments: [
            ChatAttachment(kind: .document, fileName: "doc.pdf", contentType: "application/pdf")
          ]
        )
            ]
        )
        let noPDFDecision = ExecutionRouter().routeChat(
            mode: .cloudRequired,
            local: nil,
            cloud: (
                ProviderID(rawValue: "compat"),
                ProviderCapabilities(local: false, textGeneration: true, imageInputs: true)
            ),
            requiredInputs: pdfRequirements,
            requiresTools: false
        )
        #expect(noPDFDecision.destination == .denied(reason: .cloudNotAllowed))

        let openRouterDecision = ExecutionRouter().routeChat(
            mode: .cloudRequired,
            local: nil,
            cloud: (
                ProviderID(rawValue: "openrouter"),
                ProviderCapabilities(local: false, textGeneration: true, imageInputs: true, pdfInputs: true)
            ),
            requiredInputs: pdfRequirements,
            requiresTools: false
        )
        #expect(openRouterDecision.destination == .cloud(ProviderID(rawValue: "openrouter")))

        let textRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "summarize",
          attachments: [
            ChatAttachment(kind: .document, fileName: "notes.md", contentType: "text/markdown")
          ]
        )
            ]
        )
    #expect(
      !textRequirements.isSatisfied(
        by: ProviderCapabilities(local: false, imageInputs: true, pdfInputs: true)))
    }

    @Test
    func conversationTitleDeriverNamesPlaceholderChatsFromUserContent() {
        let messages = [
            ChatMessage(role: .assistant, content: "Sure."),
            ChatMessage(
                role: .user,
        content:
          "Can we properly derive chat titles from chat conversation content? So chats are not just new chat."
            ),
        ]

        let title = ConversationTitleDeriver.title(forStoredTitle: "New chat", messages: messages)

        #expect(title == "Properly Derive Chat Titles from Chat Conversation Content")
    }

    @Test
    func conversationTitleDeriverKeepsManualTitles() {
        let title = ConversationTitleDeriver.title(
            forStoredTitle: "Release planning",
            messages: [ChatMessage(role: .user, content: "Can you summarize this release plan?")]
        )

        #expect(title == "Release planning")
    }

    @Test
    func conversationTitleDeriverUsesAttachmentNamesForGenericPrompts() {
        let title = ConversationTitleDeriver.title(
            from: [
                ChatMessage(
                    role: .user,
                    content: "Analyze the attached file.",
                    attachments: [
            ChatAttachment(
              kind: .document, fileName: "meeting_notes.md", contentType: "text/markdown")
                    ]
        )
            ]
        )

        #expect(title == "Meeting Notes")
    }

    @Test
    func cloudProviderCapabilitiesMatchAttachmentSupportMatrix() {
        let openAI = cloudConfiguration(kind: .openAI, baseURL: "https://api.openai.com/v1")
        #expect(openAI.capabilities.imageInputs)
        #expect(openAI.capabilities.pdfInputs)
        #expect(openAI.capabilities.textDocumentInputs)
        #expect(openAI.capabilities.embeddings)

        let anthropic = cloudConfiguration(kind: .anthropic, baseURL: "https://api.anthropic.com")
        #expect(anthropic.capabilities.imageInputs)
        #expect(anthropic.capabilities.pdfInputs)
        #expect(anthropic.capabilities.textDocumentInputs)
        #expect(anthropic.capabilities.files)
        #expect(anthropic.capabilities.hostedTools)
        #expect(anthropic.capabilities.structuredOutputs)
        #expect(anthropic.capabilities.contextCache)
        #expect(anthropic.capabilities.batch)
        #expect(anthropic.capabilities.tokenCounting)
        #expect(anthropic.capabilities.modelCapabilities.contains(.contextCache))
        #expect(anthropic.capabilities.modelCapabilities.contains(.batch))
        #expect(anthropic.capabilities.modelCapabilities.contains(.tokenCounting))
        #expect(!anthropic.capabilities.embeddings)

    let gemini = cloudConfiguration(
      kind: .gemini, baseURL: "https://generativelanguage.googleapis.com")
        #expect(gemini.capabilities.imageInputs)
        #expect(gemini.capabilities.audioInputs)
        #expect(gemini.capabilities.videoInputs)
        #expect(gemini.capabilities.pdfInputs)
        #expect(gemini.capabilities.textDocumentInputs)
        #expect(gemini.capabilities.files)
        #expect(gemini.capabilities.embeddings)
        #expect(gemini.capabilities.structuredOutputs)
        #expect(gemini.capabilities.hostedTools)
        #expect(gemini.capabilities.contextCache)
        #expect(gemini.capabilities.live)
        #expect(gemini.capabilities.batch)
        #expect(gemini.capabilities.tokenCounting)
        #expect(gemini.capabilities.modelCapabilities.contains(.contextCache))

        let openRouter = cloudConfiguration(kind: .openRouter, baseURL: "https://openrouter.ai/api/v1")
        #expect(openRouter.capabilities.imageInputs)
        #expect(openRouter.capabilities.pdfInputs)
        #expect(!openRouter.capabilities.textDocumentInputs)
        #expect(openRouter.capabilities.embeddings)

        let voyage = cloudConfiguration(kind: .voyageAI, baseURL: "https://api.voyageai.com/v1")
        #expect(!voyage.capabilities.textGeneration)
        #expect(voyage.capabilities.embeddings)

    let compatible = cloudConfiguration(
      kind: .openAICompatible, baseURL: "https://llm.example.test/v1")
        #expect(!compatible.capabilities.imageInputs)
        #expect(!compatible.capabilities.pdfInputs)
        #expect(!compatible.capabilities.textDocumentInputs)

        let customOpenAIHost = cloudConfiguration(kind: .custom, baseURL: "https://api.openai.com/v1")
        #expect(customOpenAIHost.capabilities.imageInputs)
        #expect(customOpenAIHost.capabilities.pdfInputs)
        #expect(customOpenAIHost.capabilities.textDocumentInputs)
        #expect(customOpenAIHost.capabilities.files)
    }

    @Test
    func providerCapabilitiesDecodeMissingGeminiParityFieldsWithDefaults() throws {
        let legacy = """
        {
          "local": false,
          "streaming": true,
          "textGeneration": true,
          "jsonMode": true
        }
        """

        let capabilities = try JSONDecoder().decode(ProviderCapabilities.self, from: Data(legacy.utf8))

        #expect(capabilities.structuredOutputs)
        #expect(!capabilities.files)
        #expect(!capabilities.audioInputs)
        #expect(!capabilities.videoInputs)
        #expect(!capabilities.contextCache)
        #expect(!capabilities.live)
        #expect(!capabilities.batch)
        #expect(!capabilities.tokenCounting)
    }

    @Test
    func vaultEmbeddingProfilesUseStableProviderScopedIDsAndDefaults() {
        let openAI = cloudConfiguration(kind: .openAI, baseURL: "https://api.openai.com/v1")
        let openAIProfile = VaultEmbeddingProfile.cloud(provider: openAI)
        #expect(openAIProfile?.modelID == ModelID(rawValue: "text-embedding-3-small"))
        #expect(openAIProfile?.dimensions == 1536)
        #expect(openAIProfile?.kind == .openAI)

    let gemini = cloudConfiguration(
      kind: .gemini, baseURL: "https://generativelanguage.googleapis.com")
        let geminiProfile = VaultEmbeddingProfile.cloud(provider: gemini)
        #expect(geminiProfile?.modelID == ModelID(rawValue: "gemini-embedding-2"))
        #expect(geminiProfile?.dimensions == 768)
        #expect(geminiProfile?.documentTask == "title: none | text: {content}")
        #expect(geminiProfile?.queryTask == "task: search result | query: {content}")

        let anthropic = cloudConfiguration(kind: .anthropic, baseURL: "https://api.anthropic.com")
        #expect(VaultEmbeddingProfile.cloud(provider: anthropic) == nil)

        let openRouter = cloudConfiguration(kind: .openRouter, baseURL: "https://openrouter.ai/api/v1")
        let openRouterProfile = VaultEmbeddingProfile.cloud(provider: openRouter)
        #expect(openRouterProfile?.modelID == ModelID(rawValue: "openai/text-embedding-3-small"))
        #expect(openRouterProfile?.queryTask == "search_query")

        let voyage = cloudConfiguration(kind: .voyageAI, baseURL: "https://api.voyageai.com/v1")
        let voyageProfile = VaultEmbeddingProfile.cloud(provider: voyage)
        #expect(voyageProfile?.modelID == ModelID(rawValue: "voyage-4-lite"))
        #expect(voyageProfile?.dimensions == 1024)
        #expect(voyageProfile?.queryTask == "query")
    }

    @Test
    func cloudEmbeddingRequestBuilderUsesProviderSpecificEmbeddingSemantics() throws {
        let builder = CloudEmbeddingRequestBuilder()

        let openRouter = builder.openAICompatibleBody(
            providerKind: .openRouter,
            modelID: "openai/text-embedding-3-small",
            inputs: ["chunk"],
            dimensions: 1536,
            inputType: .document
        )
        let openRouterObject = try #require(openRouter.objectValue)
        #expect(openRouterObject["model"] == .string("openai/text-embedding-3-small"))
        #expect(openRouterObject["dimensions"] == .number(1536))
        #expect(openRouterObject["input_type"] == .string("search_document"))

        let gemini = builder.geminiBatchBody(
            modelID: "gemini-embedding-2",
            inputs: ["find invoices"],
            dimensions: 768,
            inputType: .query
        )
        #expect(gemini.modelName == "models/gemini-embedding-2")
        let geminiObject = try #require(gemini.body.objectValue)
        let geminiRequests = try #require(geminiObject["requests"])
    guard case .array(let requestArray) = geminiRequests,
      case .object(let firstRequest) = requestArray.first,
      case .object(let content) = firstRequest["content"],
      case .array(let parts) = content["parts"],
      case .object(let firstPart) = parts.first
        else {
            Issue.record("Gemini embedding request body did not have the expected shape.")
            return
        }
        #expect(firstRequest["taskType"] == nil)
        #expect(firstRequest["output_dimensionality"] == .number(768))
        #expect(firstPart["text"] == .string("task: search result | query: find invoices"))

        let voyage = builder.voyageBody(
            modelID: "voyage-4-lite",
            inputs: ["chunk"],
            dimensions: 1024,
            inputType: .query
        )
        let voyageObject = try #require(voyage.objectValue)
        #expect(voyageObject["input_type"] == .string("query"))
        #expect(voyageObject["output_dimension"] == .number(1024))
    }

    @Test
    func redactorRemovesCommonCredentialShapes() {
        let openAIKey = "sk-" + "1234567890abcdef"
        let huggingFaceKey = "hf_" + "1234567890abcdef"
        let bearerToken = "Bearer " + "abcdefghijklmnop"
    let jwt =
      "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwZW5lcyJ9.TJVA95OrM7E2cBab30RMHrHDcEfxjoYZgeFONFh7HgQ"
        let cookie = "Cookie: session=abcdef1234567890"
        let pemKind = "PRIVATE KEY"
        let pem = """
        -----BEGIN \(pemKind)-----
        abcdefghijklmnopqrstuvwxyz1234567890
        -----END \(pemKind)-----
        """
        let generic = String(repeating: "a", count: 48)
    let text =
      "openai=\(openAIKey) hf=\(huggingFaceKey) bearer=\(bearerToken) jwt=\(jwt) \(cookie) \(pem) generic=\(generic)"
        let redacted = Redactor().redact(text)

        #expect(!redacted.contains(openAIKey))
        #expect(!redacted.contains(huggingFaceKey))
        #expect(!redacted.contains(bearerToken))
        #expect(!redacted.contains(jwt))
        #expect(!redacted.contains(cookie))
        #expect(!redacted.contains("BEGIN \(pemKind)"))
        #expect(!redacted.contains(generic))
        #expect(redacted.contains("[redacted-key]"))
        #expect(redacted.contains("Bearer [redacted-token]"))
        #expect(redacted.contains("[redacted-jwt]"))
        #expect(redacted.contains("[redacted-private-key]"))
    }

    @Test
    func endpointSecurityPolicyAllowsOnlyHTTPSOrExplicitLoopbackHTTP() throws {
        let policy = EndpointSecurityPolicy()

        try policy.validate(URL(string: "https://api.example.test/v1")!, useCase: .cloudProvider)
        try policy.validate(
            URL(string: "http://localhost:11434")!,
            useCase: .mcpEndpoint,
            allowsExplicitLocalHTTP: true
        )
        try policy.validate(
            URL(string: "http://127.0.0.1:8080")!,
            useCase: .mcpEndpoint,
            allowsExplicitLocalHTTP: true
        )
        try policy.validate(
            URL(string: "http://[::1]:8080")!,
            useCase: .mcpEndpoint,
            allowsExplicitLocalHTTP: true
        )

        #expect(throws: EndpointSecurityError.self) {
            try policy.validate(URL(string: "http://api.example.test/v1")!, useCase: .cloudProvider)
        }
        #expect(throws: EndpointSecurityError.self) {
            try policy.validate(
                URL(string: "http://localhost:11434")!,
                useCase: .mcpEndpoint,
                allowsExplicitLocalHTTP: false
            )
        }
        #expect(throws: EndpointSecurityError.self) {
            try policy.validate(
                URL(string: "http://192.168.1.10:8080")!,
                useCase: .mcpEndpoint,
                allowsExplicitLocalHTTP: true
            )
        }

        for target in [
            "https://localhost/admin",
            "https://127.0.0.1/admin",
            "https://10.0.0.1/admin",
            "https://169.254.169.254/latest/meta-data",
            "https://192.168.1.10/admin",
            "https://[::1]/admin",
            "https://service.local/admin",
        ] {
            #expect(throws: EndpointSecurityError.self) {
                try policy.validate(URL(string: target)!, useCase: .webTool)
            }
        }
        try policy.validate(URL(string: "https://example.com/article")!, useCase: .webTool)
        #expect(EndpointSecurityPolicy.isSameOrigin(
            URL(string: "https://example.com/a")!,
            URL(string: "https://EXAMPLE.com:443/b")!
        ))
        #expect(!EndpointSecurityPolicy.isSameOrigin(
            URL(string: "https://example.com/a")!,
            URL(string: "https://other.example.com/b")!
        ))
        #expect(!EndpointSecurityPolicy.isSameOrigin(
            URL(string: "https://example.com/a")!,
            URL(string: "https://example.com:8443/b")!
        ))
    }

    @Test
    func cloudProviderHeadersClassifySecretNames() {
        #expect(CloudProviderHeader.isSecretLikeName("Authorization"))
        #expect(CloudProviderHeader.isSecretLikeName("X-Api-Key"))
        #expect(CloudProviderHeader.isSecretLikeName("x-session-token"))
        #expect(CloudProviderHeader.isSecretLikeName("Cookie"))
        #expect(!CloudProviderHeader.isSecretLikeName("X-Trace-ID"))

    #expect(
      CloudProviderHeader(name: "Authorization", kind: .publicValue, value: "Bearer test")
        .storesSecretInPlaintext)
    #expect(
      !CloudProviderHeader(name: "X-Trace-ID", kind: .publicValue, value: "trace")
        .storesSecretInPlaintext)
    #expect(
      !CloudProviderHeader(
        name: "Authorization", kind: .secretReference, keychainService: "svc",
        keychainAccount: "acct"
      ).storesSecretInPlaintext)
    }

    @Test
    func installBoundSecretEnvelopeRequiresSameInstallKeyAndContext() throws {
        let installKey = Data(repeating: 0x11, count: InstallBoundSecretEnvelope.installKeyByteCount)
    let otherInstallKey = Data(
      repeating: 0x22, count: InstallBoundSecretEnvelope.installKeyByteCount)
        let plaintext = Data("sk-test-secret".utf8)
        let sealed = try InstallBoundSecretEnvelope.seal(
            plaintext,
            installKey: installKey,
            context: "com.schtack.pines.cloud::openai"
        )

        #expect(InstallBoundSecretEnvelope.isEnvelope(sealed))
    #expect(
      try InstallBoundSecretEnvelope.open(
            sealed,
            installKey: installKey,
            context: "com.schtack.pines.cloud::openai"
        ) == plaintext)
        #expect(throws: InstallBoundSecretEnvelopeError.authenticationFailed) {
            try InstallBoundSecretEnvelope.open(
                sealed,
                installKey: otherInstallKey,
                context: "com.schtack.pines.cloud::openai"
            )
        }
        #expect(throws: InstallBoundSecretEnvelopeError.authenticationFailed) {
            try InstallBoundSecretEnvelope.open(
                sealed,
                installKey: installKey,
                context: "com.schtack.pines.cloud::anthropic"
            )
        }
    }

    @Test
    func securityConfigurationDefaultsToEncryptedE2EModel() {
        let configuration = SecurityConfiguration()

        #expect(!configuration.appLockEnabled)
    #expect(
      configuration.encryptedStoreVersion == SecurityConfiguration.currentEncryptedStoreVersion)
        #expect(configuration.cloudKitE2EEnabled)
        #expect(configuration.securityResetCompletedAt == nil)
    }

    @Test
    func openAIReasoningChatRequestsUseCompatibleTokenParameters() throws {
        let request = ChatRequest(
            modelID: "gpt-5.5",
            messages: [ChatMessage(role: .user, content: "Hello")],
      sampling: ChatSampling(
        maxTokens: 256, temperature: 0.6, topP: 1, openAIReasoningEffort: .high,
        openAITextVerbosity: .medium)
        )

        let urlRequest = try OpenAICompatibleRequestBuilder().chatRequest(
            baseURL: URL(string: "https://api.openai.com")!,
            apiKey: "test",
            request: request
        )
        let body = try #require(urlRequest.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(urlRequest.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(json["max_completion_tokens"] as? Int == 16_384)
        #expect(json["max_tokens"] == nil)
        #expect(json["reasoning_effort"] as? String == "high")
        #expect(json["verbosity"] as? String == "medium")
        #expect((json["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
    }

    @Test
    func openAIReasoningEffortNormalizesModelSpecificValues() {
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5.5", requested: .xhigh)
        == .xhigh)
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5.5-pro", requested: .low)
        == .high)
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5", requested: .none) == .low)
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5", requested: .xhigh) == .low)
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5.1", requested: .none) == .none
    )
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.5") == [
        .none, .minimal, .low, .medium, .high, .xhigh,
      ])
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.4") == [
        .none, .minimal, .low, .medium, .high, .xhigh,
      ])
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5") == [
        .minimal, .low, .medium, .high,
      ])
    #expect(
      CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.5-pro") == [.high])
        #expect(!CloudProviderModelEligibility.supportsOpenAITextVerbosity(modelID: "gpt-4o"))
    }

    @Test
    func openAIChatCompletionsParserPreservesMetadataAndUsage() {
        var parser = CloudProviderStreamParser()
    parser.recordRequestMetadata(
      providerKind: .openAI, serverRequestID: "req_header", clientRequestID: "client_1")
        let payloads = [
            #"{"id":"chatcmpl_1","object":"chat.completion.chunk","model":"gpt-4.1","system_fingerprint":"fp_123","choices":[{"index":0,"delta":{"content":"hi"},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl_1","object":"chat.completion.chunk","model":"gpt-4.1","choices":[],"usage":{"prompt_tokens":7,"completion_tokens":2,"total_tokens":9}}"#,
            #"{"id":"chatcmpl_1","object":"chat.completion.chunk","model":"gpt-4.1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
        ]

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for payload in payloads {
      let output = parser.parse(
        data: Data(payload.utf8), format: .chatCompletions, providerKind: .openAI)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "hi", tokenCount: 1))))
        #expect(events.contains(.metrics(InferenceMetrics(promptTokens: 7, completionTokens: 2))))
        #expect(finish?.reason == .stop)
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIRequestID] == "req_header")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIClientRequestID] == "client_1")
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.openAIChatCompletionID] == "chatcmpl_1")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIModel] == "gpt-4.1")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAISystemFingerprint] == "fp_123")
    }

    @Test
    func cloudProviderModelControlsMatchAnthropicAndGeminiCapabilities() {
        #expect(CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: "claude-opus-4-7"))
        #expect(CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: "claude-opus-4-6"))
    #expect(
      CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: "claude-sonnet-4-6"))
    #expect(
      !CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: "claude-opus-4-5"))
    #expect(
      CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-opus-4-7") == [
        .low, .medium, .high, .xhigh, .max,
      ])
    #expect(
      CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-opus-4-6") == [
        .low, .medium, .high, .max,
      ])
    #expect(
      CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-sonnet-4-6") == [
        .low, .medium, .high, .max,
      ])
    #expect(
      CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-opus-4-5") == [
        .low, .medium, .high,
      ])
        #expect(CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-sonnet-4-5").isEmpty)
    #expect(
      CloudProviderModelEligibility.anthropicEffort(for: "claude-sonnet-4-6", requested: .xhigh)
        == .high)
    #expect(
      CloudProviderModelEligibility.anthropicThinkingModes(for: "claude-sonnet-4-6") == [
        .off, .adaptive, .budgeted, .effort,
      ])
    #expect(
      CloudProviderModelEligibility.anthropicThinkingModes(for: "claude-opus-4-5") == [
        .off, .budgeted, .effort,
      ])
        let clampedAnthropicThinking = CloudProviderModelEligibility.anthropicThinkingOptions(
            for: "claude-sonnet-4-6",
            requested: AnthropicThinkingOptions(mode: .effort, effort: .xhigh)
        )
        #expect(clampedAnthropicThinking.effort == .high)

    #expect(
      CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "models/gemini-3.1-pro-preview")
        == [.low, .medium, .high])
    #expect(
      CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "models/gemini-3.1-flash-lite")
        == [.minimal, .low, .medium, .high])
    #expect(
      CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "gemini-3-flash-preview") == [
        .minimal, .low, .medium, .high,
      ])
        #expect(CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "gemini-2.5-pro").isEmpty)
    #expect(
      CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "gemini-2.0-flash").isEmpty)
    #expect(
      CloudProviderModelEligibility.geminiThinkingLevel(
        for: "gemini-3.1-pro-preview", requested: .minimal) == .low)
    }

    @Test
    func openAICompatibleRequestBuilderSerializesImageAttachmentsAndRejectsDocuments() throws {
        let imageURL = FileManager.default.temporaryDirectory.appending(path: "pines-test-image.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let request = ChatRequest(
            modelID: "gpt-test",
            messages: [
                ChatMessage(
                    role: .user,
                    content: "Describe",
                    attachments: [
            ChatAttachment(
              kind: .image, fileName: "pines-test-image.png", contentType: "image/png",
              localURL: imageURL)
                    ]
        )
            ]
        )
        let urlRequest = try OpenAICompatibleRequestBuilder().chatRequest(
            baseURL: URL(string: "https://api.example.test/v1")!,
            apiKey: "test",
            request: request
        )
        let body = try #require(urlRequest.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])

        #expect(content.contains { $0["type"] as? String == "image_url" })
        let imagePart = try #require(content.first { $0["type"] as? String == "image_url" })
        let imageURLObject = try #require(imagePart["image_url"] as? [String: Any])
        #expect((imageURLObject["url"] as? String)?.hasPrefix("data:image/png;base64,") == true)

        let pdfRequest = ChatRequest(
            modelID: "gpt-test",
            messages: [
                ChatMessage(
                    role: .user,
                    content: "Summarize",
                    attachments: [
            ChatAttachment(
              kind: .document, fileName: "doc.pdf", contentType: "application/pdf",
              localURL: imageURL)
                    ]
        )
            ]
        )
        #expect(throws: InferenceError.self) {
            _ = try OpenAICompatibleRequestBuilder().chatRequest(
                baseURL: URL(string: "https://api.example.test/v1")!,
                apiKey: "test",
                request: pdfRequest
            )
        }
    }

    @Test
    func cloudModelEligibilityEnforcesCuratedAgentModelPolicy() {
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.5", providerKind: .openAI))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.5-pro", providerKind: .openAI))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
        id: "gpt-5.5-2026-04-23", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.4", providerKind: .openAI))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
        id: "gpt-5.4-2026-03-05", providerKind: .openAI))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.4-mini", providerKind: .openAI))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
        id: "gpt-5.4-nano-2026-03-17", providerKind: .openAI))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.6-mini", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-6", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5", providerKind: .openAI))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5-mini", providerKind: .openAI))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(id: "gpt-4.1-mini", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "gpt-4o", providerKind: .openAI))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "chatgpt-4o-latest", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o1", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o3", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o4-mini", providerKind: .openAI))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "openai/o3-mini", providerKind: .openRouter))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "openai/gpt-4.1", providerKind: .openRouter))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(id: "openai/gpt-6", providerKind: .openRouter)
    )
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
        id: "meta/llama-4-maverick", providerKind: .openRouter))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "text-embedding-3-large", providerKind: .openAI))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(id: "gpt-image-2", providerKind: .openAI))

    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
        id: "claude-opus-4-7", providerKind: .anthropic))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
        id: "claude-sonnet-4-6", providerKind: .anthropic))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
        id: "claude-haiku-4-5-20251001", providerKind: .anthropic))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(id: "claude-opus-5", providerKind: .anthropic)
    )
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "claude-opus-4-6", providerKind: .anthropic))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "claude-sonnet-4-5", providerKind: .anthropic))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "claude-3-7-sonnet-20250219", providerKind: .anthropic))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "anthropic/claude-sonnet-4-5", providerKind: .openRouter))

    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3.1-pro-preview",
            providerKind: .gemini,
            supportedGenerationMethods: ["createInteraction"]
        ))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3-flash-preview",
            providerKind: .gemini,
            supportedGenerationMethods: ["createInteraction"]
        ))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3.1-flash-lite",
            providerKind: .gemini,
            supportedGenerationMethods: ["generateContent"]
        ))
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-4-pro",
            providerKind: .gemini,
            supportedGenerationMethods: ["generateContent"]
        ))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3-pro-preview",
            providerKind: .gemini,
            supportedGenerationMethods: ["generateContent"]
        ))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-2.5-pro",
            providerKind: .gemini,
            supportedGenerationMethods: ["generateContent"]
        ))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
        id: "google/gemini-2.5-pro", providerKind: .openRouter))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
            id: "models/text-embedding-004",
            providerKind: .gemini,
            supportedGenerationMethods: ["embedContent"]
        ))
    }

    @Test
    func geminiModelEligibilityAcceptsInteractionsModels() {
    #expect(
      CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3-flash-preview",
            providerKind: .gemini,
            supportedGenerationMethods: ["createInteraction"]
        ))
    #expect(
      !CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3-flash-preview",
            providerKind: .gemini,
            supportedGenerationMethods: []
        ))
    }

    @Test
    func cloudProviderCapabilitiesAreProviderSpecific() {
        let custom = CloudProviderConfiguration(
            id: "custom",
            kind: .custom,
            displayName: "Custom",
            baseURL: URL(string: "https://example.com")!,
            keychainAccount: "custom"
        )
        let anthropic = CloudProviderConfiguration(
            id: "anthropic",
            kind: .anthropic,
            displayName: "Anthropic",
            baseURL: URL(string: "https://api.anthropic.com")!,
            keychainAccount: "anthropic"
        )
        let gemini = CloudProviderConfiguration(
            id: "gemini",
            kind: .gemini,
            displayName: "Gemini",
            baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
            keychainAccount: "gemini"
        )

        #expect(!custom.capabilities.imageInputs)
        #expect(!custom.capabilities.pdfInputs)
        #expect(!custom.capabilities.toolCalling)
        #expect(anthropic.capabilities.imageInputs)
        #expect(anthropic.capabilities.pdfInputs)
        #expect(gemini.capabilities.imageInputs)
        #expect(gemini.capabilities.textDocumentInputs)
    }

    @Test
    func anthropicStreamParserEmitsTextToolMetricsAndThinkingMetadata() throws {
        var parser = CloudProviderStreamParser()
    parser.recordRequestMetadata(
      providerKind: .anthropic, serverRequestID: "req_123", clientRequestID: nil)

        var allEvents = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for payload in [
            #"{"type":"message_start","message":{"id":"msg_123","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"cache_read_input_tokens":4,"cache_creation_input_tokens":2}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"plan"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig_123"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":"","citations":[{"type":"page_location","file_id":"file_pdf","title":"Spec","start_page_number":3,"cited_text":"quoted"}]}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"hello"}}"#,
            #"{"type":"content_block_start","index":3,"content_block":{"type":"server_tool_use","id":"srv_1","name":"web_fetch","input":{"url":"https://example.com"}}}"#,
            #"{"type":"content_block_stop","index":3}"#,
            #"{"type":"content_block_start","index":4,"content_block":{"type":"web_fetch_tool_result","tool_use_id":"srv_1","content":[{"type":"document","title":"Example","url":"https://example.com"}]}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"tool_1","name":"lookup","input":{}}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"q\":\"pines\"}"}}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":3}}"#,
        ] {
      let output = parser.parse(
        data: Data(payload.utf8), format: .anthropicMessages, providerKind: .anthropic)
            allEvents.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(allEvents.contains(.token(TokenDelta(kind: .token, text: "hello", tokenCount: 1))))
        #expect(allEvents.contains(.metrics(InferenceMetrics(promptTokens: 16, completionTokens: 0))))
        #expect(allEvents.contains(.metrics(InferenceMetrics(promptTokens: 0, completionTokens: 3))))
    #expect(
      allEvents.contains(
        .toolCall(
          ToolCallDelta(
            id: "tool_1", name: "lookup", argumentsFragment: #"{"q":"pines"}"#, isComplete: true))))
        #expect(finish?.reason == .toolCall)
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.anthropicRequestID] == "req_123")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.anthropicMessageID] == "msg_123")
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.anthropicThinkingContentJSON]?.contains(
        "sig_123") == true)
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.anthropicCacheReadInputTokens] == "4")
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.anthropicCacheCreationInputTokens] == "2")
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.anthropicHostedToolCallsJSON]?.contains(
        "srv_1") == true)
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.providerCitationsJSON]?.contains(
        "file_pdf") == true)
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.webSearchCitationsJSON]?.contains(
        "example.com") == true)
    }

    @Test
    func geminiGenerateContentParserPreservesModelContentAndToolCalls() {
        var parser = CloudProviderStreamParser()
        let payload = """
        {
          "responseId": "resp_1",
          "modelVersion": "gemini-2.5-flash",
          "usageMetadata": { "promptTokenCount": 7, "candidatesTokenCount": 5 },
          "candidates": [{
            "content": {
              "role": "model",
              "parts": [
                { "text": "visible" },
                { "thought": true, "thoughtSignature": "thought_sig" },
                { "functionCall": { "id": "call_1", "name": "lookup", "args": { "q": "pines" } } }
              ]
            },
            "finishReason": "STOP"
          }]
        }
        """

    let output = parser.parse(
      data: Data(payload.utf8), format: .geminiGenerateContent, providerKind: .gemini)

    #expect(
      output.events.contains(.token(TokenDelta(kind: .token, text: "visible", tokenCount: 1))))
    #expect(
      output.events.contains(.metrics(InferenceMetrics(promptTokens: 7, completionTokens: 5))))
    #expect(
      output.events.contains(
        .toolCall(
          ToolCallDelta(
            id: "call_1", name: "lookup", argumentsFragment: #"{"q":"pines"}"#, isComplete: true))))
        #expect(output.finish?.reason == .toolCall)
        #expect(output.finish?.providerMetadata[CloudProviderMetadataKeys.geminiResponseID] == "resp_1")
    #expect(
      parser.state.geminiProviderMetadata[CloudProviderMetadataKeys.geminiModelContentJSON]?
        .contains("thought_sig") == true)
    }

    @Test
    func geminiInteractionsParserHandlesStreamingTextToolCallsAndUsage() {
        var parser = CloudProviderStreamParser()
        let payloads = [
            #"{"event_type":"interaction.created","interaction":{"id":"ia_1","model":"gemini-3-flash-preview","status":"in_progress"}}"#,
            #"{"event_type":"step.delta","index":0,"delta":{"type":"text","text":"hello"}}"#,
            #"{"event_type":"step.start","index":1,"step":{"type":"function_call","id":"fn_1","name":"lookup","arguments":{"q":"pines"}}}"#,
            #"{"event_type":"step.stop","index":1}"#,
            #"{"event_type":"interaction.completed","interaction":{"id":"ia_1","model":"gemini-3-flash-preview","status":"completed","usage":{"total_input_tokens":11,"total_output_tokens":4}}}"#,
        ]

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for payload in payloads {
      let output = parser.parse(
        data: Data(payload.utf8), format: .geminiInteractions, providerKind: .gemini)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "hello", tokenCount: 1))))
    #expect(
      events.contains(
        .toolCall(
          ToolCallDelta(
            id: "fn_1", name: "lookup", argumentsFragment: #"{"q":"pines"}"#, isComplete: true))))
        #expect(events.contains(.metrics(InferenceMetrics(promptTokens: 11, completionTokens: 4))))
        #expect(finish?.reason == .toolCall)
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.geminiInteractionID] == "ia_1")
    }

    @Test
    func geminiInteractionsParserAcceptsGuideStreamingAliases() {
        var parser = CloudProviderStreamParser()
        let payloads = [
            #"{"event_type":"interaction.created","interaction":{"id":"ia_2","model":"gemini-3-flash-preview","status":"in_progress"}}"#,
            #"{"event_type":"content.delta","delta":{"type":"text","text":"alias"}}"#,
            #"{"event_type":"interaction.complete","interaction":{"id":"ia_2","model":"gemini-3-flash-preview","status":"completed","usage":{"total_input_tokens":2,"total_output_tokens":1}}}"#,
        ]

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for payload in payloads {
      let output = parser.parse(
        data: Data(payload.utf8), format: .geminiInteractions, providerKind: .gemini)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "alias", tokenCount: 1))))
        #expect(events.contains(.metrics(InferenceMetrics(promptTokens: 2, completionTokens: 1))))
        #expect(finish?.reason == .stop)
    }

    @Test
    func geminiParserCapturesToolFileCacheAndArtifactMetadata() {
        var parser = CloudProviderStreamParser()
        let payload = """
        {
          "responseId": "resp_meta",
          "usageMetadata": {
            "promptTokenCount": 20,
            "candidatesTokenCount": 4,
            "cachedContentTokenCount": 12,
            "thoughtsTokenCount": 3
          },
          "candidates": [{
            "content": {
              "role": "model",
              "parts": [
                { "executableCode": { "language": "PYTHON", "code": "print(1)" } },
                { "codeExecutionResult": { "outcome": "OUTCOME_OK", "output": "1" } },
                { "fileData": { "mimeType": "audio/mpeg", "fileUri": "https://files.example/audio" } },
                { "inlineData": { "mimeType": "image/png", "data": "abcd" } }
              ]
            },
            "urlContextMetadata": { "urlMetadata": [{ "retrievedUrl": "https://example.com" }] },
            "finishReason": "STOP"
          }]
        }
        """

    let output = parser.parse(
      data: Data(payload.utf8), format: .geminiGenerateContent, providerKind: .gemini)
        let metadata = output.finish?.providerMetadata ?? parser.state.geminiProviderMetadata

    #expect(
      metadata[CloudProviderMetadataKeys.geminiCacheUsageJSON]?.contains("cachedContentTokenCount")
        == true)
    #expect(
      metadata[CloudProviderMetadataKeys.geminiCodeExecutionJSON]?.contains("OUTCOME_OK") == true)
    #expect(
      metadata[CloudProviderMetadataKeys.geminiURLContextJSON]?.contains("example.com") == true)
        #expect(metadata[CloudProviderMetadataKeys.geminiFileReferencesJSON]?.contains("audio") == true)
        #expect(metadata[CloudProviderMetadataKeys.geminiArtifactsJSON]?.contains("image") == true)
    }

    @Test
    func geminiProviderRecordFixtureMaterializesLifecycleRecords() throws {
        let providerID = ProviderID(rawValue: "gemini")
        let modelID = ModelID(rawValue: "gemini-3.1-pro-preview")
        let file = GeminiProviderLifecycleRecordMapperFixture.providerFile(
            from: .object([
                "name": .string("files/audio_123"),
                "displayName": .string("meeting.mp3"),
                "mimeType": .string("audio/mpeg"),
                "sizeBytes": .string("4096"),
                "state": .string("ACTIVE"),
                "uri": .string("https://generativelanguage.googleapis.com/v1beta/files/audio_123"),
                "sha256Hash": .string("abc123"),
                "metadata": .object(["workspace": .string("pines"), "transient": .bool(true)]),
            ]),
            providerID: providerID
        )
        let cache = GeminiProviderLifecycleRecordMapperFixture.providerCache(
            from: .object([
                "name": .string("cachedContents/cache_123"),
                "model": .string("models/gemini-3.1-pro-preview"),
                "displayName": .string("Research cache"),
                "usageMetadata": .object([
                    "totalTokenCount": .number(2048),
                    "cachedContentTokenCount": .number(1536),
                ]),
                "metadata": .object(["purpose": .string("research")]),
            ]),
            providerID: providerID
        )
        let batch = GeminiProviderLifecycleRecordMapperFixture.providerBatch(
            from: .object([
                "name": .string("batches/batch_123"),
                "state": .string("JOB_STATE_RUNNING"),
                "endpoint": .string("models/gemini-3.1-pro-preview:batchGenerateContent"),
                "inputConfig": .object(["fileName": .string("files/input_123")]),
                "outputInfo": .object(["fileName": .string("files/output_123")]),
                "metadata": .object(["trace": .string("batch")]),
            ]),
            providerID: providerID
        )
        let live = GeminiProviderLifecycleRecordMapperFixture.providerLiveSession(
            from: .object([
                "name": .string("liveSessions/session_123"),
                "model": .string("models/gemini-live-2.5-flash-preview"),
                "state": .string("ACTIVE"),
                "modalities": .array([.string("audio"), .string("text")]),
                "expireTime": .string("2026-05-19T12:00:00Z"),
                "metadata": .object(["voice": .string("default")]),
            ]),
            providerID: providerID
        )
        let fileArtifact = GeminiProviderLifecycleRecordMapperFixture.providerArtifact(
            from: .object([
                "fileData": .object([
                    "fileUri": .string("files/generated_image"),
                    "mimeType": .string("image/png"),
        ])
            ]),
            providerID: providerID,
            responseID: "resp_gemini",
            toolCallID: nil
        )
        let inlineArtifact = GeminiProviderLifecycleRecordMapperFixture.providerArtifact(
            from: .object([
                "inlineData": .object([
                    "mimeType": .string("image/png"),
                    "data": .string("aW1n"),
        ])
            ]),
            providerID: providerID,
            responseID: "resp_gemini",
            toolCallID: "code_1"
        )
        let researchRun = GeminiProviderLifecycleRecordMapperFixture.providerResearchRun(
            providerID: providerID,
            modelID: modelID,
            title: "Market map",
            prompt: "Research Gemini lifecycle records.",
            sourcePolicy: .object(["scope": .string("web")]),
            responseID: "resp_gemini",
            status: "completed",
            providerMetadata: [
                CloudProviderMetadataKeys.geminiResponseID: "resp_gemini",
        CloudProviderMetadataKeys.webSearchCitationsJSON:
          #"[{"title":"Gemini lifecycle","url":"https://example.com/gemini","source":"Gemini"}]"#,
                CloudProviderMetadataKeys.webSearchQueriesJSON: #"["gemini lifecycle"]"#,
            ]
        )
        let capability = ProviderModelCapabilityRecord(
            providerID: providerID,
            providerKind: .gemini,
            modelID: modelID,
      capabilities: cloudConfiguration(
        kind: .gemini, baseURL: "https://generativelanguage.googleapis.com"
      ).capabilities,
            contextWindowTokens: 1_048_576,
            inputModalities: ["text", "image", "audio", "video", "pdf"],
            outputModalities: ["text", "image", "video"],
            metadata: ["publisher": "google"]
        )

    let decodedFile = try JSONDecoder().decode(
      ProviderFileRecord.self, from: JSONEncoder().encode(try #require(file)))
    let decodedCache = try JSONDecoder().decode(
      ProviderCacheRecord.self, from: JSONEncoder().encode(try #require(cache)))
    let decodedBatch = try JSONDecoder().decode(
      ProviderBatchRecord.self, from: JSONEncoder().encode(try #require(batch)))
    let decodedLive = try JSONDecoder().decode(
      ProviderLiveSessionRecord.self, from: JSONEncoder().encode(try #require(live)))
    let decodedFileArtifact = try JSONDecoder().decode(
      ProviderArtifactRecord.self, from: JSONEncoder().encode(try #require(fileArtifact)))
    let decodedInlineArtifact = try JSONDecoder().decode(
      ProviderArtifactRecord.self, from: JSONEncoder().encode(try #require(inlineArtifact)))
    let decodedResearchRun = try JSONDecoder().decode(
      ProviderResearchRunRecord.self, from: JSONEncoder().encode(researchRun))
    let decodedCapability = try JSONDecoder().decode(
      ProviderModelCapabilityRecord.self, from: JSONEncoder().encode(capability))

        #expect(decodedFile.id == "files/audio_123")
        #expect(decodedFile.providerKind == .gemini)
        #expect(decodedFile.fileName == "meeting.mp3")
        #expect(decodedFile.byteCount == 4096)
        #expect(decodedFile.providerMetadata["transient"] == "true")
        #expect(decodedCache.kind == "context_cache")
        #expect(decodedCache.modelID == modelID)
        #expect(decodedCache.itemCounts?.objectValue?["cachedContentTokenCount"]?.intValue == 1536)
        #expect(decodedBatch.endpoint == "models/gemini-3.1-pro-preview:batchGenerateContent")
        #expect(decodedBatch.inputFileID == "files/input_123")
        #expect(decodedLive.modelID == "gemini-live-2.5-flash-preview")
        #expect(decodedLive.modalities == ["audio", "text"])
        #expect(decodedFileArtifact.providerFileID == "files/generated_image")
        #expect(decodedInlineArtifact.byteCount == 3)
        #expect(decodedResearchRun.providerKind == .gemini)
        #expect(decodedResearchRun.citationCount == 1)
    #expect(
      decodedResearchRun.providerMetadata[CloudProviderMetadataKeys.geminiResponseID]
        == "resp_gemini")
        #expect(decodedCapability.capabilities.modelCapabilities.contains(.contextCache))
        #expect(decodedCapability.capabilities.modelCapabilities.contains(.live))
        #expect(decodedCapability.capabilities.modelCapabilities.contains(.batch))
        #expect(decodedCapability.capabilities.modelCapabilities.contains(.tokenCounting))
    }

    @Test
    func geminiParserMetadataFeedsProviderLifecycleRecordFixture() throws {
        var parser = CloudProviderStreamParser()
    parser.recordRequestMetadata(
      providerKind: .gemini, serverRequestID: "req_gemini", clientRequestID: "client_gemini")
        let payload = """
        {
          "responseId": "resp_lifecycle",
          "modelVersion": "gemini-3.1-pro-preview",
          "usageMetadata": {
            "promptTokenCount": 20,
            "candidatesTokenCount": 4,
            "cachedContentTokenCount": 12
          },
          "candidates": [{
            "content": {
              "role": "model",
              "parts": [
                { "text": "{\\"answer\\":\\"ok\\"}" },
                { "executableCode": { "language": "PYTHON", "code": "print(1)" } },
                { "codeExecutionResult": { "outcome": "OUTCOME_OK", "output": "1" } },
                { "fileData": { "mimeType": "application/pdf", "fileUri": "files/source_pdf" } },
                { "inlineData": { "mimeType": "image/png", "data": "aW1n" } }
              ]
            },
            "groundingMetadata": {
              "webSearchQueries": ["gemini cache lifecycle"],
              "groundingChunks": [{ "web": { "uri": "https://example.com/gemini", "title": "Gemini lifecycle" } }]
            },
            "finishReason": "STOP"
          }]
        }
        """

    let output = parser.parse(
      data: Data(payload.utf8), format: .geminiGenerateContent, providerKind: .gemini)
        let metadata = try #require(output.finish?.providerMetadata)
        let artifacts = GeminiProviderLifecycleRecordMapperFixture.providerArtifacts(
            fromGeminiMetadata: metadata,
            providerID: "gemini",
            responseID: metadata[CloudProviderMetadataKeys.geminiResponseID]
        )
        let cache = GeminiProviderLifecycleRecordMapperFixture.providerCache(
            fromCachedContentName: "cachedContents/cache_lifecycle",
            providerID: "gemini",
            modelID: "gemini-3.1-pro-preview",
            metadata: metadata
        )
        let structured = ProviderStructuredOutputRecord(
            providerID: "gemini",
            providerKind: .gemini,
            responseID: metadata[CloudProviderMetadataKeys.geminiResponseID],
            schemaName: "answer",
            schema: .object(["type": .string("object")]),
            content: .object(["answer": .string("ok")]),
            status: "parsed"
        )

        #expect(metadata[CloudProviderMetadataKeys.geminiRequestID] == "req_gemini")
        #expect(metadata[CloudProviderMetadataKeys.geminiResponseID] == "resp_lifecycle")
        #expect(metadata[CloudProviderMetadataKeys.geminiModelVersion] == "gemini-3.1-pro-preview")
    #expect(
      metadata[CloudProviderMetadataKeys.geminiCacheUsageJSON]?.contains("cachedContentTokenCount")
        == true)
    #expect(
      metadata[CloudProviderMetadataKeys.geminiCodeExecutionJSON]?.contains("OUTCOME_OK") == true)
    #expect(
      metadata[CloudProviderMetadataKeys.webSearchCitationsJSON]?.contains("Gemini lifecycle")
        == true)
    #expect(
      artifacts.contains {
        $0.providerFileID == "files/source_pdf" && $0.contentType == "application/pdf"
      })
        #expect(artifacts.contains { $0.kind == "inline_data" && $0.byteCount == 4 })
        #expect(cache.usageBytes == 12)
        #expect(cache.itemCounts?.objectValue?["cachedContentTokenCount"]?.intValue == 12)
        #expect(structured.providerKind == .gemini)
        #expect(structured.responseID == "resp_lifecycle")
    }

    @Test
    func geminiSSEDecoderInjectsEventTypeAndPreservesID() throws {
        var decoder = CloudProviderSSEStreamDecoder()
        #expect(decoder.ingest("id: evt_1") == nil)
        #expect(decoder.ingest("event: interaction.completed") == nil)
    #expect(
      decoder.ingest(
        #"data: {"interaction":{"id":"ia_1","usage":{"total_input_tokens":1,"total_output_tokens":1}}}"#
      ) == nil)
        let maybeEvent = decoder.ingest("")
        let event = try #require(maybeEvent)
        #expect(event.eventID == "evt_1")

        let data = try #require(event.jsonData(eventTypeField: "event_type"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["event_type"] as? String == "interaction.completed")
        #expect(object["id"] as? String == "evt_1")
    }

    @Test
    func openAIResponsesParserReportsEmptyCompletions() {
        var parser = CloudProviderStreamParser()
    let payload =
      #"{"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[]}}"#
    let output = parser.parse(
      data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.isEmpty)
        #expect(output.finish?.reason == .stop)
        #expect(output.finish?.message?.contains("without visible output text") == true)
        #expect(output.finish?.providerMetadata[CloudProviderMetadataKeys.openAIResponseID] == "resp_1")
    }

    @Test
    func openAIResponsesParserReportsEmptyCompletionsEvenWithUsage() {
        var parser = CloudProviderStreamParser()
    let payload =
      #"{"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[],"usage":{"input_tokens":4,"output_tokens":1}}}"#
    let output = parser.parse(
      data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

    #expect(
      output.events.contains(.metrics(InferenceMetrics(promptTokens: 4, completionTokens: 1))))
        #expect(output.finish?.reason == .stop)
        #expect(output.finish?.message?.contains("without visible output text") == true)
        #expect(output.finish?.message?.contains("output items: 0") == true)
    }

    @Test
    func openAIResponsesParserSurfacesStreamErrors() {
        var parser = CloudProviderStreamParser()
    parser.recordRequestMetadata(
      providerKind: .openAI, serverRequestID: "req_header", clientRequestID: "client_1")
    let payload =
      #"{"type":"error","error":{"message":"The requested model is unavailable.","code":"model_not_found"}}"#
    let output = parser.parse(
      data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.isEmpty)
        #expect(output.finish?.reason == .error)
        #expect(output.finish?.message == "The requested model is unavailable.")
    #expect(
      output.finish?.providerMetadata[CloudProviderMetadataKeys.openAIRequestID] == "req_header")
    #expect(
      output.finish?.providerMetadata[CloudProviderMetadataKeys.openAIClientRequestID] == "client_1"
    )
    }

    @Test
    func openAIResponsesParserAcceptsTextObjectStreamingVariants() {
        var parser = CloudProviderStreamParser()
        let payloads = [
            #"{"type":"response.output_text.delta","delta":{"text":"hel"}}"#,
            #"{"type":"response.output_text.delta","delta":"lo"}"#,
            #"{"type":"response.completed","response":{"id":"resp_2","status":"completed","output":[],"usage":{"input_tokens":3,"output_tokens":2}}}"#,
        ]

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for payload in payloads {
      let output = parser.parse(
        data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "hel", tokenCount: 1))))
        #expect(events.contains(.token(TokenDelta(kind: .token, text: "lo", tokenCount: 1))))
        #expect(events.contains(.metrics(InferenceMetrics(promptTokens: 3, completionTokens: 2))))
        #expect(finish?.reason == .stop)
        #expect(finish?.message == nil)
    }

    @Test
    func openAIResponsesSSEDecoderFeedsParserWhenTypeOnlyAppearsInEventField() {
        var decoder = CloudProviderSSEStreamDecoder()
        var parser = CloudProviderStreamParser()
        let lines = [
            #"event: response.output_text.delta"#,
            #"data: {"delta":"streamed"}"#,
            "",
            #"event: response.completed"#,
            #"data: {"response":{"id":"resp_5","status":"completed","output":[]}}"#,
            "",
        ]

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for line in lines {
            guard let sseEvent = decoder.ingest(line), let data = sseEvent.jsonData() else { continue }
            let output = parser.parse(data: data, format: .openAIResponses, providerKind: .openAI)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "streamed", tokenCount: 1))))
        #expect(finish?.reason == .stop)
        #expect(finish?.message == nil)
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIResponseID] == "resp_5")
    }

    @Test
    func openAIResponsesSSEDecoderFeedsParserWhenBlankSeparatorsAreOmitted() {
        var decoder = CloudProviderSSEStreamDecoder()
        var parser = CloudProviderStreamParser()
        let lines = [
            #"event: response.created"#,
            #"data: {"response":{"id":"resp_missing_blanks","status":"in_progress","output":[]}}"#,
            #"event: response.output_text.delta"#,
            #"data: {"delta":"visible"}"#,
            #"event: response.completed"#,
            #"data: {"response":{"id":"resp_missing_blanks","status":"completed","output":[],"usage":{"input_tokens":3,"output_tokens":1}}}"#,
        ]

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for line in lines {
            guard let sseEvent = decoder.ingest(line), let data = sseEvent.jsonData() else { continue }
            let output = parser.parse(data: data, format: .openAIResponses, providerKind: .openAI)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }
        if let sseEvent = decoder.finish(), let data = sseEvent.jsonData() {
            let output = parser.parse(data: data, format: .openAIResponses, providerKind: .openAI)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "visible", tokenCount: 1))))
        #expect(events.contains(.metrics(InferenceMetrics(promptTokens: 3, completionTokens: 1))))
        #expect(finish?.reason == .stop)
        #expect(finish?.message == nil)
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.openAIResponseID] == "resp_missing_blanks")
    }

    @Test
    func sseDecoderSeparatesDataOnlyJSONEventsWhenBlankSeparatorsAreOmitted() {
        var decoder = CloudProviderSSEStreamDecoder()
        let lines = [
            #"data: {"one":1}"#,
            #"data: {"two":2}"#,
            #"data: [DONE]"#,
        ]

        let first = decoder.ingest(lines[0])
        let second = decoder.ingest(lines[1])
        let third = decoder.ingest(lines[2])
        let done = decoder.finish()

        #expect(first == nil)
        #expect(second?.payload == #"{"one":1}"#)
        #expect(third?.payload == #"{"two":2}"#)
        #expect(done?.payload == "[DONE]")
        #expect(done?.jsonData() == nil)
    }

    @Test
    func openAIResponsesSSEDecoderIgnoresDoneSentinelAndFlushesTrailingEvent() throws {
        var decoder = CloudProviderSSEStreamDecoder()
        var parser = CloudProviderStreamParser()

        #expect(decoder.ingest("data: [DONE]") == nil)
        #expect(decoder.ingest("")?.jsonData() == nil)
        #expect(decoder.ingest("event: response.output_text.delta") == nil)
        #expect(decoder.ingest(#"data: {"delta":"tail"}"#) == nil)

        let flushedEvent = decoder.finish()
        let trailing = try #require(flushedEvent)
        let data = try #require(trailing.jsonData())
        let output = parser.parse(data: data, format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.contains(.token(TokenDelta(kind: .token, text: "tail", tokenCount: 1))))
    }

    @Test
    func openAIResponsesParserReadsNestedTextEventVariants() {
        var parser = CloudProviderStreamParser()
    let payload =
      #"{"type":"response.output_text.done","content":[{"type":"output_text","text":{"value":"late text"}}]}"#
    let output = parser.parse(
      data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

    #expect(
      output.events.contains(.token(TokenDelta(kind: .token, text: "late text", tokenCount: 1))))
    }

    @Test
    func openAIResponsesParserReadsFinalOutputTextFallbacks() {
        var parser = CloudProviderStreamParser()
        let payload = #"""
        {
          "type": "response.completed",
          "response": {
            "id": "resp_3",
            "status": "completed",
            "output_text": "top level",
            "output": [
              {
                "type": "message",
                "content": [
                  { "type": "output_text", "text": { "value": "nested" } }
                ]
              }
            ]
          }
        }
        """#
    let output = parser.parse(
      data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

    #expect(
      output.events.contains(.token(TokenDelta(kind: .token, text: "top level", tokenCount: 1))))
        #expect(output.finish?.reason == .stop)
        #expect(output.finish?.message == nil)
    }

    @Test
    func openAIResponsesParserReadsObjectContentFallbacks() {
        var parser = CloudProviderStreamParser()
        let payload = #"""
        {
          "type": "response.completed",
          "response": {
            "id": "resp_3",
            "status": "completed",
            "output": [
              {
                "type": "message",
                "content": { "type": "output_text", "text": { "content": "object content" } }
              }
            ]
          }
        }
        """#
    let output = parser.parse(
      data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

    #expect(
      output.events.contains(
        .token(TokenDelta(kind: .token, text: "object content", tokenCount: 1))))
        #expect(output.finish?.reason == .stop)
        #expect(output.finish?.message == nil)
    }

    @Test
    func openAIResponsesParserReadsFunctionCallDoneItemAndStoresOutputItems() {
        var parser = CloudProviderStreamParser()
        let payloads = [
            #"{"type":"response.function_call_arguments.done","output_index":0,"item":{"id":"fc_1","call_id":"call_1","type":"function_call","name":"lookup","arguments":"{\"query\":\"pines\"}"}}"#,
            #"{"type":"response.completed","response":{"id":"resp_4","status":"completed","output":[{"id":"fc_1","call_id":"call_1","type":"function_call","name":"lookup","arguments":"{\"query\":\"pines\"}","status":"completed"}]}}"#,
        ]

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for payload in payloads {
      let output = parser.parse(
        data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        let toolCall = events.compactMap { event -> ToolCallDelta? in
      if case .toolCall(let toolCall) = event { return toolCall }
            return nil
        }.first
        #expect(toolCall?.id == "call_1")
        #expect(toolCall?.name == "lookup")
        #expect(toolCall?.argumentsFragment == #"{"query":"pines"}"#)
        #expect(finish?.reason == .toolCall)
        #expect(finish?.message == nil)
    #expect(
      finish?.providerMetadata[CloudProviderMetadataKeys.openAIOutputItemsJSON]?.contains(
        #""function_call""#) == true)
    }

    @Test
    func openAIResponsesFallbackPreservesCompletedToolCall() {
        var parser = CloudProviderStreamParser()
    let payload =
      #"{"type":"response.function_call_arguments.done","output_index":0,"item":{"id":"fc_1","call_id":"call_1","type":"function_call","name":"lookup","arguments":"{\"query\":\"pines\"}"}}"#
    let output = parser.parse(
      data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
        let finish = parser.fallbackFinish(
            format: .openAIResponses,
            providerKind: .openAI,
            modelID: "gpt-5.5",
            usesOfficialOpenAIReasoningChat: false
        )

    #expect(
      output.events.contains(
        .toolCall(
          ToolCallDelta(
            id: "call_1", name: "lookup", argumentsFragment: #"{"query":"pines"}"#, isComplete: true
          ))))
        #expect(finish.reason == .toolCall)
        #expect(finish.message == nil)
    }

    @Test
    func providerNativeWebSearchMetadataIsPreserved() throws {
        var openAIParser = CloudProviderStreamParser()
        let openAIPayload = #"""
        {"type":"response.completed","response":{"id":"resp_search","status":"completed","output":[
          {"type":"web_search_call","id":"ws_1","status":"completed","action":{"type":"search","query":"pines native search"}},
          {"type":"message","content":[{"type":"output_text","text":"Pines supports native search.","annotations":[{"type":"url_citation","url":"https://example.com/openai","title":"OpenAI source"}]}]}
        ]}}
        """#
    let openAIOutput = openAIParser.parse(
      data: Data(openAIPayload.utf8), format: .openAIResponses, providerKind: .openAI)
        let openAIFinish = try #require(openAIOutput.finish)
        let openAICitations = try decodedCitations(openAIFinish.providerMetadata)
        let openAIQueries = try decodedQueries(openAIFinish.providerMetadata)
    #expect(
      openAICitations == [
        WebSearchCitation(
          title: "OpenAI source", url: "https://example.com/openai", source: "OpenAI")
      ])
        #expect(openAIQueries == ["pines native search"])

        var anthropicParser = CloudProviderStreamParser()
        let anthropicPayload = #"""
        {"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","title":"Anthropic source","url":"https://example.com/anthropic"}]}}
        """#
    _ = anthropicParser.parse(
      data: Data(anthropicPayload.utf8), format: .anthropicMessages, providerKind: .anthropic)
    let anthropicFinish = anthropicParser.fallbackFinish(
      format: .anthropicMessages, providerKind: .anthropic, modelID: "claude-sonnet-4-6",
      usesOfficialOpenAIReasoningChat: false)
        let anthropicCitations = try decodedCitations(anthropicFinish.providerMetadata)
    #expect(
      anthropicCitations == [
        WebSearchCitation(
          title: "Anthropic source", url: "https://example.com/anthropic", source: "Anthropic")
      ])

        var geminiParser = CloudProviderStreamParser()
        let geminiPayload = #"""
        {"candidates":[{"content":{"parts":[{"text":"Gemini grounded response."}],"role":"model"},"groundingMetadata":{"webSearchQueries":["pines gemini search"],"searchEntryPoint":{"renderedContent":"<div>Search suggestions</div>"},"groundingChunks":[{"web":{"uri":"https://example.com/gemini","title":"Gemini source"}}]},"finishReason":"STOP"}]}
        """#
    let geminiOutput = geminiParser.parse(
      data: Data(geminiPayload.utf8), format: .geminiGenerateContent, providerKind: .gemini)
        let geminiFinish = try #require(geminiOutput.finish)
        let geminiCitations = try decodedCitations(geminiFinish.providerMetadata)
        let geminiQueries = try decodedQueries(geminiFinish.providerMetadata)
    #expect(
      geminiCitations == [
        WebSearchCitation(
          title: "Gemini source", url: "https://example.com/gemini", source: "Gemini")
      ])
        #expect(geminiQueries == ["pines gemini search"])
    #expect(
      geminiFinish.providerMetadata[CloudProviderMetadataKeys.webSearchSuggestionsHTML]
        == "<div>Search suggestions</div>")
    }

    @Test
    func appSettingsDecodesGenerationDefaultsAndClampsLimits() throws {
    let legacyJSON =
      #"{"executionMode":"cloudAllowed","themeTemplate":"graphite","interfaceMode":"dark"}"#
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(decoded.cloudMaxCompletionTokens == AppSettingsSnapshot.defaultCloudMaxCompletionTokens)
        #expect(decoded.localMaxCompletionTokens == AppSettingsSnapshot.defaultLocalMaxCompletionTokens)
        #expect(decoded.localMaxContextTokens == AppSettingsSnapshot.defaultLocalMaxContextTokens)
        #expect(decoded.localTurboQuantMode == .balanced)
        #expect(decoded.openAIReasoningEffort == .low)
        #expect(decoded.openAITextVerbosity == .low)
        #expect(decoded.anthropicEffort == .medium)
        #expect(decoded.anthropicTokenCountPreflightEnabled == false)
        #expect(decoded.geminiThinkingLevel == .medium)
        #expect(decoded.cloudWebSearchMode == .off)
        #expect(decoded.cloudAccessMode == .byok)
        #expect(decoded.proEntitlementStatus == .inactive)
        #expect(decoded.managedCloudConsent == .notAsked)

        let clamped = AppSettingsSnapshot(
            cloudAccessMode: .managedPro,
            proEntitlementStatus: .active,
            managedCloudConsent: .optedIn,
            cloudMaxCompletionTokens: 1,
            localMaxCompletionTokens: 1_000_000,
            localMaxContextTokens: 1,
            localTurboQuantMode: .batterySaver,
            openAIReasoningEffort: .high,
            openAITextVerbosity: .medium,
            anthropicEffort: .xhigh,
            anthropicTokenCountPreflightEnabled: true,
            geminiThinkingLevel: .high,
            cloudWebSearchMode: .automatic
        )
        #expect(clamped.cloudMaxCompletionTokens == AppSettingsSnapshot.minCompletionTokens)
        #expect(clamped.localMaxCompletionTokens == AppSettingsSnapshot.maxCompletionTokens)
        #expect(clamped.localMaxContextTokens == AppSettingsSnapshot.minLocalContextTokens)
        #expect(clamped.localTurboQuantMode == .batterySaver)
        #expect(clamped.openAIReasoningEffort == .high)
        #expect(clamped.openAITextVerbosity == .medium)
        #expect(clamped.anthropicEffort == .xhigh)
        #expect(clamped.anthropicTokenCountPreflightEnabled == true)
        #expect(clamped.geminiThinkingLevel == .high)
        #expect(clamped.cloudWebSearchMode == .automatic)
        #expect(clamped.cloudAccessMode == .managedPro)
        #expect(clamped.proEntitlementStatus == .active)
        #expect(clamped.managedCloudConsent == .optedIn)

    let legacySampling = try JSONDecoder().decode(
      ChatSampling.self, from: Data(#"{"maxTokens":256,"temperature":0.2}"#.utf8))
        #expect(legacySampling.maxTokens == 256)
        #expect(legacySampling.temperature == 0.2)
        #expect(legacySampling.openAIReasoningEffort == .low)
        #expect(legacySampling.openAITextVerbosity == .low)
        #expect(legacySampling.anthropicEffort == .medium)
        #expect(legacySampling.geminiThinkingLevel == .medium)
        #expect(legacySampling.openAIResponseStorage == .stateful)
        #expect(legacySampling.cloudWebSearchMode == .off)

        let webSearchRequest = ChatRequest(
            modelID: "gpt-5.5",
            messages: [ChatMessage(role: .user, content: "search")],
            webSearchOptions: CloudWebSearchOptions(
                contextSize: .high,
        userLocation: CloudWebSearchUserLocation(
          city: "Berlin", region: "Berlin", country: "DE", timezone: "Europe/Berlin"),
                allowedDomains: ["example.com"],
                blockedDomains: ["blocked.example"],
                externalWebAccess: true
            )
        )
    let decodedWebSearchRequest = try JSONDecoder().decode(
      ChatRequest.self, from: JSONEncoder().encode(webSearchRequest))
        #expect(decodedWebSearchRequest.webSearchOptions?.contextSize == .high)
        #expect(decodedWebSearchRequest.webSearchOptions?.userLocation?.city == "Berlin")
        #expect(decodedWebSearchRequest.webSearchOptions?.allowedDomains == ["example.com"])
    }

    @Test
    func anthropicRequestOptionsRoundTripAndKeepLegacyEffortDefaults() throws {
        let legacyRequestJSON = """
        {"modelID":"claude-sonnet-4-6","messages":[{"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"hi"}],"sampling":{"anthropicEffort":"xhigh"}}
        """
    let legacyRequest = try JSONDecoder().decode(
      ChatRequest.self, from: Data(legacyRequestJSON.utf8))
        #expect(legacyRequest.anthropicOptions == nil)
        #expect(legacyRequest.resolvedAnthropicOptions.thinking.effort == .xhigh)
        #expect(legacyRequest.resolvedAnthropicOptions.thinking.mode == .adaptive)

        let request = ChatRequest(
            modelID: "claude-sonnet-4-6",
            messages: [ChatMessage(role: .user, content: "Use Anthropic files")],
            anthropicOptions: AnthropicRequestOptions(
                promptCache: AnthropicPromptCacheOptions(enabled: true, ttl: .oneHour, breakpointLimit: 8),
        thinking: AnthropicThinkingOptions(
          mode: .budgeted, budgetTokens: 4_096, effort: .high, showSummaries: false),
                citations: AnthropicCitationOptions(enabled: true),
        hostedTools: [
          .webFetch(allowedDomains: ["docs.anthropic.com"], blockedDomains: [], maxUses: 2)
        ],
                providerFileIDs: ["file_abc"],
                batch: AnthropicBatchRequestOptions(customID: "job-1", metadata: ["trace": "anthropic"]),
                countTokensBeforeSend: true,
                betaHeaders: ["custom-beta"],
                metadata: ["purpose": "contract"]
            )
        )

        let decoded = try JSONDecoder().decode(ChatRequest.self, from: JSONEncoder().encode(request))
        #expect(decoded.anthropicOptions?.promptCache.enabled == true)
        #expect(decoded.anthropicOptions?.promptCache.ttl == .oneHour)
        #expect(decoded.anthropicOptions?.thinking.mode == .budgeted)
        #expect(decoded.anthropicOptions?.thinking.budgetTokens == 4_096)
        #expect(decoded.anthropicOptions?.citations.enabled == true)
    #expect(
      decoded.anthropicOptions?.hostedTools == [
        .webFetch(allowedDomains: ["docs.anthropic.com"], blockedDomains: [], maxUses: 2)
      ])
        #expect(decoded.anthropicOptions?.providerFileIDs == ["file_abc"])
        #expect(decoded.anthropicOptions?.batch?.customID == "job-1")
        #expect(decoded.anthropicOptions?.countTokensBeforeSend == true)
    #expect(
      decoded.anthropicOptions?.requiredBetaHeaders.contains(AnthropicBetaHeaders.extendedCacheTTL)
        == true)
    #expect(
      decoded.anthropicOptions?.requiredBetaHeaders.contains(AnthropicBetaHeaders.filesAPI) == true)
        #expect(decoded.anthropicOptions?.requiredBetaHeaders.contains("custom-beta") == true)
    }

    @Test
    func providerCitationsRoundTripThroughSharedMetadata() throws {
        let citations = [
            ProviderCitation(
                id: "cite_1",
                providerKind: .anthropic,
                sourceType: .pdf,
                title: "Policy",
                fileID: "file_abc",
                page: 3,
                chunkID: "chunk_1",
                documentID: "doc_1",
                startOffset: 10,
                endOffset: 42,
                citedText: "Grounded answer.",
                source: "Anthropic"
      )
        ]
        let data = try JSONEncoder().encode(citations)
    let metadata = [
      CloudProviderMetadataKeys.providerCitationsJSON: String(decoding: data, as: UTF8.self)
    ]

        #expect(metadata.providerCitations == citations)
    }

    @Test
    func openAIParityContractsRoundTripAndKeepLegacyDefaults() throws {
        let legacyChatRun = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "conversationID":"00000000-0000-0000-0000-000000000002",
          "requestID":"00000000-0000-0000-0000-000000000003",
          "status":"completed",
          "providerID":"openai",
          "modelID":"gpt-5.5"
        }
        """
        let decodedRun = try JSONDecoder().decode(ChatRun.self, from: Data(legacyChatRun.utf8))
        #expect(decodedRun.providerKind == nil)
        #expect(decodedRun.usedResponsesAPI == false)
        #expect(decodedRun.providerMetadata.isEmpty)

        let request = ChatRequest(
            modelID: "gpt-5.5",
            messages: [ChatMessage(role: .user, content: "Return JSON")],
            openAIResponseOptions: OpenAIResponseRequestOptions(
                previousResponseID: "resp_previous",
                background: true,
                structuredOutput: OpenAIStructuredOutputRequest(
                    name: "answer",
                    schema: .object(["type": .string("object")])
                ),
                hostedTools: [OpenAIHostedToolRequest(kind: .fileSearch, vectorStoreIDs: ["vs_1"])],
                providerFileIDs: ["file_1"],
                vectorStoreIDs: ["vs_1"],
                metadata: ["trace": "test"]
            )
        )
    let decodedRequest = try JSONDecoder().decode(
      ChatRequest.self, from: JSONEncoder().encode(request))
        #expect(decodedRequest.openAIResponseOptions?.background == true)
        #expect(decodedRequest.openAIResponseOptions?.structuredOutput?.name == "answer")
        #expect(decodedRequest.openAIResponseOptions?.hostedTools.first?.vectorStoreIDs == ["vs_1"])

        let vectorStore = OpenAIVectorStore(
            id: "vs_1",
            providerID: "openai",
            name: "Docs",
            status: .completed,
            fileCounts: .init(completed: 1, total: 1),
            usageBytes: 42
        )
        let background = OpenAIBackgroundResponse(
            id: "resp_1",
            providerID: "openai",
            modelID: "gpt-5.5",
            status: .completed,
            outputItems: .array([.object(["type": .string("message")])]),
            providerMetadata: [CloudProviderMetadataKeys.openAIResponseID: "resp_1"]
        )
        let structured = OpenAIStructuredOutputResult(
            responseID: "resp_1",
            schemaName: "answer",
            content: .object(["ok": .bool(true)])
        )
        let cache = ProviderContextCache(
            id: "cachedContents/cache_1",
            providerID: "gemini",
            modelID: "gemini-3.1-pro",
            name: "cachedContents/cache_1",
            status: .active,
            contentTokenCount: 128
        )
        let providerFile: ProviderFile = OpenAIProviderFile(
            id: "file_1",
            providerID: "openai",
            purpose: .assistants,
            fileName: "doc.pdf"
        )
        let providerDataStore: ProviderDataStore = vectorStore
        let providerBackgroundRun: ProviderBackgroundRun = background
        let providerStructured: StructuredOutputResult = structured

    #expect(
      try JSONDecoder().decode(OpenAIVectorStore.self, from: JSONEncoder().encode(vectorStore))
        == vectorStore)
    #expect(
      try JSONDecoder().decode(
        OpenAIBackgroundResponse.self, from: JSONEncoder().encode(background)) == background)
    #expect(
      try JSONDecoder().decode(
        OpenAIStructuredOutputResult.self, from: JSONEncoder().encode(structured)) == structured)
    #expect(
      try JSONDecoder().decode(ProviderContextCache.self, from: JSONEncoder().encode(cache))
        == cache)
        #expect(providerFile.id == "file_1")
        #expect(providerDataStore.id == "vs_1")
        #expect(providerBackgroundRun.id == "resp_1")
        #expect(providerStructured.schemaName == "answer")
    }

    @Test
    func chatRequestReplacingPreservesProviderParityFields() {
        let request = ChatRequest(
            modelID: "gpt-5.5",
            messages: [ChatMessage(role: .user, content: "Search")],
            sampling: ChatSampling(maxTokens: 128),
            webSearchOptions: CloudWebSearchOptions(allowedDomains: ["example.com"]),
            structuredOutput: .jsonSchema(
                name: "answer",
                schema: .object(["type": .string("object")]),
                strict: true
            ),
            hostedTools: [.fileSearch(vectorStoreIDs: ["vs_1"], maxResults: 3)],
            openAIOptions: OpenAIResponsesRequestOptions(maxToolCalls: 7, metadata: ["trace": "root"]),
            allowsTools: true,
            availableTools: [],
            vaultContextIDs: [UUID()],
            executionContext: .chat,
            openAIResponseOptions: OpenAIResponseRequestOptions(
                previousResponseID: "resp_previous",
                hostedTools: [OpenAIHostedToolRequest(kind: .fileSearch, vectorStoreIDs: ["vs_1"])]
            ),
            geminiOptions: GeminiRequestOptions(cachedContentName: "cachedContents/1")
        )

        let rebuilt = request.replacing(
            messages: [ChatMessage(role: .user, content: "Next")],
            allowsTools: false,
            availableTools: [],
            executionContext: .agent
        )

        #expect(rebuilt.messages.map(\.content) == ["Next"])
        #expect(rebuilt.allowsTools == false)
        #expect(rebuilt.executionContext == .agent)
        #expect(rebuilt.structuredOutput == request.structuredOutput)
        #expect(rebuilt.hostedTools == request.hostedTools)
        #expect(rebuilt.openAIOptions?.maxToolCalls == 7)
        #expect(rebuilt.openAIResponseOptions?.previousResponseID == "resp_previous")
        #expect(rebuilt.openAIResponseOptions?.hostedTools.first?.vectorStoreIDs == ["vs_1"])
        #expect(rebuilt.geminiOptions?.cachedContentName == "cachedContents/1")
        #expect(rebuilt.webSearchOptions?.allowedDomains == ["example.com"])
        #expect(rebuilt.vaultContextIDs == request.vaultContextIDs)
    }

    @Test
    func structuredOutputResultsValidateLocallyAndHydrateResponseMetadata() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("answer")]),
            "additionalProperties": .bool(false),
            "properties": .object([
        "answer": .object(["type": .string("string")])
            ]),
        ])
        let invalid = OpenAIStructuredOutputResult(
            responseID: "resp_1",
            schemaName: "answer",
            schema: schema,
            content: .object(["extra": .bool(true)])
        ).locallyValidated()

        #expect(invalid.status == .invalid)
        #expect(invalid.validationErrors.contains("$.answer is required"))
        #expect(invalid.validationErrors.contains("$.extra is not allowed"))

        let hydrated = OpenAIStructuredOutputResult(
            schemaName: "answer",
            schema: schema,
            content: .object(["answer": .string("ok")]),
            providerMetadata: [
                CloudProviderMetadataKeys.openAIResponseID: "resp_from_parser",
                CloudProviderMetadataKeys.openAIResponseIncompleteReason: "max_output_tokens",
            ]
        )

        #expect(hydrated.responseID == "resp_from_parser")
        #expect(hydrated.incompleteReason == "max_output_tokens")
        #expect(hydrated.status == .incomplete)
        #expect(hydrated.validationErrors.isEmpty)
    }

    @Test
    func openAIParityMigrationAddsTablesAndRunProvenance() throws {
    #expect(PinesDatabaseSchema.currentVersion == 26)
        let openAIMigration = try #require(PinesDatabaseSchema.migrations.first { $0.version == 14 })
    let genericProviderMigration = try #require(
      PinesDatabaseSchema.migrations.first { $0.version == 15 })
    let projectSpacesMigration = try #require(
      PinesDatabaseSchema.migrations.first { $0.version == 16 })
    let runtimeMetadataMigration = try #require(
      PinesDatabaseSchema.migrations.first { $0.version == 17 })
        let sql = openAIMigration.sql.joined(separator: "\n")

        for table in [
            "openai_provider_files",
            "openai_vector_stores",
            "openai_vector_store_files",
            "openai_hosted_tool_calls",
            "openai_artifacts",
            "openai_background_responses",
            "openai_realtime_sessions",
            "openai_batch_jobs",
            "openai_structured_output_results",
        ] {
            #expect(sql.contains("CREATE TABLE IF NOT EXISTS \(table)"))
        }

        for column in [
            "provider_kind",
            "provider_request_id",
            "provider_response_id",
            "parent_response_id",
            "background_response_id",
            "batch_id",
            "realtime_session_id",
            "structured_output_result_id",
            "provider_metadata_json",
        ] {
            #expect(sql.contains("ALTER TABLE chat_runs ADD COLUMN \(column)"))
        }

        let genericSQL = genericProviderMigration.sql.joined(separator: "\n")
        for table in [
            "provider_files",
            "provider_artifacts",
            "provider_caches",
            "provider_batches",
            "provider_live_sessions",
            "provider_structured_outputs",
            "provider_model_capabilities",
            "provider_research_runs",
        ] {
            #expect(genericSQL.contains("CREATE TABLE IF NOT EXISTS \(table)"))
        }
        #expect(genericSQL.contains("credential_keychain_account"))
        #expect(!genericSQL.contains("client_secret_keychain_account"))

        let projectSQL = projectSpacesMigration.sql.joined(separator: "\n")
        #expect(projectSQL.contains("CREATE TABLE IF NOT EXISTS projects"))
        #expect(projectSQL.contains("ALTER TABLE conversations ADD COLUMN project_id"))
        #expect(projectSQL.contains("ALTER TABLE vault_documents ADD COLUMN project_id"))

        let runtimeMetadataSQL = runtimeMetadataMigration.sql.joined(separator: "\n")
        #expect(runtimeMetadataSQL.contains("ALTER TABLE model_installs ADD COLUMN parameter_count"))
        #expect(runtimeMetadataSQL.contains("ALTER TABLE model_installs ADD COLUMN key_head_dimension"))
    #expect(
      runtimeMetadataSQL.contains("ALTER TABLE model_installs ADD COLUMN value_head_dimension"))

    let nestedRuntimeMetadataMigration = try #require(
      PinesDatabaseSchema.migrations.first { $0.version == 18 })
        let nestedRuntimeMetadataSQL = nestedRuntimeMetadataMigration.sql.joined(separator: "\n")
    #expect(
      nestedRuntimeMetadataSQL.contains(
        "ALTER TABLE model_installs ADD COLUMN text_config_model_type"))
    #expect(
      nestedRuntimeMetadataSQL.contains("ALTER TABLE model_installs ADD COLUMN routed_experts"))
    #expect(
      nestedRuntimeMetadataSQL.contains("ALTER TABLE model_installs ADD COLUMN experts_per_token"))

    let cacheTopologyMigration = try #require(
      PinesDatabaseSchema.migrations.first { $0.version == 19 })
        let cacheTopologySQL = cacheTopologyMigration.sql.joined(separator: "\n")
        #expect(cacheTopologySQL.contains("ALTER TABLE model_installs ADD COLUMN cache_topology"))
    #expect(
      cacheTopologySQL.contains("ALTER TABLE model_installs ADD COLUMN turbo_quant_family_support"))

        let snapshotMigration = try #require(PinesDatabaseSchema.migrations.first { $0.version == 21 })
        let snapshotSQL = snapshotMigration.sql.joined(separator: "\n")
        for table in [
            "kv_snapshot_manifest",
            "kv_snapshot_blob",
            "kv_snapshot_reference",
            "kv_snapshot_restore_attempt",
            "kv_snapshot_quarantine",
        ] {
            #expect(snapshotSQL.contains("CREATE TABLE IF NOT EXISTS \(table)"))
        }
        #expect(snapshotSQL.contains("cloud_sync_allowed INTEGER NOT NULL DEFAULT 0"))
        #expect(snapshotSQL.contains("excluded_from_backup INTEGER NOT NULL DEFAULT 1"))
        #expect(snapshotSQL.contains("REFERENCES model_installs(repository) ON DELETE CASCADE"))

    let speculativeMigration = try #require(
      PinesDatabaseSchema.migrations.first { $0.version == 22 })
        let speculativeSQL = speculativeMigration.sql.joined(separator: "\n")
    #expect(
      speculativeSQL.contains(
        "ALTER TABLE turboquant_profile_evidence ADD COLUMN speculative_dimensions_json"))
    #expect(
      speculativeSQL.contains(
        "ALTER TABLE turboquant_profile_evidence ADD COLUMN speculative_telemetry_json"))
    #expect(
      speculativeSQL.contains(
        "ALTER TABLE turboquant_profile_evidence ADD COLUMN speculative_auto_disable_json"))

    let platformMigration = try #require(PinesDatabaseSchema.migrations.first { $0.version == 23 })
    let platformSQL = platformMigration.sql.joined(separator: "\n")
    #expect(
      platformSQL.contains(
        "ALTER TABLE turboquant_profile_evidence ADD COLUMN platform_evidence_dimensions_json"))

    let runtimeEvidenceMigration = try #require(
      PinesDatabaseSchema.migrations.first { $0.version == 24 })
    let runtimeEvidenceSQL = runtimeEvidenceMigration.sql.joined(separator: "\n")
    for column in [
      "requested_runtime_mode",
      "resolved_runtime_mode",
      "key_precision",
      "value_precision",
      "precision_policy_json",
      "sparse_value_policy_json",
      "effective_backend",
      "native_backend_version",
      "decoded_active_kv_bytes",
    ] {
      #expect(
        runtimeEvidenceSQL.contains(
          "ALTER TABLE turboquant_profile_evidence ADD COLUMN \(column)"))
    }
    }

    @Test
    func openAIDeepResearchContractsRoundTrip() throws {
        let request = OpenAIDeepResearchRequest(
            providerID: "openai",
            title: "Market map",
            prompt: "Map the market and cite sources.",
            depth: .deep,
            sourcePolicy: OpenAIDeepResearchSourcePolicy(
                scope: .webAndProviderFiles,
                vectorStoreIDs: ["vs_123"],
                providerFileIDs: ["file_123"],
                allowedDomains: ["example.com"]
            ),
            reportFormat: .citationFirst,
            includeCodeInterpreter: true,
            serviceTier: .priority,
            metadata: ["trace": "research"]
        )
        let run = OpenAIDeepResearchRun(
            request: request,
            responseID: "resp_123",
            status: .inProgress,
            citationCount: 4,
            toolCallCount: 2,
            providerMetadata: [CloudProviderMetadataKeys.openAIResponseID: "resp_123"]
        )
        let providerRun = ProviderResearchRunRecord(
            id: run.id.uuidString,
            providerID: request.providerID,
            providerKind: .openAI,
            modelID: request.modelID,
            title: request.title,
            prompt: request.prompt,
            depth: request.depth.rawValue,
            sourcePolicy: .object([
                "scope": .string(request.sourcePolicy.scope.rawValue),
        "vector_store_ids": .array(
          request.sourcePolicy.vectorStoreIDs.map { .string($0.rawValue) }),
            ]),
            reportFormat: request.reportFormat.rawValue,
            includeCodeInterpreter: request.includeCodeInterpreter,
            serviceTier: request.serviceTier.rawValue,
            responseID: run.responseID?.rawValue,
            status: run.status.rawValue,
            citationCount: run.citationCount,
            toolCallCount: run.toolCallCount,
            providerMetadata: run.providerMetadata
        )

    let decodedRequest = try JSONDecoder().decode(
      OpenAIDeepResearchRequest.self, from: JSONEncoder().encode(request))
    let decodedRun = try JSONDecoder().decode(
      OpenAIDeepResearchRun.self, from: JSONEncoder().encode(run))
    let decodedProviderRun = try JSONDecoder().decode(
      ProviderResearchRunRecord.self, from: JSONEncoder().encode(providerRun))

        #expect(decodedRequest == request)
        #expect(decodedRun == run)
        #expect(decodedProviderRun == providerRun)
        #expect(decodedRun.request.modelID == "gpt-5.5-pro")
        #expect(decodedRun.request.sourcePolicy.vectorStoreIDs == ["vs_123"])
        #expect(decodedProviderRun.responseID == "resp_123")
    }

    @Test
    func openAIDeepResearchSourcePolicyHelpersPreserveProviderConstraints() throws {
        let webOnly = OpenAIDeepResearchSourcePolicy.webOnly(
            allowedDomains: ["example.com"],
            blockedDomains: ["ads.example"],
            webSearchReturnTokenBudget: 12_000
        )
        let webAndFiles = OpenAIDeepResearchSourcePolicy.webAndFiles(
            vectorStoreIDs: ["vs_1"],
            providerFileIDs: ["file_1"],
            allowedDomains: ["docs.example"]
        )
        let mcpURL = try #require(URL(string: "https://mcp.example.test"))
        let webAndMCP = OpenAIDeepResearchSourcePolicy.webAndMCP(
            serverLabel: "docs",
            serverURL: mcpURL,
            requireApproval: "always",
            blockedDomains: ["blocked.example"]
        )
        let request = OpenAIDeepResearchRequest(
            providerID: "openai",
            title: "Token budget",
            prompt: "Research with explicit budgets.",
            sourcePolicy: webOnly,
            responseOutputTokenBudget: 24_000
        )

    let decodedRequest = try JSONDecoder().decode(
      OpenAIDeepResearchRequest.self, from: JSONEncoder().encode(request))
        let providerRun = ProviderResearchRunRecord(
            id: "run_1",
            providerID: "openai",
            providerKind: .openAI,
            modelID: request.modelID,
            title: request.title,
            prompt: request.prompt,
            depth: request.depth.rawValue,
            sourcePolicy: .object([
                "scope": .string(webOnly.scope.rawValue),
                "allowed_domains": .array(webOnly.allowedDomains.map(JSONValue.string)),
                "blocked_domains": .array(webOnly.blockedDomains.map(JSONValue.string)),
                "web_search_return_token_budget": .number(Double(webOnly.webSearchReturnTokenBudget ?? 0)),
            ]),
            reportFormat: request.reportFormat.rawValue,
            serviceTier: request.serviceTier.rawValue,
            status: OpenAIBackgroundResponseStatus.queued.rawValue
        )

        #expect(webOnly.scope == .webOnly)
        #expect(webOnly.allowedDomains == ["example.com"])
        #expect(webOnly.webSearchReturnTokenBudget == 12_000)
        #expect(webAndFiles.scope == .webAndProviderFiles)
        #expect(webAndFiles.vectorStoreIDs == ["vs_1"])
        #expect(webAndFiles.providerFileIDs == ["file_1"])
        #expect(webAndMCP.scope == .webAndMCP)
        #expect(webAndMCP.mcpServerLabel == "docs")
        #expect(webAndMCP.mcpServerURL == mcpURL)
        #expect(decodedRequest.responseOutputTokenBudget == 24_000)
    #expect(
      providerRun.sourcePolicy.objectValue?["web_search_return_token_budget"]?.intValue == 12_000)
    }

    @Test
    func openAIBackgroundResponseStatusNormalizesTerminalStates() {
        #expect(OpenAIBackgroundResponseStatus(providerStatus: "in_progress") == .inProgress)
        #expect(OpenAIBackgroundResponseStatus(providerStatus: "requires_action") == .requiresAction)
        #expect(OpenAIBackgroundResponseStatus(providerStatus: "completed").isTerminal)
        #expect(OpenAIBackgroundResponseStatus.failed.isTerminal)
        #expect(!OpenAIBackgroundResponseStatus.inProgress.isTerminal)
    }

    @Test
    func openAIProviderRecordMapperMaterializesLifecycleRecords() throws {
        let providerID = ProviderID(rawValue: "openai")
        let file = OpenAIProviderRecordMapper.providerFile(
            from: .object([
                "id": .string("file_123"),
                "object": .string("file"),
                "purpose": .string("assistants"),
                "filename": .string("brief.pdf"),
                "bytes": .number(2048),
                "status": .string("processed"),
                "created_at": .number(1_700_000_000),
                "metadata": .object(["workspace": .string("pines")]),
            ]),
            providerID: providerID
        )
        let vectorStore = OpenAIProviderRecordMapper.providerCache(
            fromVectorStore: .object([
                "id": .string("vs_123"),
                "name": .string("Research"),
                "status": .string("completed"),
                "usage_bytes": .number(4096),
                "file_counts": .object(["completed": .number(2), "total": .number(2)]),
                "expires_after": .object(["anchor": .string("last_active_at"), "days": .number(7)]),
                "created_at": .number(1_700_000_001),
            ]),
            providerID: providerID
        )
        let batch = OpenAIProviderRecordMapper.providerBatch(
            from: .object([
                "id": .string("batch_123"),
                "endpoint": .string("/v1/responses"),
                "status": .string("in_progress"),
                "input_file_id": .string("file_123"),
                "completion_window": .string("24h"),
                "request_counts": .object(["total": .number(10), "completed": .number(2)]),
                "created_at": .number(1_700_000_002),
            ]),
            providerID: providerID
        )
        let live = OpenAIProviderRecordMapper.providerLiveSession(
            from: .object([
                "id": .string("sess_123"),
                "model": .string("gpt-realtime"),
                "status": .string("created"),
                "modalities": .array([.string("audio"), .string("text")]),
                "expires_at": .number(1_700_003_600),
            ]),
            providerID: providerID
        )
        let researchRequest = OpenAIDeepResearchRequest(
            providerID: providerID,
            title: "Market map",
            prompt: "Map the market.",
            sourcePolicy: .init(scope: .webAndProviderFiles, vectorStoreIDs: ["vs_123"]),
            metadata: ["local": "true"]
        )
        let researchRun = OpenAIProviderRecordMapper.providerResearchRun(
            from: researchRequest,
            response: .object([
                "id": .string("resp_123"),
                "status": .string("in_progress"),
                "created_at": .number(1_700_000_003),
                "metadata": .object(["provider": .string("openai")]),
                "output": .array([
                    .object(["type": .string("web_search_call")]),
                    .object([
                        "type": .string("message"),
                        "content": .array([
                            .object([
                                "type": .string("output_text"),
                                "annotations": .array([
                  .object(["type": .string("url_citation"), "url": .string("https://example.com")])
                            ]),
              ])
                        ]),
                    ]),
                ]),
            ])
        )
        let refreshedResearchRun = OpenAIProviderRecordMapper.providerResearchRun(
            updating: researchRun,
            response: .object([
                "id": .string("resp_123"),
                "status": .string("completed"),
                "metadata": .object(["provider": .string("openai"), "final": .bool(true)]),
                "output": .array([
                    .object(["type": .string("code_interpreter_call")]),
                    .object([
                        "type": .string("message"),
                        "content": .array([
                            .object([
                                "type": .string("output_text"),
                                "annotations": .array([
                                    .object(["type": .string("url_citation"), "url": .string("https://example.org")]),
                                    .object(["type": .string("url_citation"), "url": .string("https://example.net")]),
                                ]),
              ])
                        ]),
                    ]),
                ]),
            ])
        )

        #expect(file?.id == "file_123")
        #expect(file?.byteCount == 2048)
        #expect(file?.providerMetadata["workspace"] == "pines")
        #expect(vectorStore?.id == "vs_123")
        #expect(vectorStore?.configuration?.objectValue?["expires_after"] != nil)
        #expect(batch?.status == OpenAIBackgroundResponseStatus.inProgress.rawValue)
        #expect(batch?.requestCounts?.objectValue?["total"]?.intValue == 10)
        #expect(live?.modalities == ["audio", "text"])
        #expect(researchRun.responseID == "resp_123")
        #expect(researchRun.status == OpenAIBackgroundResponseStatus.inProgress.rawValue)
        #expect(researchRun.citationCount == 1)
        #expect(researchRun.toolCallCount == 1)
        #expect(researchRun.providerMetadata["provider"] == "openai")
        #expect(researchRun.providerMetadata["local"] == "true")
        #expect(refreshedResearchRun.status == "completed")
        #expect(refreshedResearchRun.citationCount == 2)
        #expect(refreshedResearchRun.toolCallCount == 1)
        #expect(refreshedResearchRun.providerMetadata["final"] == "true")
    }

    @Test
    func providerLifecycleRepositoriesSupportFilteredCRUD() async throws {
        let repository = InMemoryProviderLifecycleRepository()
        let openAI = ProviderID(rawValue: "openai")
        let anthropic = ProviderID(rawValue: "anthropic")
        let structuredID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

    try await repository.upsertProviderFile(
      ProviderFileRecord(
            id: "file_1",
            providerID: openAI,
            providerKind: .openAI,
            purpose: "assistants",
            fileName: "brief.pdf",
            status: "processed"
        ))
    try await repository.upsertProviderFile(
      ProviderFileRecord(
            id: "file_2",
            providerID: anthropic,
            providerKind: .anthropic,
            purpose: "messages",
            fileName: "notes.txt",
            status: "processed"
        ))
    try await repository.upsertProviderArtifact(
      ProviderArtifactRecord(
            id: "artifact_1",
            providerID: openAI,
            providerKind: .openAI,
            responseID: "resp_1",
            kind: "image",
            fileName: "chart.png"
        ))
    try await repository.upsertProviderArtifact(
      ProviderArtifactRecord(
            id: "artifact_2",
            providerID: openAI,
            providerKind: .openAI,
            responseID: "resp_2",
            kind: "code_interpreter"
        ))
    try await repository.upsertProviderCache(
      ProviderCacheRecord(
            id: "vs_1",
            providerID: openAI,
            providerKind: .openAI,
            kind: "vector_store",
            name: "Docs",
            status: "completed",
            usageBytes: 128
        ))
    try await repository.upsertProviderBatch(
      ProviderBatchRecord(
            id: "batch_1",
            providerID: openAI,
            providerKind: .openAI,
            endpoint: "/v1/responses",
            status: "in_progress",
            inputFileID: "file_1"
        ))
    try await repository.upsertProviderLiveSession(
      ProviderLiveSessionRecord(
            id: "sess_1",
            providerID: openAI,
            providerKind: .openAI,
            modelID: "gpt-realtime",
            status: "created",
            modalities: ["audio", "text"]
        ))
    try await repository.upsertProviderStructuredOutput(
      ProviderStructuredOutputRecord(
            id: structuredID,
            providerID: openAI,
            providerKind: .openAI,
            responseID: "resp_1",
            schemaName: "answer",
            content: .object(["ok": .bool(true)]),
            status: "parsed"
        ))
    try await repository.upsertProviderModelCapability(
      ProviderModelCapabilityRecord(
            providerID: openAI,
            providerKind: .openAI,
            modelID: "gpt-5.5",
        capabilities: ProviderCapabilities(
          local: false, files: true, hostedTools: true, structuredOutputs: true),
            contextWindowTokens: 128_000,
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            metadata: ["source": "test"]
        ))
    try await repository.upsertProviderResearchRun(
      ProviderResearchRunRecord(
            id: "research_1",
            providerID: openAI,
            providerKind: .openAI,
            modelID: "gpt-5.5-pro",
            title: "Market map",
            prompt: "Map the market.",
            depth: "deep",
            sourcePolicy: .object(["scope": .string("web")]),
            reportFormat: "citation_first",
            serviceTier: "priority",
            responseID: "resp_research",
            status: "in_progress",
            citationCount: 2,
            toolCallCount: 1
        ))

        #expect(try await repository.listProviderFiles(providerID: openAI).map(\.id) == ["file_1"])
    #expect(
      try await repository.listProviderArtifacts(responseID: "resp_1").map(\.id) == ["artifact_1"])
    #expect(
      try await repository.listProviderCaches(providerID: openAI, kind: "vector_store").map(\.id)
        == ["vs_1"])
        #expect(try await repository.listProviderBatches(providerID: openAI).map(\.id) == ["batch_1"])
    #expect(
      try await repository.listProviderLiveSessions(providerID: openAI).map(\.id) == ["sess_1"])
    #expect(
      try await repository.listProviderStructuredOutputs(responseID: "resp_1").map(\.id) == [
        structuredID
      ])
    #expect(
      try await repository.listProviderModelCapabilities(providerID: openAI).map(\.id) == [
        "openai::gpt-5.5"
      ])
    #expect(
      try await repository.listProviderResearchRuns(providerID: openAI, status: "in_progress").map(
        \.id) == ["research_1"])

        try await repository.deleteProviderArtifact(id: "artifact_1")
        try await repository.deleteProviderStructuredOutput(id: structuredID)
        try await repository.deleteProviderModelCapability(providerID: openAI, modelID: "gpt-5.5")
        try await repository.deleteProviderResearchRun(id: "research_1")

        #expect(try await repository.listProviderArtifacts(responseID: "resp_1").isEmpty)
        #expect(try await repository.listProviderStructuredOutputs(responseID: "resp_1").isEmpty)
        #expect(try await repository.listProviderModelCapabilities(providerID: openAI).isEmpty)
        #expect(try await repository.listProviderResearchRuns(providerID: openAI, status: nil).isEmpty)
    }

    @Test
    func openAIResponsesParserCapturesHostedArtifactsBackgroundAndUsageMetadata() throws {
        var parser = CloudProviderStreamParser()
    parser.recordRequestMetadata(
      providerKind: .openAI, serverRequestID: "req_header", clientRequestID: "client_1")
        let payload = #"""
        {
          "type": "response.completed",
          "response": {
            "id": "resp_background",
            "status": "completed",
            "previous_response_id": "resp_previous",
            "service_tier": "priority",
            "store": true,
            "_request_id": "req_body",
            "metadata": { "pines_prompt_cache_key": "cache-key-1" },
            "usage": {
              "input_tokens": 20,
              "output_tokens": 7,
              "output_tokens_details": { "reasoning_tokens": 3 },
              "input_tokens_details": { "cached_tokens": 5 }
            },
            "output": [
              {
                "id": "fs_1",
                "type": "file_search_call",
                "status": "completed",
                "results": [{ "file_id": "file_1", "filename": "brief.pdf", "score": 0.98 }]
              },
              {
                "id": "img_1",
                "type": "image_generation_call",
                "status": "completed",
                "revised_prompt": "A chart",
                "result": "aW1hZ2U="
              },
              {
                "id": "ci_1",
                "type": "code_interpreter_call",
                "status": "completed",
                "container_id": "cntr_1",
                "outputs": [{ "type": "logs", "logs": "done" }]
              },
              {
                "type": "message",
                "content": [{
                  "type": "output_text",
                  "text": "Done",
                  "annotations": [{
                    "type": "container_file_citation",
                    "container_id": "cntr_1",
                    "file_id": "file_out",
                    "filename": "report.csv"
                  }]
                }]
              }
            ]
          }
        }
        """#
    let output = parser.parse(
      data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
        let finish = try #require(output.finish)
        let metadata = finish.providerMetadata
    let hostedToolCalls = try decodedJSONArray(
      metadata[CloudProviderMetadataKeys.openAIHostedToolCallsJSON])
        let artifacts = try decodedJSONArray(metadata[CloudProviderMetadataKeys.openAIArtifactsJSON])
    let fileSearchResults = try decodedJSONArray(
      metadata[CloudProviderMetadataKeys.openAIFileSearchResultsJSON])

        #expect(output.events.contains(.token(TokenDelta(kind: .token, text: "Done", tokenCount: 1))))
    #expect(
      output.events.contains(.metrics(InferenceMetrics(promptTokens: 20, completionTokens: 7))))
        #expect(metadata[CloudProviderMetadataKeys.openAIRequestID] == "req_body")
        #expect(metadata[CloudProviderMetadataKeys.openAIClientRequestID] == "client_1")
        #expect(metadata[CloudProviderMetadataKeys.openAIResponseID] == "resp_background")
        #expect(metadata[CloudProviderMetadataKeys.openAIResponsePreviousID] == "resp_previous")
        #expect(metadata[CloudProviderMetadataKeys.openAIResponseStatus] == "completed")
        #expect(metadata[CloudProviderMetadataKeys.openAIResponseServiceTier] == "priority")
        #expect(metadata[CloudProviderMetadataKeys.openAIResponseStored] == "true")
        #expect(metadata[CloudProviderMetadataKeys.openAIReasoningTokens] == "3")
        #expect(metadata[CloudProviderMetadataKeys.openAICachedInputTokens] == "5")
        #expect(metadata[CloudProviderMetadataKeys.openAIPromptCacheKey] == "cache-key-1")
        #expect(hostedToolCalls.contains { $0["type"] as? String == "file_search_call" })
        #expect(hostedToolCalls.contains { $0["type"] as? String == "code_interpreter_call" })
        #expect(artifacts.contains { $0["type"] as? String == "image" && $0["byte_hint"] as? Int == 8 })
    #expect(
      artifacts.contains {
        $0["type"] as? String == "container_file" && $0["file_id"] as? String == "file_out"
      })
        #expect(fileSearchResults.first?["file_id"] as? String == "file_1")
    }

    @Test
    func openAIResponsesParserCapturesCodeInterpreterStreamingLogsAndFiles() throws {
        var parser = CloudProviderStreamParser()
        let payloads = [
            #"{"type":"response.code_interpreter_call.in_progress","item_id":"ci_stream","container_id":"cntr_stream"}"#,
            #"{"type":"response.code_interpreter_call_code.delta","item_id":"ci_stream","container_id":"cntr_stream","delta":"print(1)\n"}"#,
            #"{"type":"response.code_interpreter_call.completed","item_id":"ci_stream","container_id":"cntr_stream","output":{"type":"logs","logs":"created report","generated_files":[{"file_id":"file_generated","filename":"report.csv"}]}}"#,
            #"{"type":"response.completed","response":{"id":"resp_ci","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"done","annotations":[{"type":"container_file_citation","container_id":"cntr_stream","file_id":"file_generated","filename":"report.csv"}]}]}]}}"#,
        ]

        var finish: InferenceFinish?
        for payload in payloads {
      let output = parser.parse(
        data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
            finish = output.finish ?? finish
        }

        let metadata = try #require(finish?.providerMetadata)
        let audit = metadata.hostedToolAuditEntries
        let artifacts = metadata.providerArtifactMaterializations

    #expect(
      audit.contains {
        $0.id == "ci_stream" && $0.kind == .codeInterpreter && $0.status == .completed
      })
    #expect(
      artifacts.contains { $0.kind == .toolOutput && $0.text?.contains("created report") == true })
    #expect(
      artifacts.contains { $0.providerFileID == "file_generated" && $0.fileName == "report.csv" })
    }

    @Test
    func openAIResponsesParserCapturesImagePartialsRemoteMCPToolSearchAndComputerUseState() throws {
        var parser = CloudProviderStreamParser()
        let payloads = [
            #"{"type":"response.image_generation_call.partial_image","item_id":"img_stream","partial_image_index":0,"partial_image_b64":"aW1n"}"#,
            #"{"type":"response.mcp_list_tools.in_progress","item_id":"mcp_tools","server_label":"docs","server_url":"https://mcp.example.test","require_approval":"always"}"#,
            #"{"type":"response.tool_search_call.completed","item_id":"tool_search_1","query":"calendar"}"#,
            #"{"type":"response.computer_call.requires_action","item_id":"computer_1","action":{"type":"click","x":12,"y":34},"pending_safety_checks":[{"code":"external_navigation"}]}"#,
            #"{"type":"response.completed","response":{"id":"resp_hosted","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"ready"}]}]}}"#,
        ]

        var finish: InferenceFinish?
        for payload in payloads {
      let output = parser.parse(
        data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
            finish = output.finish ?? finish
        }

        let metadata = try #require(finish?.providerMetadata)
        let audit = metadata.hostedToolAuditEntries
        let artifacts = metadata.providerArtifactMaterializations

        #expect(artifacts.contains { $0.type == "partial_image" && $0.byteCount == 4 })
    #expect(
      audit.contains {
        $0.id == "mcp_tools" && $0.kind == .mcp && $0.requiresAgentExecution && $0.requiresApproval
      })
    #expect(
      audit.contains {
        $0.id == "tool_search_1" && $0.kind == .toolSearch && $0.status == .completed
      })
    #expect(
      audit.contains {
        $0.id == "computer_1" && $0.kind == .computerUse && $0.status == .requiresAction
          && $0.requiresApproval
      })
    }

    @Test
    func hostedToolRequestModelGatesComputerUseAndRemoteMCPToAgentApprovedRuns() throws {
        let chatRequest = ChatRequest(
            modelID: "gpt-5.5",
            messages: [ChatMessage(role: .user, content: "Use desktop and MCP")],
            hostedTools: [
                .webFetch(allowedDomains: ["example.com"], blockedDomains: [], maxUses: 1),
                .computerUse(displayWidth: 1280, displayHeight: 720),
        .remoteMCP(
          serverLabel: "docs", serverURL: "https://mcp.example.test", requireApproval: "always"),
                .textEditor,
                .bash,
            ],
            executionContext: .chat
        )
        let agentRequest = chatRequest.replacing(executionContext: .agent)
        let anthropicAgentToolRequest = ChatRequest(
            modelID: "claude-sonnet-4-6",
            messages: [ChatMessage(role: .user, content: "Edit files")],
            executionContext: .chat,
            anthropicOptions: AnthropicRequestOptions(hostedTools: [.textEditor, .bash])
        )
        let legacyRemoteMCP = try JSONDecoder().decode(
            HostedToolConfiguration.self,
      from: Data(
        #"{"type":"remoteMCP","serverLabel":"docs","serverURL":"https://mcp.example.test"}"#.utf8)
        )
        let webFetch = try JSONDecoder().decode(
            HostedToolConfiguration.self,
            from: Data(#"{"type":"webFetch","allowedDomains":["example.com"],"maxUses":1}"#.utf8)
        )
        let metadata = [
      CloudProviderMetadataKeys.openAIHostedToolCallsJSON:
        #"[{"id":"fetch_1","type":"web_fetch_tool_result","status":"completed"},{"id":"bash_1","type":"bash_call","status":"requires_action"}]"#
        ]
        let audit = metadata.hostedToolAuditEntries

        #expect(chatRequest.hasAgentOnlyHostedTools)
        #expect(chatRequest.hasApprovalGatedHostedTools)
        #expect(!chatRequest.hostedToolsAreAllowedForExecutionContext())
        #expect(agentRequest.hostedToolsAreAllowedForExecutionContext())
        #expect(!webFetch.requiresAgentExecution)
        #expect(!webFetch.requiresApproval)
        #expect(legacyRemoteMCP.requiresAgentExecution)
        #expect(legacyRemoteMCP.requiresApproval)
        #expect(HostedToolConfiguration.textEditor.requiresAgentExecution)
        #expect(HostedToolConfiguration.textEditor.requiresApproval)
        #expect(HostedToolConfiguration.bash.requiresAgentExecution)
        #expect(HostedToolConfiguration.bash.requiresApproval)
        #expect(anthropicAgentToolRequest.hasAgentOnlyHostedTools)
        #expect(!anthropicAgentToolRequest.hostedToolsAreAllowedForExecutionContext())
    #expect(
      audit.contains { $0.id == "fetch_1" && $0.kind == .webFetch && !$0.requiresAgentExecution })
    #expect(
      audit.contains {
        $0.id == "bash_1" && $0.kind == .bash && $0.requiresAgentExecution && $0.requiresApproval
      })
    }

    @Test
    func structuredOutputValidationResultRecordsPreserveInvalidState() throws {
        let resultID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let schema: JSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("answer")]),
        ])
        let result = OpenAIStructuredOutputResult(
            id: resultID,
            responseID: "resp_invalid",
            messageID: messageID,
            schemaName: "answer",
            schema: schema,
            content: .object(["answer": .number(42)]),
            validationErrors: ["$.answer expected string"],
            status: .invalid
        )
        let providerRecord = ProviderStructuredOutputRecord(
            id: result.id,
            providerID: ProviderID(rawValue: "openai"),
            providerKind: .openAI,
            responseID: result.responseID?.rawValue,
            messageID: result.messageID,
            schemaName: result.schemaName,
            schema: result.schema,
            content: result.content,
            refusal: result.refusal,
            incompleteReason: result.incompleteReason,
            validationErrors: result.validationErrors,
            status: result.status.rawValue,
            createdAt: result.createdAt
        )

    let decodedResult = try JSONDecoder().decode(
      OpenAIStructuredOutputResult.self, from: JSONEncoder().encode(result))
    let decodedRecord = try JSONDecoder().decode(
      ProviderStructuredOutputRecord.self, from: JSONEncoder().encode(providerRecord))

        #expect(decodedResult == result)
        #expect(decodedRecord == providerRecord)
        #expect(decodedRecord.status == OpenAIStructuredOutputResultStatus.invalid.rawValue)
        #expect(decodedRecord.validationErrors == ["$.answer expected string"])
        #expect(decodedRecord.schema == schema)
    }

    @Test
    func chatRequestPreservesOpenAIResponseOptionsStructuredOutputAndHostedTools() throws {
        let request = ChatRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000404")!,
            modelID: "gpt-5.5",
            messages: [ChatMessage(role: .user, content: "Use files and return JSON.")],
            sampling: ChatSampling(
                maxTokens: 2048,
                openAIReasoningEffort: .medium,
                openAITextVerbosity: .high,
                openAIResponseStorage: .statelessEncrypted,
                cloudWebSearchMode: .required
            ),
            structuredOutput: .jsonSchema(
                name: "summary",
                schema: .object(["type": .string("object")]),
                strict: false
            ),
            hostedTools: [
                .fileSearch(vectorStoreIDs: ["vs_surface"], maxResults: 5),
                .codeInterpreter(containerID: "cntr_surface", memoryLimit: "2g"),
        .remoteMCP(
          serverLabel: "docs", serverURL: "https://mcp.example.test", requireApproval: "always"),
            ],
            openAIOptions: OpenAIResponsesRequestOptions(
                store: .statelessEncrypted,
                background: true,
                serviceTier: .priority,
                promptCacheRetention: .twentyFourHours,
                safetyIdentifier: "safe_1",
                promptCacheKey: "cache_1",
                maxToolCalls: 8,
                conversationID: "conv_1",
                metadata: ["trace": "chat-options"],
                include: ["output[*].file_search_call.results"]
            ),
            openAIResponseOptions: OpenAIResponseRequestOptions(
                previousResponseID: "resp_previous",
                background: true,
                store: .statelessEncrypted,
                structuredOutput: OpenAIStructuredOutputRequest(
                    name: "summary",
                    description: "A structured summary.",
                    schema: .object(["type": .string("object")]),
                    strictness: .disabled
                ),
                hostedTools: [
                    OpenAIHostedToolRequest(
                        kind: .fileSearch,
                        vectorStoreIDs: ["vs_surface"],
                        configuration: .object(["max_num_results": .number(5)])
          )
                ],
                providerFileIDs: ["file_surface"],
                vectorStoreIDs: ["vs_surface"],
                metadata: ["trace": "response-options"]
            )
        )

    let roundTripped = try JSONDecoder().decode(
      ChatRequest.self, from: JSONEncoder().encode(request))

        #expect(roundTripped.sampling.openAIResponseStorage == .statelessEncrypted)
        #expect(roundTripped.sampling.cloudWebSearchMode == .required)
        #expect(roundTripped.structuredOutput == request.structuredOutput)
        #expect(roundTripped.hostedTools == request.hostedTools)
        #expect(roundTripped.openAIOptions == request.openAIOptions)
        #expect(roundTripped.openAIResponseOptions == request.openAIResponseOptions)
        #expect(roundTripped.openAIResponseOptions?.structuredOutput?.strictness == .disabled)
        #expect(roundTripped.openAIResponseOptions?.providerFileIDs == ["file_surface"])
    #expect(
      roundTripped.openAIResponseOptions?.hostedTools.first?.configuration?.objectValue?[
        "max_num_results"]?.intValue == 5)
    }

    private func decodedCitations(_ metadata: [String: String]) throws -> [WebSearchCitation] {
        let raw = try #require(metadata[CloudProviderMetadataKeys.webSearchCitationsJSON])
        return try JSONDecoder().decode([WebSearchCitation].self, from: Data(raw.utf8))
    }

    private func decodedQueries(_ metadata: [String: String]) throws -> [String] {
        let raw = try #require(metadata[CloudProviderMetadataKeys.webSearchQueriesJSON])
        return try JSONDecoder().decode([String].self, from: Data(raw.utf8))
    }

    private func decodedJSONArray(_ raw: String?) throws -> [[String: Any]] {
        let raw = try #require(raw)
        return try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
    }

    @Test
    func qwenTurboQuantPreflightCarriesProfileMetadataForExpandedFamilies() throws {
        let classifier = ModelPreflightClassifier()

        for spec in qwenTurboQuantProfileCases {
            let result = classifier.classify(spec.preflightInput)
            let expectedFamilySupport: TurboQuantFamilySupport =
                spec.modalities == [.text] ? .hybridFull : .none
            let expectedVerification: ModelVerificationState =
                spec.modalities == [.text] ? .verified : .installable

            #expect(result.repository == spec.repository)
            #expect(result.verification == expectedVerification)
            #expect(result.modalities == spec.modalities)
            #expect(result.modelType == spec.modelType)
            #expect(result.processorClass == spec.processorClass)
            #expect(result.parameterCount == spec.parameterCount)
            #expect(result.keyHeadDimension == spec.headDimension)
            #expect(result.valueHeadDimension == spec.headDimension)
            #expect(result.cacheTopology == .hybridAttentionAndNativeState)
            #expect(result.turboQuantFamilySupport == expectedFamilySupport)
            #expect(result.estimatedBytes == spec.expectedDownloadBytes)
            #expect(result.reasons.isEmpty)

            let install = ModelInstall(
                modelID: ModelID(rawValue: spec.repository),
                displayName: spec.displayName,
                repository: spec.repository,
                modalities: result.modalities,
                verification: result.verification,
                parameterCount: result.parameterCount,
                estimatedBytes: result.estimatedBytes,
                modelType: result.modelType,
                processorClass: result.processorClass,
                keyHeadDimension: result.keyHeadDimension,
                valueHeadDimension: result.valueHeadDimension,
                cacheTopology: result.cacheTopology,
                turboQuantFamilySupport: result.turboQuantFamilySupport
            )
            let roundTrippedInstall = try JSONDecoder().decode(
                ModelInstall.self,
                from: JSONEncoder().encode(install)
            )

            #expect(roundTrippedInstall.repository == spec.repository)
            #expect(roundTrippedInstall.modelType == spec.modelType)
            #expect(roundTrippedInstall.parameterCount == spec.parameterCount)
            #expect(roundTrippedInstall.keyHeadDimension == spec.headDimension)
            #expect(roundTrippedInstall.valueHeadDimension == spec.headDimension)
            #expect(roundTrippedInstall.cacheTopology == .hybridAttentionAndNativeState)
            #expect(roundTrippedInstall.turboQuantFamilySupport == expectedFamilySupport)

            let hints = ModelRuntimeConfigurationHints.infer(
                repository: spec.repository,
                modelType: result.modelType,
                processorClass: result.processorClass,
                metadataFiles: [
                    "config.json": spec.configJSON,
                    "tokenizer_config.json": spec.tokenizerConfigJSON,
                ]
            )

            #expect(hints.extraEOSTokens.contains("<|im_end|>"))
        }
    }

    @Test
    func qwenTextModelsWithGenericProcessorConfigStillAdvertiseTurboQuant() throws {
        let classifier = ModelPreflightClassifier()
        let result = classifier.classify(
            ModelPreflightInput(
                repository: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
                configJSON: Data(
                    #"{"model_type":"qwen3_5","head_dim":256,"full_attention_interval":4,"linear_num_value_heads":8,"linear_conv_kernel_dim":4}"#
                        .utf8
                ),
                processorConfigJSON: Data(#"{"processor_class":"QwenProcessor"}"#.utf8),
                files: [
                    ModelFileInfo(path: "config.json", size: 10_000),
                    ModelFileInfo(path: "tokenizer.json", size: 8_000_000),
                    ModelFileInfo(path: "processor_config.json", size: 12_000),
                    ModelFileInfo(path: "model.safetensors", size: 700_000_000),
                ],
                tags: ["mlx", "qwen3_5", "4bit"]
            )
        )

        #expect(result.verification == .verified)
        #expect(result.modalities == [.text])
        #expect(result.cacheTopology == .hybridAttentionAndNativeState)
        #expect(result.turboQuantFamilySupport == .hybridFull)
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: result.repository,
                modelType: result.modelType,
                textConfigModelType: result.textConfigModelType,
                modalities: result.modalities,
                familySupport: result.turboQuantFamilySupport
            )
        )
    }

    @Test
    func qwenVisionModelsRemainGatedUntilVLMTurboQuantTopologyIsExplicit() throws {
        let classifier = ModelPreflightClassifier()
        let result = classifier.classify(
            ModelPreflightInput(
                repository: "mlx-community/Qwen3.5-VL-2B-Instruct-4bit",
                configJSON: Data(
                    #"{"model_type":"qwen3_5","head_dim":256,"full_attention_interval":4,"linear_num_value_heads":8,"linear_conv_kernel_dim":4}"#
                        .utf8
                ),
                processorConfigJSON: Data(#"{"processor_class":"Qwen2VLProcessor"}"#.utf8),
                files: [
                    ModelFileInfo(path: "config.json", size: 10_000),
                    ModelFileInfo(path: "tokenizer.json", size: 8_000_000),
                    ModelFileInfo(path: "processor_config.json", size: 12_000),
                    ModelFileInfo(path: "model.safetensors", size: 1_550_000_000),
                ],
                tags: ["mlx", "qwen3_5", "image-text-to-text", "4bit"]
            )
        )

        #expect(result.modalities == [.text, .vision])
        #expect(result.cacheTopology == .hybridAttentionAndNativeState)
        #expect(result.turboQuantFamilySupport == .none)
        #expect(
            !TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: result.repository,
                modelType: result.modelType,
                textConfigModelType: result.textConfigModelType,
                modalities: result.modalities,
                familySupport: result.turboQuantFamilySupport
            )
        )
    }

    @Test
    func qwenTurboQuantResourcePolicyKeepsLargeModelsBehindDownloadGates() throws {
        let compactPolicy = ModelDiscoveryResourcePolicy(maxDownloadBytes: 3_800_000_000)
        let proPolicy = ModelDiscoveryResourcePolicy(maxDownloadBytes: 5_500_000_000)
    let specsByRepository = Dictionary(
      uniqueKeysWithValues: qwenTurboQuantProfileCases.map { ($0.repository, $0) })

        for repository in [
            "mlx-community/Qwen3.5-0.8B-MLX-4bit",
            "mlx-community/Qwen3.5-2B-MLX-4bit",
            "mlx-community/Qwen3.5-2B-OptiQ-4bit",
        ] {
            let spec = try #require(specsByRepository[repository])
            let decision = compactPolicy.evaluate(spec.preflightInput, modalities: spec.modalities)
            #expect(!decision.isRejected)
            #expect(decision.knownDownloadBytes == spec.expectedDownloadBytes)
            #expect(decision.inferredParameterCount == spec.parameterCount)
            #expect(decision.inferredWeightBits == 4)
            #expect(decision.inferredWeightBitsAreExplicit)
        }

        let qwen4B = try #require(specsByRepository["mlx-community/Qwen3.5-4B-MLX-4bit"])
    let qwen4BDecision = compactPolicy.evaluate(
      qwen4B.preflightInput, modalities: qwen4B.modalities)
        #expect(qwen4BDecision.isRejected)
        #expect(qwen4BDecision.knownDownloadBytes == qwen4B.expectedDownloadBytes)

        let qwen9B = try #require(specsByRepository["mlx-community/Qwen3.5-9B-MLX-4bit"])
        let qwen9BDecision = proPolicy.evaluate(qwen9B.preflightInput, modalities: qwen9B.modalities)
        #expect(qwen9BDecision.isRejected)
        #expect(qwen9BDecision.knownDownloadBytes == qwen9B.expectedDownloadBytes)

        for repository in [
            "mlx-community/Qwen3.5-27B-4bit",
            "mlx-community/Qwen3.6-27B-4bit",
            "mlx-community/Qwen3.5-40B-4bit",
            "mlx-community/Qwen3.6-40B-4bit",
            "mlx-community/Qwen3.5-35B-A3B-4bit",
            "mlx-community/Qwen3.6-35B-A3B-4bit",
            "mlx-community/Qwen3.5-REAP-97B-A10B-4bit",
            "mlx-community/Qwen3.5-122B-A10B-4bit",
            "mlx-community/Qwen3.5-397B-A17B-4bit",
        ] {
            let spec = try #require(specsByRepository[repository])
            let decision = proPolicy.evaluate(spec.preflightInput, modalities: spec.modalities)
            #expect(decision.isRejected)
            #expect(decision.knownDownloadBytes == spec.expectedDownloadBytes)
            #expect(decision.inferredParameterCount == spec.parameterCount)
        }
    }

    @Test
    func modelInstallInfersSmallTextGenerationModelsFromRepositoryWhenMetadataIsMissing() {
        let qwen08 = ModelInstall(
            modelID: ModelID(rawValue: "mlx-community/Qwen3.5-0.8B-MLX-4bit"),
            displayName: "Qwen3.5 0.8B",
            repository: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
            modalities: [.text],
            verification: .installable,
            parameterCount: nil,
            modelType: "qwen3_5"
        )
        let qwen2 = ModelInstall(
            modelID: ModelID(rawValue: "mlx-community/Qwen3.5-2B-OptiQ-4bit"),
            displayName: "Qwen3.5 2B OptiQ",
            repository: "mlx-community/Qwen3.5-2B-OptiQ-4bit",
            modalities: [.text],
            verification: .installable,
            parameterCount: nil,
            modelType: "qwen3_5"
        )
        let llama3B = ModelInstall(
            modelID: ModelID(rawValue: "mlx-community/Llama-3.2-3B-Instruct-4bit"),
            displayName: "Llama 3.2 3B",
            repository: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            modalities: [.text],
            verification: .installable,
            parameterCount: nil,
            modelType: "llama"
        )
        let gemma1B = ModelInstall(
            modelID: ModelID(rawValue: "mlx-community/gemma-3-1b-it-4bit"),
            displayName: "Gemma 3 1B",
            repository: "mlx-community/gemma-3-1b-it-4bit",
            modalities: [.text],
            verification: .installable,
            parameterCount: nil,
            modelType: "gemma3_text"
        )

        #expect(qwen08.resolvedParameterCount == 800_000_000)
        #expect(qwen08.isSmallTextGenerationModel)
        #expect(qwen2.resolvedParameterCount == 2_000_000_000)
        #expect(qwen2.isSmallTextGenerationModel)
        #expect(llama3B.resolvedParameterCount == 3_000_000_000)
        #expect(!llama3B.isSmallTextGenerationModel)
        #expect(gemma1B.resolvedParameterCount == 1_000_000_000)
        #expect(gemma1B.isSmallTextGenerationModel)
    }

    @Test
    func modelInstallRepairsStaleTurboQuantFamilySupportForAdmittedTextModels() {
        let staleQwen08 = ModelInstall(
            modelID: ModelID(rawValue: "mlx-community/Qwen3.5-0.8B-MLX-4bit"),
            displayName: "Qwen3.5 0.8B",
            repository: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
            modalities: [.text, .vision],
            verification: .installable,
            modelType: "qwen3_5",
            textConfigModelType: "qwen3_5_text",
            processorClass: "QwenProcessor",
            keyHeadDimension: 256,
            valueHeadDimension: 256,
            cacheTopology: .hybridAttentionAndNativeState,
            turboQuantFamilySupport: .none
        )
        let staleLlama3B = ModelInstall(
            modelID: ModelID(rawValue: "mlx-community/Llama-3.2-3B-Instruct-4bit"),
            displayName: "Llama 3.2 3B",
            repository: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            modalities: [.text],
            verification: .installable,
            modelType: "llama",
            keyHeadDimension: 128,
            valueHeadDimension: 128,
            cacheTopology: .standardAttention,
            turboQuantFamilySupport: .none
        )
        let qwenVL = ModelInstall(
            modelID: ModelID(rawValue: "mlx-community/Qwen3.5-VL-2B-Instruct-4bit"),
            displayName: "Qwen3.5 VL 2B",
            repository: "mlx-community/Qwen3.5-VL-2B-Instruct-4bit",
            modalities: [.text, .vision],
            verification: .installable,
            modelType: "qwen3_5",
            processorClass: "Qwen2VLProcessor",
            keyHeadDimension: 256,
            valueHeadDimension: 256,
            cacheTopology: .hybridAttentionAndNativeState,
            turboQuantFamilySupport: .none
        )

        #expect(staleQwen08.effectiveTurboQuantModalities == [.text])
        #expect(staleQwen08.effectiveTurboQuantFamilySupport == .hybridFull)
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: staleQwen08.repository,
                modelType: staleQwen08.modelType,
                textConfigModelType: staleQwen08.textConfigModelType,
                modalities: staleQwen08.effectiveTurboQuantModalities,
                familySupport: staleQwen08.effectiveTurboQuantFamilySupport
            )
        )
        #expect(staleLlama3B.effectiveTurboQuantFamilySupport == .attentionKVFull)
        #expect(qwenVL.effectiveTurboQuantModalities == [.text, .vision])
        #expect(qwenVL.effectiveTurboQuantFamilySupport == .none)
        #expect(
            !TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: qwenVL.repository,
                modelType: qwenVL.modelType,
                textConfigModelType: qwenVL.textConfigModelType,
                modalities: qwenVL.effectiveTurboQuantModalities,
                familySupport: qwenVL.effectiveTurboQuantFamilySupport
            )
        )
    }

    @Test
    func turboQuantRuntimeSupportDefaultsForProfileBackedFamilies() throws {
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/gemma-3-1b-it-4bit",
                modelType: "gemma3",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
                modelType: "qwen3_5",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .hybridFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/Qwen3.5-2B-OptiQ-4bit",
                modelType: "qwen3_5",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .hybridFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                modelType: "llama",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/gemma-3n-E2B-it-4bit",
                modelType: "gemma3n",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/gemma-4-e2b-it-4bit",
                modelType: "gemma4",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
                modelType: "qwen2",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/Mistral-Small-4-119B-A6B-Instruct-4bit",
                modelType: "mistral3",
                textConfigModelType: "mistral4",
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/Phi-4-mini-instruct-4bit",
                modelType: "phi3",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/granite-3.3-2b-instruct-4bit",
                modelType: "granite",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/LFM2-1.2B-Instruct-4bit",
                modelType: "lfm2",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .hybridFull
            )
        )
        #expect(
            TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/GLM-4.7-Flash-4bit",
                modelType: "glm4_moe_lite",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            !TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
                modelType: nil,
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .hybridFull
            )
        )
        #expect(
            !TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/Pixtral-12B-4bit",
                modelType: "pixtral",
                textConfigModelType: nil,
                modalities: [.text, .vision],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            !TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/gemma-3n-E4B-it-4bit",
                modelType: "gemma3n",
                textConfigModelType: "gemma3n_text",
                modalities: [.text, .vision],
                familySupport: .attentionKVFull
            )
        )
        #expect(
            !TurboQuantRuntimeSupport.supportsThrowingAttentionGeneration(
                repository: "mlx-community/gemma-4-e2b-it-4bit",
                modelType: "gemma4_assistant",
                textConfigModelType: nil,
                modalities: [.text],
                familySupport: .attentionKVFull
            )
        )
    }

    @Test
    func preflightRequiresRuntimeCapabilityRegistryForVerifiedTurboQuantClaim() throws {
        let classifier = ModelPreflightClassifier(
            turboQuantRuntimeCapabilities: PinesTurboQuantRuntimeCapabilityRegistry(capabilities: [])
        )
        let result = classifier.classify(
            ModelPreflightInput(
                repository: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
                configJSON: Data(#"{"model_type":"qwen2","hidden_size":2048,"num_attention_heads":16}"#.utf8),
                files: [
                    ModelFileInfo(path: "config.json", size: 10_000),
                    ModelFileInfo(path: "tokenizer.json", size: 2_000_000),
                    ModelFileInfo(path: "model.safetensors", size: 1_000_000_000),
                ],
                tags: ["mlx", "4bit"]
            )
        )

        #expect(result.turboQuantFamilySupport == .attentionKVFull)
        #expect(result.verification == .installable)
    }

    @Test
    func broadTurboQuantRuntimeFamiliesPreflightAsSupported() throws {
        let classifier = ModelPreflightClassifier()
        let cases: [(String, String, ModelCacheTopology, TurboQuantFamilySupport, Int, Int)] = [
            (
                "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
                #"{"model_type":"qwen2","hidden_size":2048,"num_attention_heads":16}"#,
                .standardAttention,
                .attentionKVFull,
                128,
                128
            ),
            (
                "mlx-community/Phi-4-mini-instruct-4bit",
                #"{"model_type":"phi3","hidden_size":3072,"num_attention_heads":32}"#,
                .standardAttention,
                .attentionKVFull,
                96,
                96
            ),
            (
                "mlx-community/granite-3.3-2b-instruct-4bit",
                #"{"model_type":"granite","hidden_size":4096,"num_attention_heads":32}"#,
                .standardAttention,
                .attentionKVFull,
                128,
                128
            ),
            (
                "mlx-community/EXAONE-4.0-1.2B-4bit",
                #"{"model_type":"exaone4","head_dim":128,"sliding_window":4096}"#,
                .slidingAttention,
                .attentionKVFull,
                128,
                128
            ),
            (
                "mlx-community/SmolLM3-3B-4bit",
                #"{"model_type":"smollm3","hidden_size":2048,"num_attention_heads":32}"#,
                .standardAttention,
                .attentionKVFull,
                64,
                64
            ),
            (
                "mlx-community/LFM2-1.2B-Instruct-4bit",
                #"{"model_type":"lfm2","hidden_size":1024,"num_attention_heads":16,"layer_types":["full_attention","conv"]}"#,
                .hybridAttentionAndNativeState,
                .hybridFull,
                64,
                64
            ),
            (
                "mlx-community/GLM-4.7-Flash-4bit",
                #"{"model_type":"glm4_moe_lite","qk_nope_head_dim":128,"qk_rope_head_dim":64,"v_head_dim":128}"#,
                .standardAttention,
                .attentionKVFull,
                192,
                128
            ),
        ]

        for (repository, configJSON, topology, familySupport, keyDimension, valueDimension) in cases {
            let result = classifier.classify(
                ModelPreflightInput(
                    repository: repository,
                    configJSON: Data(configJSON.utf8),
                    files: [
                        ModelFileInfo(path: "config.json", size: 10_000),
                        ModelFileInfo(path: "tokenizer.json", size: 2_000_000),
                        ModelFileInfo(path: "model.safetensors", size: 1_000_000_000),
                    ],
                    tags: ["mlx", "4bit"]
                )
            )

            #expect(result.verification == .verified)
            #expect(result.modalities == [.text])
            #expect(result.cacheTopology == topology)
            #expect(result.turboQuantFamilySupport == familySupport)
            #expect(result.keyHeadDimension == keyDimension)
            #expect(result.valueHeadDimension == valueDimension)
            #expect(result.reasons.isEmpty)
        }
    }

    @Test
    func modelInstallDecodingPreservesLegacyTurboQuantDefault() throws {
        let payload = """
        {
          "modelID": "local-test",
          "displayName": "Local Test",
          "repository": "local/test",
          "modalities": ["text"]
        }
        """
        let install = try JSONDecoder().decode(ModelInstall.self, from: Data(payload.utf8))
        #expect(install.turboQuantFamilySupport == .attentionKVFull)
    }

    @Test
    func gemmaTurboQuantPreflightCarriesProfileMetadataForExpandedFamilies() throws {
        let classifier = ModelPreflightClassifier()

        for spec in gemmaTurboQuantProfileCases {
            let result = classifier.classify(spec.preflightInput)
            let isPromotedFamily = [
                "gemma3", "gemma3_text", "gemma3n", "gemma4", "gemma4_text", "gemma4_assistant",
            ]
                .contains(spec.modelType)
            let expectedFamilySupport: TurboQuantFamilySupport =
                spec.modalities == [.text] ? .attentionKVFull : .none

            #expect(result.repository == spec.repository)
            let expectedVerification: ModelVerificationState =
                spec.modelType == "gemma4_assistant"
                ? .experimental
                : (isPromotedFamily && spec.modalities == [.text] ? .verified : .installable)
            #expect(result.verification == expectedVerification)
            #expect(result.modalities == spec.modalities)
            #expect(result.modelType == spec.modelType)
            #expect(result.processorClass == spec.processorClass)
            #expect(result.parameterCount == spec.parameterCount)
            #expect(result.keyHeadDimension == spec.headDimension)
            #expect(result.valueHeadDimension == spec.headDimension)
            #expect(result.cacheTopology == spec.expectedCacheTopology)
            #expect(result.turboQuantFamilySupport == expectedFamilySupport)
            #expect(result.estimatedBytes == spec.expectedDownloadBytes)
            #expect(result.reasons.isEmpty)

            let install = ModelInstall(
                modelID: ModelID(rawValue: spec.repository),
                displayName: spec.displayName,
                repository: spec.repository,
                modalities: result.modalities,
                verification: result.verification,
                parameterCount: result.parameterCount,
                estimatedBytes: result.estimatedBytes,
                modelType: result.modelType,
                processorClass: result.processorClass,
                keyHeadDimension: result.keyHeadDimension,
                valueHeadDimension: result.valueHeadDimension,
                cacheTopology: result.cacheTopology,
                turboQuantFamilySupport: result.turboQuantFamilySupport
            )
            let roundTrippedInstall = try JSONDecoder().decode(
                ModelInstall.self,
                from: JSONEncoder().encode(install)
            )

            #expect(roundTrippedInstall.repository == spec.repository)
            #expect(roundTrippedInstall.modelType == spec.modelType)
            #expect(roundTrippedInstall.parameterCount == spec.parameterCount)
            #expect(roundTrippedInstall.keyHeadDimension == spec.headDimension)
            #expect(roundTrippedInstall.valueHeadDimension == spec.headDimension)
            #expect(roundTrippedInstall.cacheTopology == spec.expectedCacheTopology)
            #expect(roundTrippedInstall.turboQuantFamilySupport == expectedFamilySupport)

            let hints = ModelRuntimeConfigurationHints.infer(
                repository: spec.repository,
                modelType: result.modelType,
                processorClass: result.processorClass,
                metadataFiles: [
                    "config.json": spec.configJSON,
                    "tokenizer_config.json": spec.tokenizerConfigJSON,
                ]
            )

            #expect(hints.extraEOSTokens.contains("<end_of_turn>"))
            #expect(hints.extraEOSTokens.contains("<turn|>"))
            #expect(!hints.stopStrings.contains("<start_of_turn>"))
        }
    }

    @Test
    func gemmaTurboQuantResourcePolicyKeepsLargeModelsBehindDownloadGates() throws {
        let compactPolicy = ModelDiscoveryResourcePolicy(maxDownloadBytes: 3_800_000_000)
        let proPolicy = ModelDiscoveryResourcePolicy(maxDownloadBytes: 5_500_000_000)
        let maxPolicy = ModelDiscoveryResourcePolicy(maxDownloadBytes: 8_000_000_000)
    let specsByRepository = Dictionary(
      uniqueKeysWithValues: gemmaTurboQuantProfileCases.map { ($0.repository, $0) })

        for repository in [
            "mlx-community/gemma-3-270m-it-qat-4bit",
            "mlx-community/gemma-3-1b-it-qat-4bit",
            "mlx-community/gemma-3-1b-it-4bit",
            "mlx-community/gemma-3n-E2B-it-lm-4bit",
        ] {
            let spec = try #require(specsByRepository[repository])
            let decision = compactPolicy.evaluate(spec.preflightInput, modalities: spec.modalities)
            #expect(!decision.isRejected)
            #expect(decision.knownDownloadBytes == spec.expectedDownloadBytes)
            #expect(decision.inferredParameterCount == spec.parameterCount)
            #expect(decision.inferredWeightBits == 4)
            #expect(decision.inferredWeightBitsAreExplicit)
        }

        let gemma4E2B = try #require(specsByRepository["mlx-community/gemma-4-e2b-it-OptiQ-4bit"])
    let gemma4E2BDecision = proPolicy.evaluate(
      gemma4E2B.preflightInput, modalities: gemma4E2B.modalities)
        #expect(!gemma4E2BDecision.isRejected)
        #expect(gemma4E2BDecision.knownDownloadBytes == gemma4E2B.expectedDownloadBytes)

        let gemma4E4B = try #require(specsByRepository["mlx-community/gemma-4-e4b-it-OptiQ-4bit"])
    let gemma4E4BDecision = proPolicy.evaluate(
      gemma4E4B.preflightInput, modalities: gemma4E4B.modalities)
        #expect(gemma4E4BDecision.isRejected)
        #expect(gemma4E4BDecision.knownDownloadBytes == gemma4E4B.expectedDownloadBytes)
        #expect(gemma4E4BDecision.reason?.contains("on-device discovery limit") == true)

        for repository in [
            "mlx-community/gemma-2-9b-it-4bit",
            "mlx-community/gemma-2-27b-it-4bit",
            "mlx-community/gemma-3-12b-it-qat-4bit",
            "mlx-community/gemma-3-27b-it-qat-4bit",
            "mlx-community/gemma-4-26b-it-OptiQ-4bit",
            "mlx-community/gemma-4-31b-it-OptiQ-4bit",
        ] {
            let spec = try #require(specsByRepository[repository])
            let decision = maxPolicy.evaluate(spec.preflightInput, modalities: spec.modalities)
            #expect(decision.isRejected)
            #expect(decision.knownDownloadBytes == spec.expectedDownloadBytes)
            #expect(decision.inferredParameterCount == spec.parameterCount)
            #expect(decision.inferredWeightBits == 4)
            #expect(decision.inferredWeightBitsAreExplicit)
            if spec.expectedDownloadBytes > maxPolicy.maxDownloadBytes {
                #expect(decision.reason?.contains("on-device discovery limit") == true)
            } else {
                #expect(decision.estimatedWeightBytes ?? 0 > maxPolicy.maxDownloadBytes)
                #expect(decision.reason?.contains("device profile limit") == true)
            }
        }
    }

    @Test
    func llamaAndMistralTurboQuantPreflightCarriesNestedProfileMetadata() throws {
        let classifier = ModelPreflightClassifier()
        let llama = classifier.classify(
            ModelPreflightInput(
                repository: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        configJSON: #"{"model_type":"llama","hidden_size":4096,"num_attention_heads":32}"#.data(
          using: .utf8),
                files: [
                    ModelFileInfo(path: "config.json", size: 10_000),
                    ModelFileInfo(path: "tokenizer.json", size: 8_000_000),
                    ModelFileInfo(path: "model.safetensors", size: 4_800_000_000),
                ],
                tags: ["mlx", "llama", "4bit"]
            )
        )
        let mistralSmall4 = classifier.classify(
            ModelPreflightInput(
                repository: "mlx-community/Mistral-Small-4-119B-A6B-Instruct-4bit",
        configJSON:
          #"{"model_type":"mistral3","text_config":{"model_type":"mistral4","qk_nope_head_dim":64,"qk_rope_head_dim":64,"v_head_dim":128,"n_routed_experts":128,"num_experts_per_tok":4}}"#
          .data(using: .utf8),
                files: [
                    ModelFileInfo(path: "config.json", size: 10_000),
                    ModelFileInfo(path: "tokenizer.json", size: 8_000_000),
                    ModelFileInfo(path: "model.safetensors", size: 72_000_000_000),
                ],
                tags: ["mlx", "mistral3", "4bit"]
            )
        )
        let pixtral = classifier.classify(
            ModelPreflightInput(
                repository: "mlx-community/Pixtral-12B-2409-4bit",
        configJSON:
          #"{"model_type":"pixtral","text_config":{"model_type":"mistral","head_dim":128}}"#.data(
            using: .utf8),
                processorConfigJSON: #"{"processor_class":"PixtralProcessor"}"#.data(using: .utf8),
                files: [
                    ModelFileInfo(path: "config.json", size: 10_000),
                    ModelFileInfo(path: "tokenizer.json", size: 8_000_000),
                    ModelFileInfo(path: "processor_config.json", size: 12_000),
                    ModelFileInfo(path: "model.safetensors", size: 7_200_000_000),
                ],
                tags: ["mlx", "pixtral", "image-text-to-text", "4bit"]
            )
        )
        let llama4 = classifier.classify(
            ModelPreflightInput(
                repository: "mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit",
        configJSON:
          #"{"model_type":"llama4","text_config":{"model_type":"llama4_text","head_dim":128}}"#
          .data(using: .utf8),
                processorConfigJSON: #"{"processor_class":"Llama4Processor"}"#.data(using: .utf8),
                files: [
                    ModelFileInfo(path: "config.json", size: 10_000),
                    ModelFileInfo(path: "tokenizer.json", size: 8_000_000),
                    ModelFileInfo(path: "processor_config.json", size: 12_000),
                    ModelFileInfo(path: "model.safetensors", size: 40_000_000_000),
                ],
                tags: ["mlx", "llama4", "any-to-any", "4bit"]
            )
        )
        let mllama = classifier.classify(
            ModelPreflightInput(
                repository: "mlx-community/Llama-3.2-11B-Vision-Instruct-4bit",
        configJSON: #"{"model_type":"mllama","text_config":{"model_type":"llama","head_dim":128}}"#
          .data(using: .utf8),
                processorConfigJSON: #"{"processor_class":"MllamaProcessor"}"#.data(using: .utf8),
                files: [
                    ModelFileInfo(path: "config.json", size: 10_000),
                    ModelFileInfo(path: "tokenizer.json", size: 8_000_000),
                    ModelFileInfo(path: "processor_config.json", size: 12_000),
                    ModelFileInfo(path: "model.safetensors", size: 7_200_000_000),
                ],
                tags: ["mlx", "mllama", "image-text-to-text", "4bit"]
            )
        )

        #expect(llama.verification == .verified)
        #expect(llama.modelType == "llama")
        #expect(llama.keyHeadDimension == 128)
        #expect(llama.valueHeadDimension == 128)
        #expect(llama.textConfigModelType == nil)
        #expect(llama.cacheTopology == .standardAttention)
        #expect(llama.turboQuantFamilySupport == .attentionKVFull)

        #expect(mistralSmall4.verification == .verified)
        #expect(mistralSmall4.modelType == "mistral3")
        #expect(mistralSmall4.textConfigModelType == "mistral4")
        #expect(mistralSmall4.keyHeadDimension == 128)
        #expect(mistralSmall4.valueHeadDimension == 128)
        #expect(mistralSmall4.routedExperts == 128)
        #expect(mistralSmall4.expertsPerToken == 4)
        #expect(mistralSmall4.cacheTopology == .standardAttention)
        #expect(mistralSmall4.turboQuantFamilySupport == .attentionKVFull)

        #expect(pixtral.verification == .installable)
        #expect(pixtral.modalities == [.text, .vision])
        #expect(pixtral.modelType == "pixtral")
        #expect(pixtral.textConfigModelType == "mistral")
        #expect(pixtral.keyHeadDimension == 128)
        #expect(pixtral.valueHeadDimension == 128)
        #expect(pixtral.turboQuantFamilySupport == .none)

        #expect(llama4.verification == .unsupported)
        #expect(llama4.modalities.isEmpty)
        #expect(llama4.cacheTopology == .unsupported)
        #expect(llama4.turboQuantFamilySupport == .unsupportedTopology)
    #expect(
      llama4.reasons.contains("model_type llama4 is not registered in the linked MLX runtime."))

        #expect(mllama.verification == .unsupported)
        #expect(mllama.modalities.isEmpty)
        #expect(mllama.cacheTopology == .unsupported)
        #expect(mllama.turboQuantFamilySupport == .unsupportedTopology)
    #expect(
      mllama.reasons.contains(
        "model_type mllama requires an MLX Swift LM fork with Llama 3.2 Vision registry, processor, cache topology, and TurboQuant profile support."
      ))
    }

    @Test
    func preflightMarksQwen17BRuntimeGateExperimental() throws {
        let config = try JSONSerialization.data(withJSONObject: ["model_type": "qwen3"])
        let input = ModelPreflightInput(
            repository: "mlx-community/Qwen3-1.7B-4bit",
            configJSON: config,
            files: [
                ModelFileInfo(path: "config.json", size: 10),
                ModelFileInfo(path: "tokenizer.json", size: 10),
                ModelFileInfo(path: "model.safetensors", size: 10),
            ]
        )

        let result = ModelPreflightClassifier().classify(input)

        #expect(result.verification == .experimental)
        #expect(result.reasons.contains(ModelPreflightClassifier.runtimeCompatibilityGateReason))
    }

    @Test
    func preflightPrefersExplicitHeadDimensionMetadata() throws {
        let explicit = ModelPreflightInput(
            repository: "mlx-community/Qwen3-0.6B-4bit",
      configJSON:
        #"{"model_type":"qwen3","head_dim":128,"hidden_size":2048,"num_attention_heads":32}"#.data(
          using: .utf8),
            files: [
                ModelFileInfo(path: "model.safetensors"),
                ModelFileInfo(path: "tokenizer.json"),
            ]
        )
        let nested = ModelPreflightInput(
            repository: "mlx-community/Phi-4-mini-instruct-4bit",
      configJSON:
        #"{"model_type":"phi3","text_config":{"head_dim":96,"hidden_size":3072,"num_attention_heads":32}}"#
        .data(using: .utf8),
            files: [
                ModelFileInfo(path: "model.safetensors"),
                ModelFileInfo(path: "tokenizer.json"),
            ]
        )
        let inferred = ModelPreflightInput(
            repository: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
      configJSON: #"{"model_type":"qwen2","hidden_size":2048,"num_attention_heads":16}"#.data(
        using: .utf8),
            files: [
                ModelFileInfo(path: "model.safetensors"),
                ModelFileInfo(path: "tokenizer.json"),
            ]
        )
        let legacyLlama = ModelPreflightInput(
            repository: "mlx-community/Llama-2-7b-chat-mlx",
            configJSON: #"{"model_type":"llama","dim":4096,"n_heads":32}"#.data(using: .utf8),
            files: [
                ModelFileInfo(path: "model.safetensors"),
                ModelFileInfo(path: "tokenizer.json"),
            ]
        )

        let classifier = ModelPreflightClassifier()
        let explicitResult = classifier.classify(explicit)
        let nestedResult = classifier.classify(nested)
        let inferredResult = classifier.classify(inferred)
        let legacyLlamaResult = classifier.classify(legacyLlama)

        #expect(explicitResult.keyHeadDimension == 128)
        #expect(explicitResult.valueHeadDimension == 128)
        #expect(nestedResult.keyHeadDimension == 96)
        #expect(nestedResult.valueHeadDimension == 96)
        #expect(inferredResult.keyHeadDimension == 128)
        #expect(inferredResult.valueHeadDimension == 128)
        #expect(legacyLlamaResult.keyHeadDimension == 128)
        #expect(legacyLlamaResult.valueHeadDimension == 128)
    }

    @Test
    func preflightInfersDenseTransformerParameterCountFromConfigWhenNameOmitsSize() throws {
        let config = """
        {
          "model_type": "mistral",
          "hidden_size": 4096,
          "intermediate_size": 14336,
          "num_attention_heads": 32,
          "num_key_value_heads": 8,
          "num_hidden_layers": 32,
          "vocab_size": 32000,
          "tie_word_embeddings": false
        }
        """.data(using: .utf8)
        let input = ModelPreflightInput(
            repository: "mlx-community/mistral-ft-optimized-1227-4bit-mlx",
            configJSON: config,
            files: [
                ModelFileInfo(path: "model.safetensors", size: 3_900_000_000),
                ModelFileInfo(path: "tokenizer.json", size: 2_000_000),
            ],
            tags: ["mlx", "mistral"]
        )

        let result = ModelPreflightClassifier().classify(input)
        let resourceDecision = ModelDiscoveryResourcePolicy(maxDownloadBytes: 12_000_000_000)
            .evaluate(input, modalities: result.modalities)

        #expect(result.parameterCount == 7_241_465_856)
        #expect(result.keyHeadDimension == 128)
        #expect(result.valueHeadDimension == 128)
        #expect(resourceDecision.inferredParameterCount == 7_241_465_856)
    }

    @Test
    func preflightUsesGemmaRuntimeDefaultHeadDimensionWhenConfigOmitsHeadDim() throws {
        let classifier = ModelPreflightClassifier()
        let examples: [(String, String)] = [
            (
                "mlx-community/gemma-3-4b-it-4bit",
                #"{"model_type":"gemma3","text_config":{"model_type":"gemma3_text","hidden_size":2560,"num_attention_heads":8}}"#
            ),
            (
                "mlx-community/gemma-3-text-4b-it-4bit",
                #"{"model_type":"gemma3","text_config":{"model_type":"gemma3_text","hidden_size":2560,"num_attention_heads":8,"num_key_value_heads":4}}"#
            ),
            (
                "mlx-community/gemma-3-12b-it-4bit",
                #"{"model_type":"gemma3","text_config":{"model_type":"gemma3_text","hidden_size":3840,"num_attention_heads":16,"num_key_value_heads":8}}"#
            ),
        ]

        for (repository, configJSON) in examples {
            let result = classifier.classify(
                ModelPreflightInput(
                    repository: repository,
                    configJSON: Data(configJSON.utf8),
                    files: [
                        ModelFileInfo(path: "model.safetensors"),
                        ModelFileInfo(path: "tokenizer.json"),
                    ]
                )
            )

            #expect(result.verification == .verified)
            #expect(result.keyHeadDimension == 256)
            #expect(result.valueHeadDimension == 256)
        }
    }

    @Test
    func modelDiscoveryResourcePolicyRejectsOversizedDownloadMetadata() throws {
        let policy = ModelDiscoveryResourcePolicy(maxDownloadBytes: 3_500_000_000)
        let input = ModelPreflightInput(
            repository: "mlx-community/Qwen3-4B-4bit",
            configJSON: #"{"model_type":"qwen3"}"#.data(using: .utf8),
            files: [
                ModelFileInfo(path: "model-00001-of-00002.safetensors", size: 3_900_000_000),
                ModelFileInfo(path: "model-00002-of-00002.safetensors", size: 300_000_000),
                ModelFileInfo(path: "tokenizer.json", size: 250_000),
                ModelFileInfo(path: "README.md", size: 1_000_000),
            ],
            tags: ["mlx", "qwen3", "4bit"]
        )

        let decision = policy.evaluate(input, modalities: [.text])

        #expect(decision.isRejected)
        #expect(decision.knownDownloadBytes == 4_200_250_000)
        #expect(decision.reason?.contains("on-device discovery limit") == true)
    }

    @Test
    func modelDiscoveryResourcePolicyFallsBackToParameterAndQuantizationHints() throws {
        let policy = ModelDiscoveryResourcePolicy(maxDownloadBytes: 5_000_000_000)
        let sevenB = ModelPreflightInput(
            repository: "mlx-community/Llama-3.1-8B-Instruct-4bit",
            configJSON: #"{"model_type":"llama"}"#.data(using: .utf8),
            files: [
                ModelFileInfo(path: "model.safetensors"),
                ModelFileInfo(path: "tokenizer.json"),
            ],
            tags: ["mlx", "safetensors"]
        )
        let small = ModelPreflightInput(
            repository: "mlx-community/Qwen3-3B-Instruct-4bit",
            configJSON: #"{"model_type":"qwen3"}"#.data(using: .utf8),
            files: [
                ModelFileInfo(path: "model.safetensors"),
                ModelFileInfo(path: "tokenizer.json"),
            ],
            tags: ["mlx", "safetensors"]
        )

        let rejected = policy.evaluate(sevenB, modalities: [.text])
        let allowed = policy.evaluate(small, modalities: [.text])

        #expect(rejected.isRejected)
        #expect(rejected.inferredParameterCount == 8_000_000_000)
        #expect(rejected.inferredWeightBits == 4)
        #expect(allowed.isRejected == false)
    }

    @Test
    func modelDiscoveryResourcePolicyParsesMoEAndQuantizationEdgeCases() throws {
        #expect(
            ModelDiscoveryResourcePolicy.inferredParameterCount(
                repository: "mlx-community/Mixtral-8x7B-Instruct-v0.1-4bit",
                tags: []
            ) == 56_000_000_000
        )
        #expect(
            ModelDiscoveryResourcePolicy.inferredParameterCount(
                repository: "mlx-community/ERNIE-4.5-21B-A3B-PT-4bit",
                tags: []
            ) == 21_000_000_000
        )
        #expect(
            ModelDiscoveryResourcePolicy.inferredParameterCount(
                repository: "mlx-community/Qwen3-1_7B-4bit",
                tags: []
            ) == 1_700_000_000
        )
        #expect(
            ModelDiscoveryResourcePolicy.inferredParameterCount(
                repository: "mlx-community/AMD-Llama-135m-4bit",
                tags: [
                    "dataset:cerebras/SlimPajama-627B",
                    "base_model:amd/AMD-Llama-135m",
                ]
            ) == 135_000_000
        )
        #expect(
            ModelDiscoveryResourcePolicy.inferredParameterCount(
                repository: "mlx-community/Llama-3.1-SuperNova-Lite-4bit",
                tags: ["base_model:meta-llama/Llama-3.1-8B-Instruct"]
            ) == 8_000_000_000
        )
        #expect(
            ModelDiscoveryResourcePolicy.inferredWeightBits(
                repository: "mlx-community/Qwen3-4B-Instruct-2507-mxfp8",
                tags: []
            ) == 8
        )
        #expect(
            ModelDiscoveryResourcePolicy.inferredWeightBits(
                repository: "mlx-community/llama-3.2-1B-Q4_K_M",
                tags: []
            ) == 4
        )
    }

    @Test
    func mSeriesIPadProfilesUsePhysicalMemoryTiers() throws {
        let baseProOrAir = DeviceProfile.recommended(
            for: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 2_000_000_000,
                thermalState: "nominal",
                hardwareModelIdentifier: "iPad13,4",
                metalSelfTestStatus: .passed
            )
        )
        #expect(baseProOrAir.performanceClass == .mSeriesTabletBalanced)
        #expect(baseProOrAir.recommendedMaxModelBytes == 3_500_000_000)

        let m4AirOrM5Base = DeviceProfile.recommended(
            for: RuntimeMemorySnapshot(
                physicalMemoryBytes: 12_000_000_000,
                availableMemoryBytes: 4_000_000_000,
                thermalState: "nominal",
                hardwareModelIdentifier: "iPad17,1",
                metalSelfTestStatus: .passed
            )
        )
        #expect(m4AirOrM5Base.performanceClass == .mSeriesTabletPro)
        #expect(m4AirOrM5Base.recommendedMaxModelBytes == 5_500_000_000)

        let highStoragePro = DeviceProfile.recommended(
            for: RuntimeMemorySnapshot(
                physicalMemoryBytes: 16_000_000_000,
                availableMemoryBytes: 8_000_000_000,
                thermalState: "nominal",
                hardwareModelIdentifier: "iPad16,6",
                metalSelfTestStatus: .passed
            )
        )
        #expect(highStoragePro.performanceClass == .mSeriesTabletMax)
        #expect(highStoragePro.recommendedMaxModelBytes == 8_000_000_000)
    }

    @Test
    func localRuntimeSafetyPausesGenerationUnderCriticalDevicePressure() {
        let thermal = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 2_500_000_000,
                thermalState: "critical"
            )
        )
        #expect(!thermal.allowed)
        #expect(thermal.constrainedModeActive)
        #expect(thermal.requiresImmediateUnload)

        let seriousThermal = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 2_500_000_000,
                thermalState: "serious"
            )
        )
        #expect(seriousThermal.allowed)
        #expect(seriousThermal.pressureReason == .thermalSerious)
        #expect(seriousThermal.constrainedModeActive)
        #expect(!seriousThermal.requiresImmediateUnload)

        let memory = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 500_000_000,
                thermalState: "nominal"
            )
        )
        #expect(!memory.allowed)
        #expect(memory.constrainedModeActive)
        #expect(memory.requiresImmediateUnload)
        #expect(memory.recommendedMaxContextTokens <= 2_048)
    }

    @Test
    func localRuntimeSafetyConstrainsProfileUnderModeratePressure() {
        let profile = RuntimeProfile(
            quantization: QuantizationProfile(maxKVSize: 16_384),
            streamExperts: true,
            expertStreamingMode: .directNVMe,
            mtpEnabled: true,
            prefillStepSize: 1_024,
            speculativeDecodingEnabled: true
        )
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 1_250_000_000,
                thermalState: "fair"
            )
        )
        let constrained = safety.constrainedRuntimeProfile(profile)

        #expect(safety.allowed)
        #expect(safety.constrainedModeActive)
        #expect(!safety.requiresImmediateUnload)
        #expect(constrained.quantization.maxKVSize == 2_048)
        #expect(constrained.prefillStepSize == 256)
        #expect(!constrained.streamExperts)
        #expect(!constrained.mtpEnabled)
        #expect(!constrained.speculativeDecodingEnabled)
    }

    @Test
    func localGenerationPipelinePlanDoesNotClampOrdinaryLoadedModelHeadroom() {
        let profile = RuntimeProfile(
            quantization: QuantizationProfile(
                maxKVSize: 4_096,
                algorithm: .none,
                kvCacheStrategy: .none,
                preset: nil,
                requestedBackend: nil,
                activeBackend: nil,
                activeAttentionPath: nil
            )
        )
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 1_800_000_000,
                thermalState: "nominal"
            )
        )
        let plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: 2_048,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 1_800_000_000
        )

        #expect(safety.allowed)
        #expect(safety.pressureReason == .none)
        #expect(plan.pressureCompletionTokenLimit == nil)
        #expect(plan.reservedCompletionTokens == 2_048)
        #expect(plan.effectiveMaxTokens == 2_048)
        #expect(!plan.maxTokensClamped)
        #expect(
            plan.providerMetadata()[LocalProviderMetadataKeys.generationEffectiveMaxTokens] == "2048"
        )
        #expect(
            plan.providerMetadata()[LocalProviderMetadataKeys.generationInitialAvailableMemoryBytes]
                == "1800000000"
        )
    }

    @Test
    func localGenerationPipelinePlanHonorsSmallerRequestedCompletionBudget() {
        let profile = RuntimeProfile(quantization: QuantizationProfile(maxKVSize: 4_096))
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 1_800_000_000,
                thermalState: "nominal"
            )
        )
        let plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: 20,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 1_800_000_000
        )

        #expect(plan.pressureCompletionTokenLimit == 512)
        #expect(plan.reservedCompletionTokens == 20)
        #expect(plan.effectiveMaxTokens == 20)
        #expect(!plan.maxTokensClamped)
    }

    @Test
    func localGenerationPipelinePlanCapsTurboQuantCompletionForLoadedModelHeadroom() {
        let profile = RuntimeProfile(quantization: QuantizationProfile(maxKVSize: 16_384))
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 2_533_000_000,
                thermalState: "nominal"
            )
        )
        let plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: 2_048,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 2_533_000_000
        )

        #expect(safety.pressureReason == .none)
        #expect(plan.pressureCompletionTokenLimit == 512)
        #expect(plan.reservedCompletionTokens == 512)
        #expect(plan.effectiveMaxTokens == 512)
        #expect(plan.maxTokensClamped)
    }

    @Test
    func localGenerationPipelinePlanCapsHybridTurboQuantCompletionForNativeStateHeadroom() {
        let profile = RuntimeProfile(
            quantization: QuantizationProfile(
                maxKVSize: 16_384,
                turboQuantProfileID: "qwen3.5-0.8b",
                turboQuantProfileSource: "bundled"
            )
        )
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 2_900_000_000,
                thermalState: "nominal"
            )
        )
        let plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: 2_048,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 2_900_000_000
        )

        #expect(safety.pressureReason == .none)
        #expect(plan.pressureCompletionTokenLimit == 256)
        #expect(plan.reservedCompletionTokens == 256)
        #expect(plan.effectiveMaxTokens == 256)
        #expect(plan.maxTokensClamped)
    }

    @Test
    func localGenerationPipelinePlanCapsQualitySensitiveTurboQuantFamilies() {
        let cases: [(String, Int64, Int)] = [
            ("gemma-3-1b", 2_900_000_000, 256),
            ("llama-3.2-3b", 1_600_000_000, 128),
            ("qwen3.5-2b", 2_900_000_000, 192),
        ]
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 2_900_000_000,
                thermalState: "nominal"
            )
        )

        for (profileID, availableMemoryBytes, expectedLimit) in cases {
            let profile = RuntimeProfile(
                quantization: QuantizationProfile(
                    maxKVSize: 16_384,
                    turboQuantProfileID: profileID,
                    turboQuantProfileSource: "bundled"
                )
            )
            let plan = LocalGenerationPipelinePlan(
                requestedCompletionTokens: 2_048,
                profile: profile,
                safety: safety,
                initialAvailableMemoryBytes: availableMemoryBytes
            )

            #expect(plan.pressureCompletionTokenLimit == expectedLimit)
            #expect(plan.reservedCompletionTokens == expectedLimit)
            #expect(plan.effectiveMaxTokens == expectedLimit)
            #expect(plan.maxTokensClamped)
        }
    }

    @Test
    func localGenerationPipelinePlanFitsCompletionBudgetToContextAfterTokenization() {
        let profile = RuntimeProfile(quantization: QuantizationProfile(maxKVSize: 4_096))
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 1_800_000_000,
                thermalState: "nominal"
            )
        )
        var plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: 2_048,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 1_800_000_000
        )

        let fitsContext = plan.constrainToContext(promptTokenCount: 4_080, maxContextTokens: 4_096)
        #expect(fitsContext)
        #expect(plan.reservedCompletionTokens == 16)
        #expect(plan.effectiveMaxTokens == 16)
        #expect(plan.maxTokensClamped)
        #expect(plan.effectiveMaxKVSize == 4_096)
        #expect(!plan.maxKVSizeClamped)
    }

    @Test
    func localGenerationPipelinePlanClampsContinuationBeforeContextFailure() {
        let profile = RuntimeProfile(quantization: QuantizationProfile(maxKVSize: 16_384))
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 1_800_000_000,
                thermalState: "nominal"
            )
        )
        var plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: 2_048,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 1_800_000_000
        )

        let continuationFits = plan.fitPreparedPrompt(
            promptTokenCount: 15_900,
            maxContextTokens: 16_384
        )
        #expect(continuationFits)
        #expect(plan.reservedCompletionTokens == 484)
        #expect(plan.effectiveMaxTokens == 484)
        #expect(plan.maxTokensClamped)

        let promptTooLarge = plan.fitPreparedPrompt(
            promptTokenCount: 16_385,
            maxContextTokens: 16_384
        )
        #expect(!promptTooLarge)
    }

    @Test
    func localGenerationPipelinePlanRightSizesKVWindowAfterTokenization() {
        let profile = RuntimeProfile(quantization: QuantizationProfile(maxKVSize: 4_096))
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 3_200_000_000,
                thermalState: "nominal"
            )
        )
        var plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: 2_048,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 3_200_000_000
        )

        let fitsContext = plan.fitPreparedPrompt(promptTokenCount: 47, maxContextTokens: 4_096)
        #expect(fitsContext)
        #expect(plan.reservedCompletionTokens == 2_048)
        #expect(plan.effectiveMaxTokens == 2_048)
        #expect(plan.effectiveMaxKVSize == 2_304)
        #expect(plan.maxKVSizeClamped)
        #expect(
            plan.providerMetadata()[LocalProviderMetadataKeys.generationEffectiveMaxKVSize] == "2304"
        )
        #expect(
            plan.providerMetadata()[LocalProviderMetadataKeys.generationMaxKVSizeClamped] == "true"
        )
    }

    @Test
    func localGenerationPipelinePlanPreservesFullKVWindowForUnboundedCompletion() {
        let profile = RuntimeProfile(quantization: QuantizationProfile(maxKVSize: 4_096))
        let safety = LocalRuntimeSafetyAssessment(
            allowed: true,
            recommendedMaxContextTokens: 4_096,
            recommendedPrefillStepSize: 512
        )
        var plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: nil,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 3_000_000_000
        )

        let fitsContext = plan.fitPreparedPrompt(promptTokenCount: 47, maxContextTokens: 4_096)
        #expect(fitsContext)
        #expect(plan.effectiveMaxTokens == nil)
        #expect(plan.effectiveMaxKVSize == 4_096)
        #expect(!plan.maxKVSizeClamped)
    }

    @Test
    func localGenerationPipelinePlanUsesEmergencyLowMemoryCap() {
        let profile = RuntimeProfile(quantization: QuantizationProfile(maxKVSize: 4_096))
        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 1_100_000_000,
                thermalState: "nominal"
            )
        )
        let plan = LocalGenerationPipelinePlan(
            requestedCompletionTokens: nil,
            profile: profile,
            safety: safety,
            initialAvailableMemoryBytes: 1_100_000_000
        )

        #expect(plan.pressureCompletionTokenLimit == 256)
        #expect(plan.reservedCompletionTokens == 256)
        #expect(plan.effectiveMaxTokens == 256)
        #expect(plan.maxTokensClamped)
    }

    @Test
    func lowPowerModeKeepsContextWindowButConservesPrefill() {
        let profile = DeviceProfile.recommended(
            for: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 2_500_000_000,
                thermalState: "nominal",
                hardwareModelIdentifier: "iPhone16,2",
                lowPowerModeEnabled: true
            )
        )

        #expect(profile.performanceClass == .a17Pro)
        #expect(profile.runtimePressureReason == .lowPower)
        #expect(!profile.thermalDownshiftActive)
        #expect(profile.recommendedContextTokens == 16_384)
        #expect(profile.recommendedSmallModelContextTokens == 24_576)
        #expect(profile.recommendedPrefillStepSize == 256)

        let safety = LocalRuntimeSafetyPolicy.assess(
            snapshot: RuntimeMemorySnapshot(
                physicalMemoryBytes: 8_000_000_000,
                availableMemoryBytes: 2_500_000_000,
                thermalState: "nominal",
                hardwareModelIdentifier: "iPhone16,2",
                lowPowerModeEnabled: true
            )
        )
        #expect(safety.allowed)
        #expect(safety.pressureReason == .lowPower)
        #expect(safety.recommendedMaxContextTokens == 16_384)
        #expect(safety.recommendedPrefillStepSize == 256)
    }

    @Test
    func calculatorHonorsOperatorPrecedenceAndRejectsDivisionByZero() throws {
        let evaluator = SafeCalculatorEvaluator()

        #expect(try evaluator.evaluate("2 + 3 * 4") == 14)
        #expect(try evaluator.evaluate("(2 + 3) * 4") == 20)
        #expect(throws: CalculatorEvaluationError.divisionByZero) {
            try evaluator.evaluate("1 / 0")
        }
    }

    @Test
    func userSuppliedConfigurationValidationThrows() throws {
        #expect(throws: VaultChunkerConfigurationError.invalidMaxCharacterCount(0)) {
            _ = try VaultChunker.Configuration(maxCharacterCount: 0)
        }
        #expect(throws: VaultChunkerConfigurationError.overlapNotSmallerThanMax(overlap: 8, max: 8)) {
            _ = try VaultChunker.Configuration(maxCharacterCount: 8, overlapCharacterCount: 8)
        }
        #expect(throws: CalculatorEvaluationError.invalidMaximumExpressionLength(0)) {
            _ = try SafeCalculatorEvaluator(maximumExpressionLength: 0)
        }
        #expect(throws: EndpointSecurityError.insecureRemoteHTTP(URL(string: "http://example.com")!)) {
            _ = try HuggingFaceModelCatalogService(baseURL: URL(string: "http://example.com")!)
        }
    }

    @Test
    func timeAndDateToolsReturnDeterministicLocalResults() async throws {
        let fixed = ISO8601DateFormatter().date(from: "2026-05-18T10:30:00Z")!
        let timeSpec = try TimeNowTool.spec(now: { fixed })
        let timeOutput = try await timeSpec.call(TimeNowInput(timeZone: "UTC"))
        #expect(timeOutput.iso8601 == "2026-05-18T10:30:00.000Z")
        #expect(timeOutput.secondsFromGMT == 0)

        let dateSpec = try DateCalculateTool.spec(now: { fixed })
        let friday = try await dateSpec.call(
            DateCalculateInput(
                operation: "nextWeekday",
                date: "2026-05-18",
                weekday: "Friday",
                timeZone: "UTC"
            )
        )
        #expect(friday.resultDate == "2026-05-22")

        let added = try await dateSpec.call(
            DateCalculateInput(
                operation: "add",
                date: "2026-05-18",
                amount: 2,
                unit: "weeks",
                timeZone: "UTC"
            )
        )
        #expect(added.resultDate == "2026-06-01")
    }

    @Test
    func attachmentReadToolOnlyReadsProviderApprovedAttachment() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "notes.txt")
        try "alpha beta gamma delta".write(to: url, atomically: true, encoding: .utf8)
        let attachment = ChatAttachment(
            kind: .document,
            fileName: "notes.txt",
            contentType: "text/plain",
            localURL: url,
            byteCount: 22
        )

        let spec = try AttachmentReadTool.spec { requestedID in
            requestedID == attachment.id ? attachment : nil
        }
        let output = try await spec.call(
            AttachmentReadInput(
                attachmentID: attachment.id.uuidString,
                offset: 6,
                maxCharacters: 4
            )
        )
        #expect(output.text == "beta")
        #expect(output.truncated)

        do {
            _ = try await spec.call(AttachmentReadInput(attachmentID: UUID().uuidString))
            Issue.record("attachment.read should reject attachments outside the current run context")
        } catch AgentError.permissionDenied {
        }
    }

    @Test
    func webFetchExtractsReadableHTMLText() {
        let html = """
        <html><head><title>Example &amp; Test</title><style>.x{}</style></head>
        <body><h1>Hello</h1><script>ignore()</script><p>Readable&nbsp;text.</p></body></html>
        """
        let parsed = WebFetchTool.readableText(data: Data(html.utf8), contentType: "text/html")
        #expect(parsed.title == "Example & Test")
        #expect(parsed.text.contains("Hello"))
        #expect(parsed.text.contains("Readable text."))
        #expect(!parsed.text.contains("ignore"))
    }

    @Test
    func chatRequestExecutionContextDefaultsToChatAndRoundTripsAgent() throws {
        let legacy = """
        {"modelID":"local","messages":[{"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"hi"}]}
        """
        let decoded = try JSONDecoder().decode(ChatRequest.self, from: Data(legacy.utf8))
        #expect(decoded.executionContext == .chat)

        let request = ChatRequest(
            modelID: "local",
            messages: [ChatMessage(role: .user, content: "search")],
            executionContext: .agent
        )
    let roundTripped = try JSONDecoder().decode(
      ChatRequest.self, from: JSONEncoder().encode(request))
        #expect(roundTripped.executionContext == .agent)
    }

    @Test
    func agentEvidenceFormatterProducesReadableWebEvidence() throws {
        let resultsData = try JSONSerialization.data(withJSONObject: [
      ["title": "Pines Source", "url": "https://example.com/pines", "snippet": "Useful context."]
        ])
        let rawData = try JSONSerialization.data(withJSONObject: [
      "resultsJSON": String(decoding: resultsData, as: UTF8.self)
        ])
        let evidence = AgentEvidenceFormatter.modelVisibleOutput(
            toolName: "web.search",
            rawOutputJSON: String(decoding: rawData, as: UTF8.self)
        )

        #expect(evidence.contains("Tool evidence from web.search"))
        #expect(evidence.contains("Pines Source"))
        #expect(evidence.contains("https://example.com/pines"))
        #expect(!evidence.contains("resultsJSON"))
    }

    @Test
    func agentEvidenceFormatterTruncatesLargeFetches() throws {
    let rawData = try JSONSerialization.data(
      withJSONObject: [
            "url": "https://example.com",
            "finalURL": "https://example.com/final",
            "statusCode": 200,
            "title": "Large",
            "text": String(repeating: "x", count: 5_000),
            "truncated": true,
        ] as [String: Any])
        let evidence = AgentEvidenceFormatter.modelVisibleOutput(
            toolName: WebFetchTool.name,
            rawOutputJSON: String(decoding: rawData, as: UTF8.self),
            textLimit: 1_000
        )

        #expect(evidence.contains("Tool evidence from web.fetch"))
        #expect(evidence.contains("https://example.com/final"))
        #expect(evidence.contains("[Evidence truncated.]"))
        #expect(evidence.count < 1_100)
    }

    @Test
    func agentEvidenceFormatterDoesNotExposeRawJSONOnSchemaMismatch() throws {
        let rawData = try JSONSerialization.data(withJSONObject: [
            "unexpected": [
                "title": "Fallback Title",
                "url": "https://example.com/fallback",
                "snippet": "Readable fallback field.",
      ]
        ])
        let evidence = AgentEvidenceFormatter.modelVisibleOutput(
            toolName: "web.search",
            rawOutputJSON: String(decoding: rawData, as: UTF8.self)
        )

        #expect(evidence.contains("Tool evidence from web.search"))
        #expect(evidence.contains("The tool output did not match the expected schema."))
        #expect(evidence.contains("Fallback Title"))
        #expect(evidence.contains("https://example.com/fallback"))
        #expect(!evidence.contains("\"unexpected\""))
        #expect(!evidence.contains("{"))
    }

    @Test
    func privateLocalToolsAreMarkedAsCloudContext() throws {
        let attachmentSpec = try AnyToolSpec(AttachmentReadTool.spec { _ in nil })
    let vaultSpec = try AnyToolSpec(
      VaultSearchTool.spec { query, _ in
            VaultSearchOutput(query: query, searchMode: "lexical", results: [])
        })
    let conversationSpec = try AnyToolSpec(
      ConversationSearchTool.spec(repository: EmptyConversationRepository()))

        #expect(attachmentSpec.permissions.contains(.cloudContext))
        #expect(vaultSpec.permissions.contains(.cloudContext))
        #expect(conversationSpec.permissions.contains(.cloudContext))
    }

    @Test
    func agentPolicyDecodesMissingCloudContextScopeAsUnrestricted() throws {
        let data = Data(
            """
            {
              "executionMode": "cloudAllowed",
              "maxSteps": 3,
              "maxToolCalls": 2,
              "maxWallTimeSeconds": 30,
              "allowedDomains": [],
              "requiresConsentForNetwork": false,
              "requiresConsentForBrowser": false,
              "allowsCloudContext": true
            }
            """.utf8
        )

        let policy = try JSONDecoder().decode(AgentPolicy.self, from: data)

        #expect(policy.allowsCloudContext)
        #expect(policy.cloudContextScope == .unrestricted)
    }

    @Test
    func vaultSearchFiltersResultsToAllowedCloudContextDocuments() async throws {
        let approvedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secretID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let approved = Self.vaultSearchItem(
      documentID: approvedID, title: "Approved", text: "approved context")
    let secret = Self.vaultSearchItem(
      documentID: secretID, title: "Secret", text: "TOP_SECRET_TOKEN")
        let registry = ToolRegistry()
        let spec = try VaultSearchTool.spec(allowedDocumentIDs: { [approvedID] }) { query, _ in
            VaultSearchOutput(query: query, searchMode: "lexical", results: [approved, secret])
        }
        try await registry.register(spec)

        let output: VaultSearchOutput = try await registry.call(
            VaultSearchTool.name,
            input: VaultSearchInput(query: "token")
        )

        #expect(output.results.map(\.documentID) == [approvedID.uuidString])
        #expect(!output.resultsJSON.contains("TOP_SECRET_TOKEN"))
    }

    @Test
    func vaultReadRejectsDocumentsOutsideAllowedCloudContext() async throws {
        let approvedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secretID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let repository = FixtureVaultRepository(
            documents: [
                VaultDocumentRecord(id: approvedID, title: "Approved", sourceType: "text", chunkCount: 1),
                VaultDocumentRecord(id: secretID, title: "Secret", sourceType: "text", chunkCount: 1),
            ],
            chunksByDocument: [
        approvedID: [
          Self.vaultChunk(id: "approved-0", documentID: approvedID, text: "approved context")
        ],
                secretID: [Self.vaultChunk(id: "secret-0", documentID: secretID, text: "TOP_SECRET_TOKEN")],
            ]
        )
        let registry = ToolRegistry()
        try await registry.register(
            try VaultReadTool.spec(repository: repository, allowedDocumentIDs: { [approvedID] })
        )

        let output: VaultReadOutput = try await registry.call(
            VaultReadTool.name,
            input: VaultReadInput(documentID: approvedID.uuidString)
        )
        #expect(output.text.contains("approved context"))

        do {
            let _: VaultReadOutput = try await registry.call(
                VaultReadTool.name,
                input: VaultReadInput(documentID: secretID.uuidString)
            )
            Issue.record("vault.read should reject unapproved documents")
        } catch AgentError.permissionDenied {
        } catch {
            Issue.record("vault.read failed with unexpected error: \(error)")
        }

        do {
            let _: VaultReadOutput = try await registry.call(
                VaultReadTool.name,
                input: VaultReadInput(chunkID: "secret-0")
            )
            Issue.record("vault.read should reject unapproved chunks")
        } catch AgentError.permissionDenied {
        } catch {
            Issue.record("vault.read failed with unexpected error: \(error)")
        }
    }

    @Test
    func conversationSearchCanBeDisabledForSelectedCloudContextRuns() async throws {
        let registry = ToolRegistry()
        try await registry.register(
      try ConversationSearchTool.spec(
        repository: EmptyConversationRepository(), allowsSearch: { false })
        )

        do {
            let _: ConversationSearchOutput = try await registry.call(
                ConversationSearchTool.name,
                input: ConversationSearchInput(query: "secret")
            )
            Issue.record("conversation.search should reject selected cloud-context runs")
        } catch AgentError.permissionDenied {
        } catch {
            Issue.record("conversation.search failed with unexpected error: \(error)")
        }
    }

    @Test
    func toolRegistryEnforcesDeclaredTimeouts() async throws {
        let registry = ToolRegistry()
        let spec = try ToolSpec<CalculatorInput, CalculatorOutput>(
            name: "calculator.slow",
            description: "Slow calculator used to verify timeout behavior.",
      inputSchema: ToolIOSchema(
        properties: ["expression": .init(type: .string)], required: ["expression"]),
      outputSchema: ToolIOSchema(properties: [
        "value": .init(type: .number), "formatted": .init(type: .string),
      ]),
            permissions: [.localComputation],
            sideEffect: .none,
            networkPolicy: .noNetwork,
            timeoutSeconds: 1,
            explanationRequired: false
        ) { _ in
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return CalculatorOutput(value: 1, formatted: "1")
        }
        try await registry.register(spec)

        do {
            _ = try await registry.callRaw("calculator.slow", inputJSON: #"{"expression":"1"}"#)
            Issue.record("slow tool should time out")
        } catch ToolRegistryError.toolTimedOut(let name, let timeoutSeconds) {
            #expect(name == "calculator.slow")
            #expect(timeoutSeconds == 1)
        }
    }

    @Test
    func downloadResumePlanUsesDurableOpenEndedRanges() {
        let plan = ModelDownloadResumePlan(
            expectedBytes: 695_283_921,
            existingBytes: 64 * 1024 * 1024
        )

        #expect(plan.isComplete == false)
        #expect(plan.resumeOffset == 67_108_864)
        #expect(plan.rangeHeader == "bytes=67108864-")
        #expect(plan.expectedBytes == 695_283_921)
    }

    @Test
    func downloadResumePlanRecognizesCompletedFiles() {
        let plan = ModelDownloadResumePlan(expectedBytes: 128, existingBytes: 128)

        #expect(plan.isComplete)
        #expect(plan.rangeHeader == nil)
        #expect(plan.resumeOffset == 128)
    }

    @Test
    func downloadStagingManifestPreservesReusableFileProgressAcrossPlanRefresh() {
        var manifest = ModelDownloadStagingManifest(
            repository: "example/model",
            revision: "main",
            totalBytes: 128
        )
        manifest.updateFile(
            path: "model.safetensors",
            expectedBytes: 128,
            checksum: "abc",
            receivedBytes: 64,
            status: .downloading
        )

        manifest.mergeDownloadPlan(
            repository: "example/model",
            revision: "main",
            totalBytes: 160,
            files: [
                ModelFileInfo(path: "config.json", size: 32),
                ModelFileInfo(path: "model.safetensors", size: 128, oid: "def"),
            ]
        )

        #expect(manifest.totalBytes == 160)
        #expect(manifest.reusableBytes == 64)
        #expect(manifest.file(path: "model.safetensors")?.receivedBytes == 64)
        #expect(manifest.file(path: "model.safetensors")?.checksum == "def")
        #expect(manifest.file(path: "config.json")?.status == .pending)
    }

  private func cloudConfiguration(kind: CloudProviderKind, baseURL: String)
    -> CloudProviderConfiguration
  {
        CloudProviderConfiguration(
            id: ProviderID(rawValue: kind.rawValue),
            kind: kind,
            displayName: kind.rawValue,
            baseURL: URL(string: baseURL)!,
            defaultModelID: "model",
            validationStatus: .unvalidated,
            keychainService: "test",
            keychainAccount: "test"
        )
    }
}

private actor InMemoryProviderLifecycleRepository:
    ProviderFileRepository,
    ProviderArtifactRepository,
    ProviderCacheRepository,
    ProviderBatchRepository,
    ProviderLiveSessionRepository,
    ProviderStructuredOutputRepository,
    ProviderModelCapabilityRepository,
    ProviderResearchRunRepository
{
    private var files = [String: ProviderFileRecord]()
    private var artifacts = [String: ProviderArtifactRecord]()
    private var caches = [String: ProviderCacheRecord]()
    private var batches = [String: ProviderBatchRecord]()
    private var liveSessions = [String: ProviderLiveSessionRecord]()
    private var structuredOutputs = [UUID: ProviderStructuredOutputRecord]()
    private var modelCapabilities = [String: ProviderModelCapabilityRecord]()
    private var researchRuns = [String: ProviderResearchRunRecord]()

    func listProviderFiles(providerID: ProviderID?) async throws -> [ProviderFileRecord] {
        sorted(files.values.filter { providerID == nil || $0.providerID == providerID })
    }

    func upsertProviderFile(_ file: ProviderFileRecord) async throws {
        files[file.id] = file
    }

    func deleteProviderFile(id: String) async throws {
        files[id] = nil
    }

    func listProviderArtifacts(responseID: String?) async throws -> [ProviderArtifactRecord] {
        sorted(artifacts.values.filter { responseID == nil || $0.responseID == responseID })
    }

    func upsertProviderArtifact(_ artifact: ProviderArtifactRecord) async throws {
        artifacts[artifact.id] = artifact
    }

    func deleteProviderArtifact(id: String) async throws {
        artifacts[id] = nil
    }

  func listProviderCaches(providerID: ProviderID?, kind: String?) async throws
    -> [ProviderCacheRecord]
  {
    sorted(
      caches.values.filter { cache in
            (providerID == nil || cache.providerID == providerID) && (kind == nil || cache.kind == kind)
        })
    }

    func upsertProviderCache(_ cache: ProviderCacheRecord) async throws {
        caches[cache.id] = cache
    }

    func deleteProviderCache(id: String) async throws {
        caches[id] = nil
    }

    func listProviderBatches(providerID: ProviderID?) async throws -> [ProviderBatchRecord] {
        sorted(batches.values.filter { providerID == nil || $0.providerID == providerID })
    }

    func upsertProviderBatch(_ batch: ProviderBatchRecord) async throws {
        batches[batch.id] = batch
    }

    func deleteProviderBatch(id: String) async throws {
        batches[id] = nil
    }

  func listProviderLiveSessions(providerID: ProviderID?) async throws -> [ProviderLiveSessionRecord]
  {
        sorted(liveSessions.values.filter { providerID == nil || $0.providerID == providerID })
    }

    func upsertProviderLiveSession(_ session: ProviderLiveSessionRecord) async throws {
        liveSessions[session.id] = session
    }

    func deleteProviderLiveSession(id: String) async throws {
        liveSessions[id] = nil
    }

  func listProviderStructuredOutputs(responseID: String?) async throws
    -> [ProviderStructuredOutputRecord]
  {
        structuredOutputs.values
            .filter { responseID == nil || $0.responseID == responseID }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func upsertProviderStructuredOutput(_ output: ProviderStructuredOutputRecord) async throws {
        structuredOutputs[output.id] = output
    }

    func deleteProviderStructuredOutput(id: UUID) async throws {
        structuredOutputs[id] = nil
    }

  func listProviderModelCapabilities(providerID: ProviderID?) async throws
    -> [ProviderModelCapabilityRecord]
  {
        sorted(modelCapabilities.values.filter { providerID == nil || $0.providerID == providerID })
    }

    func upsertProviderModelCapability(_ capability: ProviderModelCapabilityRecord) async throws {
        modelCapabilities[capability.id] = capability
    }

    func deleteProviderModelCapability(providerID: ProviderID, modelID: ModelID) async throws {
        modelCapabilities["\(providerID.rawValue)::\(modelID.rawValue)"] = nil
    }

  func listProviderResearchRuns(providerID: ProviderID?, status: String?) async throws
    -> [ProviderResearchRunRecord]
  {
    sorted(
      researchRuns.values.filter { run in
        (providerID == nil || run.providerID == providerID)
          && (status == nil || run.status == status)
        })
    }

    func upsertProviderResearchRun(_ run: ProviderResearchRunRecord) async throws {
        researchRuns[run.id] = run
    }

    func deleteProviderResearchRun(id: String) async throws {
        researchRuns[id] = nil
    }

    private func sorted<T: Identifiable>(_ values: some Sequence<T>) -> [T] where T.ID == String {
        values.sorted { $0.id < $1.id }
    }
}

private enum GeminiProviderLifecycleRecordMapperFixture {
    static func providerFile(from object: JSONValue, providerID: ProviderID) -> ProviderFileRecord? {
        guard let fields = object.objectValue,
              let id = fields.string("name")
        else { return nil }
        return ProviderFileRecord(
            id: id,
            providerID: providerID,
            providerKind: .gemini,
            purpose: fields.string("purpose") ?? "prompt",
            fileName: fields.string("displayName") ?? fields.string("filename") ?? id,
            contentType: fields.string("mimeType"),
            byteCount: Int64(fields.int("sizeBytes") ?? fields.int("size_bytes") ?? 0),
            status: normalizedStatus(fields.string("state") ?? fields.string("status")),
            sha256: fields.string("sha256Hash"),
            providerObject: fields.string("uri"),
            providerMetadata: metadata(from: fields["metadata"])
        )
    }

  static func providerCache(from object: JSONValue, providerID: ProviderID) -> ProviderCacheRecord?
  {
        guard let fields = object.objectValue,
              let id = fields.string("name")
        else { return nil }
        let usage = fields["usageMetadata"]
        return ProviderCacheRecord(
            id: id,
            providerID: providerID,
            providerKind: .gemini,
            kind: "context_cache",
            name: fields.string("displayName") ?? id,
            modelID: normalizedModelID(fields.string("model")),
            status: normalizedStatus(fields.string("state") ?? fields.string("status") ?? "ACTIVE"),
      usageBytes: Int64(
        usage?.objectValue?.int("cachedContentTokenCount") ?? usage?.objectValue?.int(
          "totalTokenCount") ?? 0),
            itemCounts: usage,
            configuration: fields["configuration"],
            metadata: metadata(from: fields["metadata"])
        )
    }

    static func providerCache(
        fromCachedContentName name: String,
        providerID: ProviderID,
        modelID: ModelID,
        metadata: [String: String]
    ) -> ProviderCacheRecord {
    let cacheUsage = jsonValue(
      fromJSONString: metadata[CloudProviderMetadataKeys.geminiCacheUsageJSON])
        let cachedTokens = cacheUsage?.objectValue?.int("cachedContentTokenCount") ?? 0
        return ProviderCacheRecord(
            id: name,
            providerID: providerID,
            providerKind: .gemini,
            kind: "context_cache",
            name: name,
            modelID: modelID,
            status: "active",
            usageBytes: Int64(cachedTokens),
            itemCounts: cacheUsage,
            metadata: metadata
        )
    }

  static func providerBatch(from object: JSONValue, providerID: ProviderID) -> ProviderBatchRecord?
  {
        guard let fields = object.objectValue,
              let id = fields.string("name")
        else { return nil }
        return ProviderBatchRecord(
            id: id,
            providerID: providerID,
            providerKind: .gemini,
            endpoint: fields.string("endpoint") ?? "",
            status: normalizedStatus(fields.string("state") ?? fields.string("status")),
            inputFileID: fields["inputConfig"]?.objectValue?.string("fileName"),
            outputFileID: fields["outputInfo"]?.objectValue?.string("fileName"),
            errorFileID: fields["errorInfo"]?.objectValue?.string("fileName"),
            requestCounts: fields["requestCounts"],
            metadata: metadata(from: fields["metadata"])
        )
    }

  static func providerLiveSession(from object: JSONValue, providerID: ProviderID)
    -> ProviderLiveSessionRecord?
  {
        guard let fields = object.objectValue,
              let id = fields.string("name")
        else { return nil }
        return ProviderLiveSessionRecord(
            id: id,
            providerID: providerID,
            providerKind: .gemini,
            modelID: normalizedModelID(fields.string("model")) ?? "gemini-live",
            status: normalizedStatus(fields.string("state") ?? fields.string("status") ?? "ACTIVE"),
            modalities: fields.arrayStrings("modalities"),
            expiresAt: fields.string("expireTime").flatMap(iso8601Date),
            providerMetadata: metadata(from: fields["metadata"])
        )
    }

    static func providerArtifact(
        from part: JSONValue,
        providerID: ProviderID,
        responseID: String?,
        toolCallID: String?
    ) -> ProviderArtifactRecord? {
        guard let fields = part.objectValue else { return nil }
        if let fileData = fields["fileData"]?.objectValue,
      let fileURI = fileData.string("fileUri")
    {
            return ProviderArtifactRecord(
                id: fileURI,
                providerID: providerID,
                providerKind: .gemini,
                responseID: responseID,
                toolCallID: toolCallID,
                providerFileID: fileURI,
                kind: "file_data",
                contentType: fileData.string("mimeType")
            )
        }
        if let inlineData = fields["inlineData"]?.objectValue,
      let data = inlineData.string("data")
    {
            return ProviderArtifactRecord(
                id: "gemini-inline-\(responseID ?? UUID().uuidString)-\(toolCallID ?? "model")",
                providerID: providerID,
                providerKind: .gemini,
                responseID: responseID,
                toolCallID: toolCallID,
                kind: "inline_data",
                contentType: inlineData.string("mimeType"),
                byteCount: Int64(Data(base64Encoded: data)?.count ?? 0)
            )
        }
        return nil
    }

    static func providerArtifacts(
        fromGeminiMetadata metadata: [String: String],
        providerID: ProviderID,
        responseID: String?
    ) -> [ProviderArtifactRecord] {
    let fileReferences = jsonArray(
      fromJSONString: metadata[CloudProviderMetadataKeys.geminiFileReferencesJSON])
        let fileArtifacts = fileReferences.map { object in
            ProviderArtifactRecord(
                id: object.string("fileUri") ?? UUID().uuidString,
                providerID: providerID,
                providerKind: .gemini,
                responseID: responseID,
                providerFileID: object.string("fileUri"),
                kind: "file_data",
                contentType: object.string("mimeType")
            )
        }
    let inlineArtifacts = jsonArray(
      fromJSONString: metadata[CloudProviderMetadataKeys.geminiArtifactsJSON]
    ).map { object in
            ProviderArtifactRecord(
                id: object.string("id") ?? object.string("fileUri") ?? UUID().uuidString,
                providerID: providerID,
                providerKind: .gemini,
                responseID: responseID,
                kind: object.string("type") ?? "inline_data",
                contentType: object.string("mimeType"),
                byteCount: Int64(object.int("byteCount") ?? object.int("byte_hint") ?? 0)
            )
        }
        return fileArtifacts + inlineArtifacts
    }

    static func providerResearchRun(
        providerID: ProviderID,
        modelID: ModelID,
        title: String,
        prompt: String,
        sourcePolicy: JSONValue,
        responseID: String?,
        status: String,
        providerMetadata: [String: String]
    ) -> ProviderResearchRunRecord {
        ProviderResearchRunRecord(
            id: responseID ?? UUID().uuidString,
            providerID: providerID,
            providerKind: .gemini,
            modelID: modelID,
            title: title,
            prompt: prompt,
            depth: "standard",
            sourcePolicy: sourcePolicy,
            reportFormat: "citation_first",
      includeCodeInterpreter: providerMetadata[CloudProviderMetadataKeys.geminiCodeExecutionJSON]
        != nil,
            serviceTier: "default",
            responseID: responseID,
            status: status,
            citationCount: webCitationCount(providerMetadata),
            toolCallCount: geminiToolCallCount(providerMetadata),
            providerMetadata: providerMetadata
        )
    }

    private static func normalizedStatus(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "unknown" }
    return
      value
            .replacingOccurrences(of: "JOB_STATE_", with: "")
            .lowercased()
    }

    private static func normalizedModelID(_ value: String?) -> ModelID? {
        guard let value else { return nil }
        return ModelID(rawValue: value.replacingOccurrences(of: "models/", with: ""))
    }

    private static func metadata(from value: JSONValue?) -> [String: String] {
        guard let object = value?.objectValue else { return [:] }
        return object.reduce(into: [String: String]()) { result, pair in
            if let string = pair.value.stringValue {
                result[pair.key] = string
            } else if let int = pair.value.intValue {
                result[pair.key] = String(int)
            } else if let bool = pair.value.boolValue {
                result[pair.key] = String(bool)
            }
        }
    }

    private static func jsonValue(fromJSONString raw: String?) -> JSONValue? {
        guard let raw else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    }

    private static func jsonArray(fromJSONString raw: String?) -> [[String: JSONValue]] {
    guard case .array(let values) = jsonValue(fromJSONString: raw) else { return [] }
        return values.compactMap(\.objectValue)
    }

    private static func webCitationCount(_ metadata: [String: String]) -> Int {
        jsonArray(fromJSONString: metadata[CloudProviderMetadataKeys.webSearchCitationsJSON]).count
    }

    private static func geminiToolCallCount(_ metadata: [String: String]) -> Int {
        jsonArray(fromJSONString: metadata[CloudProviderMetadataKeys.geminiCodeExecutionJSON]).count
    }
}

private var qwenTurboQuantProfileCases: [QwenTurboQuantProfileCase] {
        [
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
                displayName: "Qwen3.5 0.8B MLX 4-bit",
                modelType: "qwen3_5",
                parameterCount: 800_000_000,
                modelBytes: 700_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-2B-MLX-4bit",
                displayName: "Qwen3.5 2B MLX 4-bit",
                modelType: "qwen3_5",
                parameterCount: 2_000_000_000,
                modelBytes: 1_550_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-2B-OptiQ-4bit",
                displayName: "Qwen3.5 2B OptiQ 4-bit",
                modelType: "qwen3_5",
                parameterCount: 2_000_000_000,
                modelBytes: 1_550_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-4B-MLX-4bit",
                displayName: "Qwen3.5 4B MLX 4-bit",
                modelType: "qwen3_5_text",
                parameterCount: 4_000_000_000,
                modelBytes: 3_290_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-9B-MLX-4bit",
                displayName: "Qwen3.5 9B MLX 4-bit",
                modelType: "qwen3_5",
                parameterCount: 9_000_000_000,
                modelBytes: 5_600_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-27B-4bit",
                displayName: "Qwen3.5 27B 4-bit",
                modelType: "qwen3_5",
                parameterCount: 27_000_000_000,
                modelBytes: 16_200_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.6-27B-4bit",
                displayName: "Qwen3.6 27B 4-bit",
                modelType: "qwen3_5",
                parameterCount: 27_000_000_000,
                modelBytes: 16_200_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-40B-4bit",
                displayName: "Qwen3.5 40B 4-bit",
                modelType: "qwen3_5",
                parameterCount: 40_000_000_000,
                modelBytes: 24_000_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.6-40B-4bit",
                displayName: "Qwen3.6 40B 4-bit",
                modelType: "qwen3_5",
                parameterCount: 40_000_000_000,
                modelBytes: 24_000_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-35B-A3B-4bit",
                displayName: "Qwen3.5 35B-A3B 4-bit",
                modelType: "qwen3_5_moe",
                parameterCount: 35_000_000_000,
                modelBytes: 21_000_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.6-35B-A3B-4bit",
                displayName: "Qwen3.6 35B-A3B 4-bit",
                modelType: "qwen3_5_moe_text",
                parameterCount: 35_000_000_000,
                modelBytes: 21_000_000_000,
                processorClass: "Qwen2VLProcessor"
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-REAP-97B-A10B-4bit",
                displayName: "Qwen3.5 REAP 97B-A10B 4-bit",
                modelType: "qwen3_5_moe",
                parameterCount: 97_000_000_000,
                modelBytes: 58_200_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-122B-A10B-4bit",
                displayName: "Qwen3.5 122B-A10B 4-bit",
                modelType: "qwen3_5_moe",
                parameterCount: 122_000_000_000,
                modelBytes: 73_200_000_000
            ),
            QwenTurboQuantProfileCase(
                repository: "mlx-community/Qwen3.5-397B-A17B-4bit",
                displayName: "Qwen3.5 397B-A17B 4-bit",
                modelType: "qwen3_5_moe",
                parameterCount: 397_000_000_000,
                modelBytes: 238_200_000_000
            ),
        ]
    }

private struct QwenTurboQuantProfileCase {
        static let configBytes: Int64 = 10_000
        static let tokenizerBytes: Int64 = 8_000_000
        static let processorBytes: Int64 = 12_000

        var repository: String
        var displayName: String
        var modelType: String
        var parameterCount: Int64
        var headDimension: Int = 256
        var modelBytes: Int64
        var processorClass: String?

        var modalities: Set<ModelModality> {
            processorClass == nil ? [.text] : [.text, .vision]
        }

        var expectedDownloadBytes: Int64 {
    modelBytes + Self.configBytes + Self.tokenizerBytes
      + (processorClass == nil ? 0 : Self.processorBytes)
        }

        var configJSON: Data {
    Data(
      #"{"model_type":"\#(modelType)","head_dim":\#(headDimension),"full_attention_interval":4,"linear_num_value_heads":8,"linear_conv_kernel_dim":4}"#
        .utf8)
        }

        var tokenizerConfigJSON: Data {
    Data(
      #"{"chat_template":"<|im_start|>user\n{{ content }}<|im_end|>\n<|im_start|>assistant\n","additional_special_tokens":["<|im_start|>","<|im_end|>"]}"#
        .utf8)
        }

        var processorConfigJSON: Data? {
            processorClass.map { Data(#"{"processor_class":"\#($0)"}"#.utf8) }
        }

        var preflightInput: ModelPreflightInput {
            var files = [
                ModelFileInfo(path: "config.json", size: Self.configBytes),
                ModelFileInfo(path: "tokenizer.json", size: Self.tokenizerBytes),
                ModelFileInfo(path: "model.safetensors", size: modelBytes),
            ]
            if processorClass != nil {
                files.append(ModelFileInfo(path: "processor_config.json", size: Self.processorBytes))
            }
            return ModelPreflightInput(
                repository: repository,
                configJSON: configJSON,
                processorConfigJSON: processorConfigJSON,
                files: files,
                tags: ["mlx", modelType, "4bit"]
            )
        }
    }

private var gemmaTurboQuantProfileCases: [GemmaTurboQuantProfileCase] {
        [
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-1.1-2b-it-4bit",
                displayName: "Gemma 1.1 2B IT 4-bit",
                modelType: "gemma",
                parameterCount: 2_000_000_000,
                headDimension: 256,
                modelBytes: 1_700_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-1.1-7b-it-4bit",
                displayName: "Gemma 1.1 7B IT 4-bit",
                modelType: "gemma",
                parameterCount: 7_000_000_000,
                headDimension: 256,
                modelBytes: 4_500_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-2-9b-it-4bit",
                displayName: "Gemma 2 9B IT 4-bit",
                modelType: "gemma2",
                parameterCount: 9_000_000_000,
                headDimension: 256,
                modelBytes: 5_900_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-2-27b-it-4bit",
                displayName: "Gemma 2 27B IT 4-bit",
                modelType: "gemma2",
                parameterCount: 27_000_000_000,
                headDimension: 128,
                modelBytes: 16_200_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3-270m-it-qat-4bit",
                displayName: "Gemma 3 270M IT QAT 4-bit",
                modelType: "gemma3_text",
                parameterCount: 270_000_000,
                headDimension: 256,
                modelBytes: 340_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3-1b-it-qat-4bit",
                displayName: "Gemma 3 1B IT QAT 4-bit",
                modelType: "gemma3_text",
                parameterCount: 1_000_000_000,
                headDimension: 256,
                modelBytes: 770_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3-1b-it-4bit",
                displayName: "Gemma 3 1B IT 4-bit",
                modelType: "gemma3_text",
                parameterCount: 1_000_000_000,
                headDimension: 256,
                modelBytes: 770_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3-4b-it-qat-4bit",
                displayName: "Gemma 3 4B IT QAT 4-bit",
                modelType: "gemma3",
                parameterCount: 4_000_000_000,
                headDimension: 256,
                modelBytes: 2_900_000_000,
                modalities: [.text, .vision],
                processorClass: "Gemma3Processor"
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3-4b-it-4bit",
                displayName: "Gemma 3 4B IT 4-bit",
                modelType: "gemma3",
                parameterCount: 4_000_000_000,
                headDimension: 256,
                modelBytes: 2_900_000_000,
      configJSONOverride: Data(
        #"{"model_type":"gemma3","text_config":{"model_type":"gemma3_text","hidden_size":2560,"num_attention_heads":8,"num_key_value_heads":4}}"#
          .utf8),
                modalities: [.text, .vision],
                processorClass: "Gemma3Processor"
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3-12b-it-qat-4bit",
                displayName: "Gemma 3 12B IT QAT 4-bit",
                modelType: "gemma3",
                parameterCount: 12_000_000_000,
                headDimension: 256,
                modelBytes: 7_800_000_000,
                modalities: [.text, .vision],
                processorClass: "Gemma3Processor"
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3-12b-it-4bit",
                displayName: "Gemma 3 12B IT 4-bit",
                modelType: "gemma3",
                parameterCount: 12_000_000_000,
                headDimension: 256,
                modelBytes: 7_800_000_000,
      configJSONOverride: Data(
        #"{"model_type":"gemma3","text_config":{"model_type":"gemma3_text","hidden_size":3840,"num_attention_heads":16,"num_key_value_heads":8}}"#
          .utf8),
                modalities: [.text, .vision],
                processorClass: "Gemma3Processor"
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3-27b-it-qat-4bit",
                displayName: "Gemma 3 27B IT QAT 4-bit",
                modelType: "gemma3",
                parameterCount: 27_000_000_000,
                headDimension: 128,
                modelBytes: 16_300_000_000,
                modalities: [.text, .vision],
                processorClass: "Gemma3Processor"
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3n-E2B-it-lm-4bit",
                displayName: "Gemma 3n E2B IT LM 4-bit",
                modelType: "gemma3n",
                parameterCount: 2_000_000_000,
                headDimension: 256,
                modelBytes: 2_550_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-3n-E4B-it-lm-4bit",
                displayName: "Gemma 3n E4B IT LM 4-bit",
                modelType: "gemma3n",
                parameterCount: 4_000_000_000,
                headDimension: 256,
                modelBytes: 4_400_000_000
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-4-e2b-it-OptiQ-4bit",
                displayName: "Gemma 4 E2B IT OptiQ 4-bit",
                modelType: "gemma4",
                parameterCount: 2_000_000_000,
                headDimension: 256,
                modelBytes: 4_330_000_000,
                modalities: [.text, .vision],
                processorClass: "Gemma4Processor"
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-4-e4b-it-OptiQ-4bit",
                displayName: "Gemma 4 E4B IT OptiQ 4-bit",
                modelType: "gemma4",
                parameterCount: 4_000_000_000,
                headDimension: 256,
                modelBytes: 6_570_000_000,
                modalities: [.text, .vision],
                processorClass: "Gemma4Processor"
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-4-26b-it-OptiQ-4bit",
                displayName: "Gemma 4 26B IT OptiQ 4-bit",
                modelType: "gemma4",
                parameterCount: 26_000_000_000,
                headDimension: 256,
                modelBytes: 15_800_000_000,
                modalities: [.text, .vision],
                processorClass: "Gemma4Processor"
            ),
            GemmaTurboQuantProfileCase(
                repository: "mlx-community/gemma-4-31b-it-OptiQ-4bit",
                displayName: "Gemma 4 31B IT OptiQ 4-bit",
                modelType: "gemma4",
                parameterCount: 31_000_000_000,
                headDimension: 256,
                modelBytes: 18_600_000_000,
                modalities: [.text, .vision],
                processorClass: "Gemma4Processor"
            ),
        ]
    }

private struct GemmaTurboQuantProfileCase {
        static let configBytes: Int64 = 10_000
        static let tokenizerBytes: Int64 = 8_000_000
        static let processorBytes: Int64 = 12_000

        var repository: String
        var displayName: String
        var modelType: String
        var parameterCount: Int64
        var headDimension: Int
        var modelBytes: Int64
        var configJSONOverride: Data?
        var modalities: Set<ModelModality> = [.text]
        var processorClass: String?
        var expectedCacheTopology: ModelCacheTopology {
            if modalities.contains(.vision), modelType == "gemma3" || modelType == "gemma4" {
                return .visionLanguageAttention
            }
            if modelType == "gemma3n" || modelType == "gemma4_text" || modelType == "gemma4_assistant" {
                return .sharedKVAttention
            }
            return .standardAttention
        }

        var expectedDownloadBytes: Int64 {
    modelBytes + Self.configBytes + Self.tokenizerBytes
      + (processorClass == nil ? 0 : Self.processorBytes)
        }

        var configJSON: Data {
            if let configJSONOverride {
                return configJSONOverride
            }
            if modelType == "gemma3n" {
      return Data(
        #"{"model_type":"gemma3n","head_dim":\#(headDimension),"layer_types":["sliding_attention","full_attention"],"sliding_window":2048,"num_kv_shared_layers":4}"#
          .utf8)
            }
            return Data(#"{"model_type":"\#(modelType)","head_dim":\#(headDimension)}"#.utf8)
        }

        var tokenizerConfigJSON: Data {
    Data(
      #"{"chat_template":"<start_of_turn>user\n{{ content }}<end_of_turn>\n<start_of_turn>model\n","additional_special_tokens":["<start_of_turn>","<end_of_turn>","<turn|>"]}"#
        .utf8)
        }

        var processorConfigJSON: Data? {
            processorClass.map { Data(#"{"processor_class":"\#($0)"}"#.utf8) }
        }

        var preflightInput: ModelPreflightInput {
            var files = [
                ModelFileInfo(path: "config.json", size: Self.configBytes),
                ModelFileInfo(path: "tokenizer.json", size: Self.tokenizerBytes),
                ModelFileInfo(path: "model.safetensors", size: modelBytes),
            ]
            if processorClass != nil {
                files.append(ModelFileInfo(path: "processor_config.json", size: Self.processorBytes))
            }
            return ModelPreflightInput(
                repository: repository,
                configJSON: configJSON,
                processorConfigJSON: processorConfigJSON,
                files: files,
                tags: ["mlx", modelType, "4bit"]
            )
        }
    }

private func iso8601Date(_ raw: String) -> Date? {
    ISO8601DateFormatter().date(from: raw)
}

extension Dictionary where Key == String, Value == JSONValue {
  fileprivate func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

  fileprivate func int(_ key: String) -> Int? {
        if let int = self[key]?.intValue {
            return int
        }
        if let string = self[key]?.stringValue {
            return Int(string)
        }
        return nil
    }

  fileprivate func arrayStrings(_ key: String) -> [String] {
    guard case .array(let values) = self[key] else { return [] }
        return values.compactMap(\.stringValue)
    }
}

private struct FixtureVaultRepository: VaultRepository {
    let documents: [VaultDocumentRecord]
    let chunksByDocument: [UUID: [VaultChunk]]

    func listDocuments() async throws -> [VaultDocumentRecord] { documents }
    func observeDocuments() -> AsyncStream<[VaultDocumentRecord]> {
        AsyncStream { continuation in
            continuation.yield(documents)
            continuation.finish()
        }
    }

  func upsertDocument(_ document: VaultDocumentRecord, localURL: URL?, checksum: String?)
    async throws
  {}
    func deleteDocument(id: UUID) async throws {}
    func chunks(documentID: UUID) async throws -> [VaultChunk] { chunksByDocument[documentID] ?? [] }
  func replaceChunks(_ chunks: [VaultChunk], documentID: UUID, embeddingModelID: ModelID?)
    async throws
  {}

    func search(query: String, embedding: [Float]?, limit: Int) async throws -> [VaultSearchResult] {
        documents.prefix(max(1, limit)).compactMap { document in
            guard let chunk = chunksByDocument[document.id]?.first else { return nil }
            return VaultSearchResult(document: document, chunk: chunk, score: 1, snippet: chunk.text)
        }
    }
}

private struct EmptyConversationRepository: ConversationRepository {
    func listConversations() async throws -> [ConversationRecord] { [] }
    func listConversationPreviews() async throws -> [ConversationPreviewRecord] { [] }
    func observeConversations() -> AsyncStream<[ConversationRecord]> { AsyncStream { $0.finish() } }
  func observeConversationPreviews() -> AsyncStream<[ConversationPreviewRecord]> {
    AsyncStream { $0.finish() }
  }
  func createConversation(title: String, defaultModelID: ModelID?, defaultProviderID: ProviderID?)
    async throws -> ConversationRecord
  {
    ConversationRecord(
      title: title, defaultModelID: defaultModelID, defaultProviderID: defaultProviderID)
    }
    func updateConversationTitle(_ title: String, conversationID: UUID) async throws {}
  func updateConversationModel(modelID: ModelID?, providerID: ProviderID?, conversationID: UUID)
    async throws
  {}
    func setConversationArchived(_ archived: Bool, conversationID: UUID) async throws {}
    func setConversationPinned(_ pinned: Bool, conversationID: UUID) async throws {}
    func deleteConversation(id: UUID) async throws {}
    func messages(in conversationID: UUID) async throws -> [ChatMessage] { [] }
  func observeMessages(in conversationID: UUID) -> AsyncStream<[ChatMessage]> {
    AsyncStream { $0.finish() }
  }
  func appendMessage(
    _ message: ChatMessage, status: MessageStatus, conversationID: UUID, modelID: ModelID?,
    providerID: ProviderID?
  ) async throws {}
    func deleteMessages(after messageID: UUID, in conversationID: UUID) async throws {}
    func updateMessage(
        id: UUID,
        content: String,
        status: MessageStatus,
        tokenCount: Int?,
        providerMetadata: [String: String]?,
        toolName: String?,
        toolCalls: [ToolCallDelta]?
    ) async throws {}
}
