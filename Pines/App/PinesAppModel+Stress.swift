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
                "context_mode": configuration.contextMode.rawValue,
                "context_sweep_start_tokens": String(configuration.contextSweepStartTokens),
                "context_sweep_step_tokens": String(configuration.contextSweepStepTokens),
                "context_sweep_max_tokens": configuration.contextSweepMaxTokens.map(String.init) ?? "runtime",
                "context_target_tokens": configuration.contextTargetTokens.map(String.init) ?? "auto",
                "context_high_ratio": String(configuration.contextHighWatermarkRatio),
                "context_reserve_tokens": String(configuration.contextReserveTokens),
                "requested_model_id": configuration.requestedModelID ?? "first-installed",
                "allow_pressure_recovery": String(configuration.allowPressureRecovery),
                "disable_turboquant": String(configuration.disableTurboQuant),
            ],
            enabled: true
        )
        await runLocalGenerationStress(configuration: configuration, services: services)
    }

    private func runLocalGenerationStress(
        configuration: PinesStressConfiguration,
        services: PinesAppServices
    ) async {
        stressDisablesTurboQuant = configuration.disableTurboQuant
        defer { stressDisablesTurboQuant = false }

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
        let installedTextCandidates = installs.filter { $0.state == .installed && $0.modalities.contains(.text) }
        await FreezeBreadcrumbJournal.shared.record(
            stage: "stress.installed_models",
            runID: configuration.runID,
            metadata: [
                "installed_text_model_count": String(installedTextCandidates.count),
                "installed_text_model_ids": installedTextCandidates.map(\.modelID.rawValue).joined(separator: " | "),
                "installed_text_repositories": installedTextCandidates.map(\.repository).joined(separator: " | "),
                "requested_model_id": configuration.requestedModelID ?? "first-installed",
            ],
            enabled: true
        )
        guard let install = Self.selectedStressInstall(from: installs, configuration: configuration) else {
            let message = configuration.requestedModelID.map {
                "Requested stress model \($0) is not an installed local text model."
            } ?? "No installed local text model is available."
            await failStressRun(configuration, iteration: 0, message: message)
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
        if configuration.requiresRuntimeContextWindow(), stressRuntimeMaxContextTokens == nil {
            await failStressRun(
                configuration,
                iteration: 0,
                threadID: conversationID,
                modelID: install.modelID,
                message: "Context \(configuration.contextMode.rawValue) stress requires a known runtime context window."
            )
            return
        }
        await FreezeBreadcrumbJournal.shared.record(
            stage: "stress.conversation.ready",
            runID: configuration.runID,
            metadata: [
                "thread_id": conversationID.uuidString,
                "model_id": install.modelID.rawValue,
                "context_mode": configuration.contextMode.rawValue,
                "context_plan_preview": configuration.contextPlanPreview(
                    iterations: configuration.iterations,
                    runtimeMaxContextTokens: stressRuntimeMaxContextTokens
                ),
                "runtime_max_context_tokens": stressRuntimeMaxContextTokens.map(String.init) ?? "unknown",
                "runtime_prefill_step_size": String(stressRuntimeProfile.prefillStepSize),
                "runtime_pressure_reason": stressRuntimeProfile.quantization.runtimePressureReason.rawValue,
                "turboquant_profile_id": stressRuntimeProfile.quantization.turboQuantProfileID ?? "none",
                "turboquant_profile_source": stressRuntimeProfile.quantization.turboQuantProfileSource ?? "none",
                "model_type": install.modelType ?? "unknown",
                "text_config_model_type": install.textConfigModelType ?? "none",
                "processor_class": install.processorClass ?? "none",
                "parameter_count": install.parameterCount.map(String.init) ?? "unknown",
                "modalities": install.modalities.map(\.rawValue).sorted().joined(separator: ","),
                "effective_turboquant_modalities": install.effectiveTurboQuantModalities.map(\.rawValue).sorted().joined(separator: ","),
                "key_head_dimension": install.keyHeadDimension.map(String.init) ?? "unknown",
                "value_head_dimension": install.valueHeadDimension.map(String.init) ?? "unknown",
                "routed_experts": install.routedExperts.map(String.init) ?? "none",
                "experts_per_token": install.expertsPerToken.map(String.init) ?? "none",
                "cache_topology": install.cacheTopology.rawValue,
                "turboquant_family_support": install.effectiveTurboQuantFamilySupport.rawValue,
                "stored_turboquant_family_support": install.turboQuantFamilySupport.rawValue,
                "effective_turboquant_family_support": install.effectiveTurboQuantFamilySupport.rawValue,
                "runtime_kv_cache_strategy": stressRuntimeProfile.quantization.kvCacheStrategy.rawValue,
                "runtime_turboquant_diagnostics": stressRuntimeProfile.quantization.turboQuantProfileDiagnostics.joined(separator: " | "),
                "disable_turboquant": String(configuration.disableTurboQuant),
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
                runtimeMaxContextTokens: stressRuntimeMaxContextTokens,
                targetContextTokens: targetContextTokens,
                message: "Starting local generation iteration \(iteration)."
            )
            await FreezeBreadcrumbJournal.shared.record(
                stage: "stress.iteration.start",
                runID: configuration.runID,
                metadata: [
                    "iteration": String(iteration),
                    "thread_id": conversationID.uuidString,
                    "model_id": install.modelID.rawValue,
                    "context_mode": configuration.contextMode.rawValue,
                    "runtime_max_context_tokens": stressRuntimeMaxContextTokens.map(String.init) ?? "unknown",
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
                    guard configuration.allowPressureRecovery else {
                        await failStressRun(
                            configuration,
                            iteration: iteration,
                            threadID: conversationID,
                            modelID: install.modelID,
                            message: "Iteration \(iteration) hit \(pressureReason) before producing an accepted local response."
                        )
                        return
                    }
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
                    runtimeMaxContextTokens: stressRuntimeMaxContextTokens,
                    targetContextTokens: targetContextTokens,
                    message: "Completed iteration \(iteration) with status \(status?.rawValue ?? "unknown")."
                )
                var completionMetadata = Self.localStressOutputDiagnostics(lastAssistant?.content ?? "")
                completionMetadata.merge(Self.localStressProviderDiagnostics(lastAssistant)) { _, new in new }
                completionMetadata.merge([
                    "iteration": String(iteration),
                    "context_mode": configuration.contextMode.rawValue,
                    "target_context_tokens": targetContextTokens.map(String.init) ?? "short",
                    "assistant_message_id": lastAssistant?.id.uuidString ?? "none",
                    "assistant_status": status?.rawValue ?? "unknown",
                ]) { _, new in new }
                await FreezeBreadcrumbJournal.shared.record(
                    stage: "stress.iteration.complete",
                    runID: configuration.runID,
                    metadata: completionMetadata,
                    enabled: true
                )
                if status != .complete {
                    if let pressureReason = Self.recoverableLocalStressPressureReason(from: lastAssistant) {
                        guard configuration.allowPressureRecovery else {
                            await failStressRun(
                                configuration,
                                iteration: iteration,
                                threadID: conversationID,
                                modelID: install.modelID,
                                message: "Iteration \(iteration) hit \(pressureReason) before producing an accepted local response."
                            )
                            return
                        }
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
                            runtimeMaxContextTokens: stressRuntimeMaxContextTokens,
                            targetContextTokens: targetContextTokens,
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
                if let lastAssistant,
                   let outputFailure = Self.localStressOutputQualityFailure(lastAssistant.content) {
                    await FreezeBreadcrumbJournal.shared.record(
                        stage: "stress.iteration.output_rejected",
                        runID: configuration.runID,
                        detail: outputFailure,
                        metadata: Self.localStressOutputDiagnostics(lastAssistant.content),
                        enabled: true
                    )
                    await failStressRun(
                        configuration,
                        iteration: iteration,
                        threadID: conversationID,
                        modelID: install.modelID,
                        message: outputFailure
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

        let finalTargetContextTokens = configuration.targetContextTokens(
            iteration: configuration.iterations,
            runtimeMaxContextTokens: stressRuntimeMaxContextTokens
        )
        await writeStressStatus(
            configuration: configuration,
            state: "completed",
            iteration: configuration.iterations,
            threadID: conversationID,
            modelID: install.modelID,
            runtimeMaxContextTokens: stressRuntimeMaxContextTokens,
            targetContextTokens: finalTargetContextTokens,
            message: "Completed \(configuration.iterations) local generation stress iterations."
        )
        await FreezeBreadcrumbJournal.shared.record(
            stage: "stress.run.complete",
            runID: configuration.runID,
            metadata: [
                "iterations": String(configuration.iterations),
                "thread_id": conversationID.uuidString,
                "model_id": install.modelID.rawValue,
                "context_mode": configuration.contextMode.rawValue,
                "runtime_max_context_tokens": stressRuntimeMaxContextTokens.map(String.init) ?? "unknown",
            ],
            enabled: true
        )
    }

    private static func selectedStressInstall(
        from installs: [ModelInstall],
        configuration: PinesStressConfiguration
    ) -> ModelInstall? {
        let candidates = installs.filter { $0.state == .installed && $0.modalities.contains(.text) }
        guard let requestedModelID = configuration.requestedModelID?.lowercased() else {
            return candidates.first
        }
        return candidates.first { install in
            install.modelID.rawValue.lowercased() == requestedModelID
                || install.repository.lowercased() == requestedModelID
                || install.displayName.lowercased() == requestedModelID
        }
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

    private static func localStressOutputQualityFailure(_ content: String) -> String? {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count < 16 {
            return "Local generation produced too little output for the diagnostic prompt."
        }

        let scalars = Array(text.unicodeScalars)
        let replacementCount = scalars.filter { $0.value == 0xfffd }.count
        if replacementCount > 0 {
            return "Local generation produced Unicode replacement characters, which indicates tokenizer/model output corruption."
        }

        let controlCount = scalars.filter { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && scalar != "\n"
                && scalar != "\r"
                && scalar != "\t"
        }.count
        if controlCount > 0 {
            return "Local generation produced control characters, which indicates invalid decoded output."
        }

        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        if letterCount < max(8, scalars.count / 5) {
            return "Local generation output failed the diagnostic text sanity check."
        }

        let words = text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
        if let mostRepeated = Dictionary(grouping: words, by: { $0 }).values.map(\.count).max(),
           words.count >= 12,
           mostRepeated > max(8, words.count / 2) {
            return "Local generation repeated the same token pattern excessively."
        }

        return nil
    }

    private static func localStressOutputDiagnostics(_ content: String) -> [String: String] {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = Array(text.unicodeScalars)
        let replacementCount = scalars.filter { $0.value == 0xfffd }.count
        let controlCount = scalars.filter { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && scalar != "\n"
                && scalar != "\r"
                && scalar != "\t"
        }.count
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        let words = text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
        let wordGroups = Dictionary(grouping: words, by: { $0 })
        let mostRepeatedEntry = wordGroups.max { left, right in left.value.count < right.value.count }
        let mostRepeated = mostRepeatedEntry?.value.count ?? 0
        let mostRepeatedWord = mostRepeatedEntry?.key ?? ""
        let uniqueWordCount = wordGroups.count
        let maxRepeatedBigram = maxRepeatedNgramCount(words: words, size: 2)
        let maxRepeatedTrigram = maxRepeatedNgramCount(words: words, size: 3)
        let sample = text
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .prefix(240)
        let suffixSample = text
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .suffix(240)
        return [
            "assistant_content_characters": String(text.count),
            "assistant_unicode_scalar_count": String(scalars.count),
            "assistant_letter_count": String(letterCount),
            "assistant_control_character_count": String(controlCount),
            "assistant_replacement_character_count": String(replacementCount),
            "assistant_word_count": String(words.count),
            "assistant_unique_word_count": String(uniqueWordCount),
            "assistant_most_repeated_word_count": String(mostRepeated),
            "assistant_most_repeated_word": mostRepeatedWord,
            "assistant_max_repeated_bigram_count": String(maxRepeatedBigram),
            "assistant_max_repeated_trigram_count": String(maxRepeatedTrigram),
            "assistant_content_sample": String(sample),
            "assistant_content_suffix_sample": String(suffixSample),
        ]
    }

    private static func localStressProviderDiagnostics(_ message: ChatMessage?) -> [String: String] {
        guard let metadata = message?.providerMetadata else { return [:] }
        let keys: Set<String> = [
            LocalProviderMetadataKeys.turboQuantPreset,
            LocalProviderMetadataKeys.turboQuantRequestedBackend,
            LocalProviderMetadataKeys.turboQuantActiveBackend,
            LocalProviderMetadataKeys.turboQuantValueBits,
            LocalProviderMetadataKeys.turboQuantAttentionPath,
            LocalProviderMetadataKeys.turboQuantKernelProfile,
            LocalProviderMetadataKeys.turboQuantSelfTestStatus,
            LocalProviderMetadataKeys.turboQuantFallbackReason,
            LocalProviderMetadataKeys.turboQuantLastUnsupportedShape,
            LocalProviderMetadataKeys.turboQuantRawFallbackAllocated,
            LocalProviderMetadataKeys.turboQuantProfileID,
            LocalProviderMetadataKeys.turboQuantAdmissionDecision,
            LocalProviderMetadataKeys.turboQuantSelectedMode,
            LocalProviderMetadataKeys.cacheTopology,
            LocalProviderMetadataKeys.turboQuantFamilySupport,
            LocalProviderMetadataKeys.attentionCacheCount,
            LocalProviderMetadataKeys.nativeStateCacheCount,
            LocalProviderMetadataKeys.runtimePressureReason,
            LocalProviderMetadataKeys.runtimeLowPowerMode,
            LocalProviderMetadataKeys.runtimeMaxKVSize,
            LocalProviderMetadataKeys.runtimePrefillStepSize,
            LocalProviderMetadataKeys.generationCompletionTokens,
            LocalProviderMetadataKeys.generationElapsedSeconds,
            LocalProviderMetadataKeys.generationTokensPerSecond,
            LocalProviderMetadataKeys.generationFirstTokenLatencySeconds,
            LocalProviderMetadataKeys.generationPrepareElapsedSeconds,
            LocalProviderMetadataKeys.generationCacheCreateElapsedSeconds,
            LocalProviderMetadataKeys.generationEffectiveMaxTokens,
            LocalProviderMetadataKeys.generationIncompleteReason,
        ]
        return metadata.reduce(into: [String: String]()) { result, entry in
            guard keys.contains(entry.key) else { return }
            result["provider.\(entry.key)"] = String(entry.value.prefix(500))
        }
    }

    private static func maxRepeatedNgramCount(words: [String], size: Int) -> Int {
        guard size > 0, words.count >= size else { return 0 }
        var counts: [String: Int] = [:]
        for index in 0...(words.count - size) {
            let key = words[index..<(index + size)].joined(separator: " ")
            counts[key, default: 0] += 1
        }
        return counts.values.max() ?? 0
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

    private static func recoverableLocalStressPressureReason(from message: ChatMessage?) -> String? {
        guard let message else { return nil }
        if let pressureReason = message.providerMetadata[LocalProviderMetadataKeys.generationCancellationReason],
           isRecoverableLocalStressPressureReason(pressureReason) {
            return pressureReason
        }
        if let pressureReason = recoverableLocalStressPressureReason(from: message.content) {
            return pressureReason
        }
        for value in message.providerMetadata.values {
            if let pressureReason = recoverableLocalStressPressureReason(from: value) {
                return pressureReason
            }
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
        runtimeMaxContextTokens: Int? = nil,
        targetContextTokens: Int? = nil,
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
                contextMode: configuration.contextMode,
                runtimeMaxContextTokens: runtimeMaxContextTokens,
                targetContextTokens: targetContextTokens,
                message: message,
                updatedAt: Date()
            )
        )
    }
}
#endif
