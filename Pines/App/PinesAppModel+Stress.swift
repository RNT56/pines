import Foundation
import PinesCore

#if DEBUG
extension PinesAppModel {
    func runLaunchStressModeIfNeeded(services: PinesAppServices) async {
        guard let configuration = PinesStressConfiguration.current() else { return }
        if configuration.resetBreadcrumbs {
            await FreezeBreadcrumbJournal.shared.reset()
        }
        await FreezeBreadcrumbJournal.shared.record(
            stage: "stress.launch.detected",
            runID: configuration.runID,
            metadata: [
                "mode": configuration.mode,
                "iterations": String(configuration.iterations),
                "context_sweep_enabled": String(configuration.contextSweepEnabled),
                "context_sweep_start_tokens": String(configuration.contextSweepStartTokens),
                "context_sweep_step_tokens": String(configuration.contextSweepStepTokens),
                "context_sweep_max_tokens": configuration.contextSweepMaxTokens.map(String.init) ?? "runtime",
            ],
            enabled: true
        )
        await runLocalGenerationStress(configuration: configuration, services: services)
    }

    private func runLocalGenerationStress(
        configuration: PinesStressConfiguration,
        services: PinesAppServices
    ) async {
        await writeStressStatus(
            configuration: configuration,
            state: "starting",
            iteration: 0,
            message: "Stress mode is starting."
        )

        guard let repository = services.conversationRepository else {
            await failStressRun(configuration, iteration: 0, message: "Conversation repository is unavailable.")
            return
        }
        let installs: [ModelInstall]
        do {
            try await services.modelLifecycleService?.validateInstalledModels()
            installs = try await services.modelInstallRepository?.listInstalledAndCuratedModels() ?? []
            let downloads = try await services.modelDownloadRepository?.listDownloads() ?? []
            modelDownloads = downloads
            models = Self.modelPreviews(
                installs: installs,
                downloads: downloads,
                runtime: services.mlxRuntime,
                enrichRuntime: false
            )
        } catch {
            await failStressRun(configuration, iteration: 0, message: "Unable to load local model state: \(error.localizedDescription)")
            return
        }
        guard let install = installs
            .first(where: { $0.state == .installed && $0.modalities.contains(.text) })
        else {
            await failStressRun(configuration, iteration: 0, message: "No installed local text model is available.")
            return
        }
        guard let conversationID = await createChat(services: services) else {
            await failStressRun(configuration, iteration: 0, message: serviceError ?? "Unable to create stress chat.")
            return
        }

        let option = ModelPickerOption(
            providerID: services.mlxRuntime.localProviderID,
            providerName: "Local",
            providerKind: nil,
            modelID: install.modelID,
            displayName: Self.localModelDisplayName(install),
            isLocal: true,
            rank: 0
        )
        await selectModel(option, for: conversationID, services: services)
        let stressRuntimeProfile = localRuntimeProfile(for: install, settings: nil, services: services)
        let stressRuntimeMaxContextTokens = stressRuntimeProfile.quantization.maxKVSize
        await FreezeBreadcrumbJournal.shared.record(
            stage: "stress.conversation.ready",
            runID: configuration.runID,
            metadata: [
                "thread_id": conversationID.uuidString,
                "model_id": install.modelID.rawValue,
                "runtime_max_context_tokens": stressRuntimeMaxContextTokens.map(String.init) ?? "unknown",
                "runtime_prefill_step_size": String(stressRuntimeProfile.prefillStepSize),
                "runtime_pressure_reason": stressRuntimeProfile.quantization.runtimePressureReason.rawValue,
                "turboquant_profile_id": stressRuntimeProfile.quantization.turboQuantProfileID ?? "none",
                "turboquant_profile_source": stressRuntimeProfile.quantization.turboQuantProfileSource ?? "none",
            ],
            enabled: true
        )

        for iteration in 1...configuration.iterations {
            let targetContextTokens = configuration.targetContextTokens(
                iteration: iteration,
                runtimeMaxContextTokens: stressRuntimeMaxContextTokens
            )
            let prompt = Self.stressPrompt(
                basePrompt: configuration.prompt,
                iteration: iteration,
                iterations: configuration.iterations,
                targetContextTokens: targetContextTokens
            )
            await writeStressStatus(
                configuration: configuration,
                state: "running",
                iteration: iteration,
                threadID: conversationID,
                modelID: install.modelID,
                message: "Starting local generation iteration \(iteration)."
            )
            await FreezeBreadcrumbJournal.shared.record(
                stage: "stress.iteration.start",
                runID: configuration.runID,
                metadata: [
                    "iteration": String(iteration),
                    "thread_id": conversationID.uuidString,
                    "model_id": install.modelID.rawValue,
                    "target_context_tokens": targetContextTokens.map(String.init) ?? "short",
                    "prompt_characters": String(prompt.count),
                ],
                enabled: true
            )

            startSending(
                prompt,
                attachments: [],
                in: conversationID,
                mode: .chat,
                services: services
            )

            let completion = await waitForStressIterationCompletion(
                timeoutSeconds: configuration.perIterationTimeoutSeconds
            )
            if let completion {
                if let pressureReason = Self.recoverableLocalStressPressureReason(from: completion) {
                    await recoverStressRunFromLocalPressure(
                        configuration: configuration,
                        iteration: iteration,
                        threadID: conversationID,
                        modelID: install.modelID,
                        message: completion,
                        pressureReason: pressureReason,
                        services: services
                    )
                    continue
                }
                await FreezeBreadcrumbJournal.shared.record(
                    stage: "stress.iteration.timeout",
                    runID: configuration.runID,
                    detail: completion,
                    metadata: ["iteration": String(iteration)],
                    enabled: true
                )
                stopCurrentRun()
                await failStressRun(configuration, iteration: iteration, threadID: conversationID, modelID: install.modelID, message: completion)
                return
            }

            do {
                let lastAssistant = try await settledLastAssistantMessage(
                    in: conversationID,
                    repository: repository
                )
                let status = lastAssistant?.persistedMessageStatus
                await writeStressStatus(
                    configuration: configuration,
                    state: "running",
                    iteration: iteration,
                    threadID: conversationID,
                    modelID: install.modelID,
                    message: "Completed iteration \(iteration) with status \(status?.rawValue ?? "unknown")."
                )
                await FreezeBreadcrumbJournal.shared.record(
                    stage: "stress.iteration.complete",
                    runID: configuration.runID,
                    metadata: [
                        "iteration": String(iteration),
                        "assistant_message_id": lastAssistant?.id.uuidString ?? "none",
                        "assistant_status": status?.rawValue ?? "unknown",
                    ],
                    enabled: true
                )
                if status != .complete {
                    if status == .cancelled,
                       let pressureReason = lastAssistant?.providerMetadata[LocalProviderMetadataKeys.generationCancellationReason],
                       Self.isRecoverableLocalStressPressureReason(pressureReason) {
                        let thermal = pressureReason == "thermal_pressure"
                        let recoveryMessage = thermal
                            ? "Recovered from thermal-pressure cancellation at iteration \(iteration)."
                            : "Recovered from memory-pressure cancellation at iteration \(iteration)."
                        await writeStressStatus(
                            configuration: configuration,
                            state: "running",
                            iteration: iteration,
                            threadID: conversationID,
                            modelID: install.modelID,
                            message: recoveryMessage
                        )
                        await FreezeBreadcrumbJournal.shared.record(
                            stage: thermal ? "stress.iteration.thermal_pressure_recovered" : "stress.iteration.memory_pressure_recovered",
                            runID: configuration.runID,
                            metadata: [
                                "iteration": String(iteration),
                                "assistant_message_id": lastAssistant?.id.uuidString ?? "none",
                                "pressure_reason": pressureReason,
                            ],
                            enabled: true
                        )
                        await recoverStressRunFromLocalPressure(
                            configuration: configuration,
                            iteration: iteration,
                            threadID: conversationID,
                            modelID: install.modelID,
                            message: "Recovered from \(pressureReason).",
                            pressureReason: pressureReason,
                            services: services
                        )
                        continue
                    }
                    await failStressRun(
                        configuration,
                        iteration: iteration,
                        threadID: conversationID,
                        modelID: install.modelID,
                        message: "Iteration \(iteration) ended with assistant status \(status?.rawValue ?? "unknown")."
                    )
                    return
                }
            } catch {
                await failStressRun(
                    configuration,
                    iteration: iteration,
                    threadID: conversationID,
                    modelID: install.modelID,
                    message: error.localizedDescription
                )
                return
            }
        }

        await writeStressStatus(
            configuration: configuration,
            state: "completed",
            iteration: configuration.iterations,
            threadID: conversationID,
            modelID: install.modelID,
            message: "Completed \(configuration.iterations) local generation stress iterations."
        )
        await FreezeBreadcrumbJournal.shared.record(
            stage: "stress.run.complete",
            runID: configuration.runID,
            metadata: [
                "iterations": String(configuration.iterations),
                "thread_id": conversationID.uuidString,
                "model_id": install.modelID.rawValue,
            ],
            enabled: true
        )
    }

    private func waitForStressIterationCompletion(timeoutSeconds: TimeInterval) async -> String? {
        let startDeadline = Date().addingTimeInterval(min(15, timeoutSeconds))
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var observedActiveRun = false
        while Date() < startDeadline {
            if activeRunID != nil {
                observedActiveRun = true
                break
            }
            if let serviceError {
                return serviceError
            }
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return "Stress iteration was cancelled."
            }
        }

        guard observedActiveRun else {
            if let serviceError {
                return serviceError
            }
            return "Stress iteration did not start a generation run within 15 seconds."
        }

        while Date() < deadline {
            if activeRunID == nil {
                return nil
            }
            if let serviceError {
                return serviceError
            }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return "Stress iteration was cancelled."
            }
        }
        return "Stress iteration exceeded \(Int(timeoutSeconds)) seconds without completing."
    }

    private static func stressPrompt(
        basePrompt: String,
        iteration: Int,
        iterations: Int,
        targetContextTokens: Int?
    ) -> String {
        var prompt = """
        \(basePrompt)

        Stress iteration \(iteration) of \(iterations). Include the iteration number in the response.
        """
        guard let targetContextTokens else { return prompt }
        let approximateExistingTokens = max(1, prompt.count / 3)
        let payloadTokens = max(0, targetContextTokens - approximateExistingTokens)
        guard payloadTokens > 0 else { return prompt }
        let payload = Self.stressPayload(approximateTokens: payloadTokens)
        prompt += """

        Context sweep payload follows. Use it only as inert context and answer the stress instruction above.

        \(payload)
        """
        return prompt
    }

    private static func stressPayload(approximateTokens: Int) -> String {
        let sentence = "pines context sweep marker diagnostic payload keeps deterministic local prompt pressure without semantic branching. "
        let approximateCharacters = max(0, approximateTokens * 3)
        guard approximateCharacters > 0 else { return "" }
        let repetitions = max(1, (approximateCharacters + sentence.count - 1) / sentence.count)
        return String(String(repeating: sentence, count: repetitions).prefix(approximateCharacters))
    }

    private func settledLastAssistantMessage(
        in conversationID: UUID,
        repository: any ConversationRepository,
        timeoutSeconds: TimeInterval = 8
    ) async throws -> ChatMessage? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastAssistant: ChatMessage?
        repeat {
            let messages = try await repository.messages(in: conversationID)
            lastAssistant = messages.last { $0.role == .assistant }
            if lastAssistant?.persistedMessageStatus != .streaming {
                return lastAssistant
            }
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return lastAssistant
            }
        } while Date() < deadline
        return lastAssistant
    }

    private static func isRecoverableLocalStressPressureMessage(_ message: String) -> Bool {
        recoverableLocalStressPressureReason(from: message) != nil
    }

    private static func recoverableLocalStressPressureReason(from message: String) -> String? {
        let lowercased = message.lowercased()
        if lowercased.contains("memory")
            && (
                lowercased.contains("critically low")
                    || lowercased.contains("ios reported memory pressure")
                    || lowercased.contains("recovering memory")
            ) {
            return "memory_pressure"
        }
        if lowercased.contains("thermal")
            || lowercased.contains("too hot")
            || lowercased.contains("device cool down")
            || lowercased.contains("device to cool down")
            || lowercased.contains("let the device cool down") {
            return "thermal_pressure"
        }
        return nil
    }

    private static func isRecoverableLocalStressPressureReason(_ reason: String) -> Bool {
        reason == "memory_pressure" || reason == "thermal_pressure"
    }

    private func recoverStressRunFromLocalPressure(
        configuration: PinesStressConfiguration,
        iteration: Int,
        threadID: UUID,
        modelID: ModelID,
        message: String,
        pressureReason: String,
        services: PinesAppServices
    ) async {
        let thermal = pressureReason == "thermal_pressure"
        await services.mlxRuntime.unload()
        await writeStressStatus(
            configuration: configuration,
            state: "running",
            iteration: iteration,
            threadID: threadID,
            modelID: modelID,
            message: "Cooling down after local \(thermal ? "thermal" : "memory") pressure at iteration \(iteration)."
        )
        await FreezeBreadcrumbJournal.shared.record(
            stage: thermal ? "stress.iteration.thermal_pressure_cooldown" : "stress.iteration.memory_pressure_cooldown",
            runID: configuration.runID,
            detail: message,
            metadata: [
                "iteration": String(iteration),
                "cooldown_seconds": String(configuration.recoveryCooldownSeconds),
                "pressure_reason": pressureReason,
            ],
            enabled: true
        )
        await sleepForStressRecoveryCooldown(configuration)
    }

    private func sleepForStressRecoveryCooldown(_ configuration: PinesStressConfiguration) async {
        guard configuration.recoveryCooldownSeconds > 0 else { return }
        let nanoseconds = UInt64(configuration.recoveryCooldownSeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func failStressRun(
        _ configuration: PinesStressConfiguration,
        iteration: Int,
        threadID: UUID? = nil,
        modelID: ModelID? = nil,
        message: String
    ) async {
        let normalizedMessage = Self.normalizedChatErrorMessage(message)
        await writeStressStatus(
            configuration: configuration,
            state: "failed",
            iteration: iteration,
            threadID: threadID,
            modelID: modelID,
            message: normalizedMessage
        )
        await FreezeBreadcrumbJournal.shared.record(
            stage: "stress.run.failed",
            runID: configuration.runID,
            detail: normalizedMessage,
            metadata: [
                "iteration": String(iteration),
                "thread_id": threadID?.uuidString ?? "none",
                "model_id": modelID?.rawValue ?? "none",
            ],
            enabled: true
        )
    }

    private func writeStressStatus(
        configuration: PinesStressConfiguration,
        state: String,
        iteration: Int,
        threadID: UUID? = nil,
        modelID: ModelID? = nil,
        message: String?
    ) async {
        await PinesStressStatusWriter.shared.write(
            PinesStressStatus(
                runID: configuration.runID,
                mode: configuration.mode,
                state: state,
                iteration: iteration,
                iterations: configuration.iterations,
                threadID: threadID?.uuidString,
                modelID: modelID?.rawValue,
                message: message,
                updatedAt: Date()
            )
        )
    }
}
#endif
