import Foundation

public enum CloudProviderMetadataKeys {
    public static let openAIResponseID = "openai.response_id"
    public static let openAIChatCompletionID = "openai.chat_completion_id"
    public static let openAIRequestID = "openai.request_id"
    public static let openAIClientRequestID = "openai.client_request_id"
    public static let openAIModel = "openai.model"
    public static let openAISystemFingerprint = "openai.system_fingerprint"
    public static let openAIOutputItemsJSON = "openai.output_items_json"
    public static let openAIResponseStatus = "openai.response.status"
    public static let openAIResponsePreviousID = "openai.response.previous_id"
    public static let openAIResponseServiceTier = "openai.response.service_tier"
    public static let openAIResponseStored = "openai.response.stored"
    public static let openAIResponseIncompleteReason = "openai.response.incomplete_reason"
    public static let openAIReasoningTokens = "openai.usage.reasoning_tokens"
    public static let openAICachedInputTokens = "openai.usage.cached_input_tokens"
    public static let openAIPromptCacheKey = "openai.prompt_cache_key"
    public static let openAIHostedToolCallsJSON = "openai.hosted_tool_calls_json"
    public static let openAIFileSearchResultsJSON = "openai.file_search.results_json"
    public static let openAIArtifactsJSON = "openai.artifacts_json"
    public static let openRouterGenerationID = "openrouter.generation_id"
    public static let openRouterProvider = "openrouter.provider"
    public static let openRouterRequestedModel = "openrouter.requested_model"
    public static let openRouterResolvedModel = "openrouter.resolved_model"
    public static let openRouterNativeFinishReason = "openrouter.native_finish_reason"
    public static let openRouterServiceTier = "openrouter.service_tier"
    public static let openRouterStrategy = "openrouter.strategy"
    public static let openRouterRegion = "openrouter.region"
    public static let openRouterSummary = "openrouter.summary"
    public static let openRouterAttempt = "openrouter.attempt"
    public static let openRouterAttemptCount = "openrouter.attempt_count"
    public static let openRouterIsBYOK = "openrouter.is_byok"
    public static let openRouterSelectedProvider = "openrouter.selected_provider"
    public static let openRouterSelectedModel = "openrouter.selected_model"
    public static let openRouterMetadataJSON = "openrouter.metadata_json"
    public static let openRouterAttemptsJSON = "openrouter.attempts_json"
    public static let openRouterUsageJSON = "openrouter.usage_json"
    public static let openRouterPromptTokens = "openrouter.usage.prompt_tokens"
    public static let openRouterCompletionTokens = "openrouter.usage.completion_tokens"
    public static let openRouterTotalTokens = "openrouter.usage.total_tokens"
    public static let openRouterCostCredits = "openrouter.usage.cost_credits"
    public static let openRouterUpstreamInferenceCost = "openrouter.usage.upstream_inference_cost"
    public static let webSearchCitationsJSON = "pines.web_search.citations_json"
    public static let webSearchQueriesJSON = "pines.web_search.queries_json"
    public static let webSearchSuggestionsHTML = "pines.web_search.suggestions_html"
    public static let anthropicMessageID = "anthropic.message_id"
    public static let anthropicRequestID = "anthropic.request_id"
    public static let anthropicThinkingContentJSON = "anthropic.thinking_content_json"
    public static let anthropicUsageJSON = "anthropic.usage_json"
    public static let anthropicCacheUsageJSON = "anthropic.cache_usage_json"
    public static let anthropicCacheReadInputTokens = "anthropic.cache_read_input_tokens"
    public static let anthropicCacheCreationInputTokens = "anthropic.cache_creation_input_tokens"
    public static let anthropicCountTokensInputTokens = "anthropic.count_tokens.input_tokens"
    public static let anthropicHostedToolCallsJSON = "anthropic.hosted_tool_calls_json"
    public static let anthropicArtifactsJSON = "anthropic.artifacts_json"
    public static let anthropicFileReferencesJSON = "anthropic.file_references_json"
    public static let anthropicErrorType = "anthropic.error.type"
    public static let anthropicErrorJSON = "anthropic.error_json"
    public static let geminiResponseID = "gemini.response_id"
    public static let geminiModelVersion = "gemini.model_version"
    public static let geminiRequestID = "gemini.request_id"
    public static let geminiModelContentJSON = "gemini.model_content_json"
    public static let geminiInteractionID = "gemini.interaction_id"
    public static let geminiCodeExecutionJSON = "gemini.code_execution_json"
    public static let geminiURLContextJSON = "gemini.url_context_json"
    public static let geminiFileReferencesJSON = "gemini.file_references_json"
    public static let geminiCacheUsageJSON = "gemini.cache_usage_json"
    public static let geminiArtifactsJSON = "gemini.artifacts_json"
}

public enum CloudProviderStreamFormat: Sendable {
    case chatCompletions
    case openAIResponses
    case anthropicMessages
    case geminiGenerateContent
    case geminiInteractions
}

public struct CloudProviderStreamParseOutput: Sendable {
    public var events: [InferenceStreamEvent]
    public var finish: InferenceFinish?

    public init(events: [InferenceStreamEvent] = [], finish: InferenceFinish? = nil) {
        self.events = events
        self.finish = finish
    }
}

public struct CloudProviderStreamParser {
    public private(set) var state = CloudProviderStreamState()

    public init() {}

    public mutating func recordRequestMetadata(providerKind: CloudProviderKind, serverRequestID: String?, clientRequestID: String?) {
        state.recordRequestMetadata(providerKind: providerKind, serverRequestID: serverRequestID, clientRequestID: clientRequestID)
    }

    public mutating func parse(data: Data, format: CloudProviderStreamFormat, providerKind: CloudProviderKind) -> CloudProviderStreamParseOutput {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CloudProviderStreamParseOutput()
        }

        switch format {
        case .openAIResponses:
            return extractOpenAIResponsesEvents(json)
        case .anthropicMessages:
            return extractAnthropicEvents(json)
        case .geminiGenerateContent:
            return extractGeminiGenerateContentEvents(json)
        case .geminiInteractions:
            return extractGeminiInteractionEvents(json)
        case .chatCompletions:
            return extractChatCompletionEvents(json, providerKind: providerKind)
        }
    }

    public func finalizedFinish(
        _ pendingFinish: InferenceFinish?,
        format: CloudProviderStreamFormat,
        providerKind: CloudProviderKind,
        modelID: ModelID,
        usesOfficialOpenAIReasoningChat: Bool
    ) -> InferenceFinish {
        var finish = pendingFinish ?? fallbackFinish(
            format: format,
            providerKind: providerKind,
            modelID: modelID,
            usesOfficialOpenAIReasoningChat: usesOfficialOpenAIReasoningChat
        )
        let latestMetadata: [String: String]
        switch format {
        case .chatCompletions, .openAIResponses:
            latestMetadata = state.openAIProviderMetadata
        case .anthropicMessages:
            latestMetadata = state.anthropicProviderMetadata
        case .geminiGenerateContent:
            latestMetadata = state.geminiProviderMetadata
        case .geminiInteractions:
            latestMetadata = state.geminiInteractionProviderMetadata
        }
        finish.providerMetadata.merge(latestMetadata) { _, latest in latest }
        return finish
    }

    public func fallbackFinish(format: CloudProviderStreamFormat, providerKind: CloudProviderKind, modelID: ModelID, usesOfficialOpenAIReasoningChat: Bool) -> InferenceFinish {
        switch format {
        case .openAIResponses:
            let hasToolCalls = !state.completedOpenAIToolCallIDs.isEmpty
            return InferenceFinish(
                reason: hasToolCalls ? .toolCall : .stop,
                message: hasToolCalls ? nil : Self.openAIResponsesEmptyOutputMessage(response: nil, eventTypes: state.openAIResponsesEventTypes),
                providerMetadata: state.openAIProviderMetadata
            )
        case .chatCompletions:
            guard usesOfficialOpenAIReasoningChat else {
                return InferenceFinish(reason: .stop, providerMetadata: state.openAIProviderMetadata)
            }
            return InferenceFinish(
                reason: .stop,
                message: "Pines received an empty OpenAI Chat Completions stream for \(modelID.rawValue). Official OpenAI reasoning models should use the Responses API; check that the provider base URL is https://api.openai.com/v1.",
                providerMetadata: state.openAIProviderMetadata
            )
        case .anthropicMessages:
            return InferenceFinish(reason: .stop, providerMetadata: state.anthropicProviderMetadata)
        case .geminiGenerateContent:
            return InferenceFinish(reason: state.geminiCompletedToolCallIDs.isEmpty ? .stop : .toolCall, providerMetadata: state.geminiProviderMetadata)
        case .geminiInteractions:
            return InferenceFinish(reason: state.geminiInteractionCompletedToolCallIDs.isEmpty ? .stop : .toolCall, providerMetadata: state.geminiInteractionProviderMetadata)
        }
    }

    private mutating func extractAnthropicEvents(_ json: [String: Any]) -> CloudProviderStreamParseOutput {
        let type = json["type"] as? String
        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?

        if type == "message_start",
           let message = json["message"] as? [String: Any] {
            state.recordAnthropicMessage(message)
            if let usage = message["usage"] as? [String: Any],
               let metrics = Self.anthropicMetrics(from: usage) {
                state.recordAnthropicUsage(usage)
                events.append(.metrics(metrics))
            }
        }

        if type == "content_block_start",
           let index = json["index"] as? Int,
           let block = json["content_block"] as? [String: Any] {
            switch block["type"] as? String {
            case "tool_use":
                state.anthropicToolIndex = index
                state.anthropicToolID = block["id"] as? String
                state.anthropicToolName = block["name"] as? String
                let initialInput = Self.jsonString(from: block["input"]) ?? ""
                state.anthropicArguments = initialInput == "{}" ? "" : initialInput
            case "thinking":
                state.anthropicThinkingIndex = index
                state.anthropicThinkingText = block["thinking"] as? String ?? ""
                state.anthropicThinkingSignature = block["signature"] as? String
            case "text":
                state.recordAnthropicContentBlock(block)
                if let text = block["text"] as? String, !text.isEmpty {
                    events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                }
            case "server_tool_use":
                state.anthropicServerToolIndex = index
                state.anthropicServerToolID = block["id"] as? String
                state.anthropicServerToolName = block["name"] as? String
                let initialInput = Self.jsonString(from: block["input"]) ?? ""
                state.anthropicServerToolArguments = initialInput == "{}" ? "" : initialInput
                state.recordAnthropicHostedToolBlock(block, status: "in_progress")
            case "web_search_tool_result", "web_fetch_tool_result", "code_execution_tool_result", "mcp_tool_result":
                state.recordAnthropicHostedToolBlock(block, status: "completed")
                state.recordAnthropicContentBlock(block)
            default:
                state.recordAnthropicContentBlock(block)
                break
            }
        }

        if let delta = json["delta"] as? [String: Any] {
            if delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String,
               !text.isEmpty {
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
            if delta["type"] as? String == "input_json_delta",
               let partial = delta["partial_json"] as? String {
                if let index = json["index"] as? Int,
                   index == state.anthropicServerToolIndex {
                    state.anthropicServerToolArguments += partial
                } else {
                    state.anthropicArguments += partial
                }
            }
            if delta["type"] as? String == "thinking_delta",
               let thinking = delta["thinking"] as? String {
                state.anthropicThinkingText += thinking
            }
            if delta["type"] as? String == "signature_delta",
               let signature = delta["signature"] as? String {
                state.anthropicThinkingSignature = signature
            }
            if delta["type"] as? String == "citations_delta",
               let citation = delta["citation"] as? [String: Any] {
                state.recordAnthropicCitationObjects([citation])
            }
        }

        if type == "content_block_stop",
           let index = json["index"] as? Int,
           index == state.anthropicToolIndex,
           let id = state.anthropicToolID,
           let name = state.anthropicToolName {
            events.append(.toolCall(ToolCallDelta(
                id: id,
                name: name,
                argumentsFragment: state.anthropicArguments.isEmpty ? "{}" : state.anthropicArguments,
                isComplete: true
            )))
            state.clearAnthropicTool()
        }
        if type == "content_block_stop",
           let index = json["index"] as? Int,
           index == state.anthropicServerToolIndex {
            state.recordAnthropicCompletedServerTool()
            state.clearAnthropicServerTool()
        }
        if type == "content_block_stop",
           let index = json["index"] as? Int,
           index == state.anthropicThinkingIndex {
            state.recordAnthropicThinkingBlock()
        }

        if type == "message_delta" {
            if let usage = json["usage"] as? [String: Any],
               let metrics = Self.anthropicMetrics(from: usage) {
                state.recordAnthropicUsage(usage)
                events.append(.metrics(metrics))
            }
            if let delta = json["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String {
                finish = Self.anthropicFinish(from: stopReason, metadata: state.anthropicProviderMetadata)
            }
        }

        if type == "error" {
            let error = json["error"] as? [String: Any]
            state.recordAnthropicError(error)
            finish = InferenceFinish(
                reason: .error,
                message: error?["message"] as? String ?? "Anthropic returned a streaming error.",
                providerMetadata: state.anthropicProviderMetadata
            )
        }

        return CloudProviderStreamParseOutput(events: events, finish: finish)
    }

    private mutating func extractGeminiGenerateContentEvents(_ json: [String: Any]) -> CloudProviderStreamParseOutput {
        state.recordGeminiResponse(json)
        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?

        if let promptFeedback = json["promptFeedback"] as? [String: Any],
           let feedbackFinish = Self.geminiPromptFeedbackFinish(from: promptFeedback, metadata: state.geminiProviderMetadata) {
            finish = feedbackFinish
        }
        if let usage = json["usageMetadata"] as? [String: Any],
           let metrics = Self.geminiMetrics(from: usage) {
            events.append(.metrics(metrics))
        }

        for candidate in json["candidates"] as? [[String: Any]] ?? [] {
            if let content = candidate["content"] as? [String: Any] {
                state.recordGeminiModelContent(content)
                for part in content["parts"] as? [[String: Any]] ?? [] {
                    state.recordGeminiPartMetadata(part, interactionsAPI: false)
                    if part["thought"] as? Bool == true {
                        continue
                    }
                    if let text = part["text"] as? String, !text.isEmpty {
                        events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                    }
                    if let call = part["functionCall"] as? [String: Any],
                       let name = call["name"] as? String {
                        let toolCall = ToolCallDelta(
                            id: (call["id"] as? String) ?? UUID().uuidString,
                            name: name,
                            argumentsFragment: Self.jsonString(from: call["args"]) ?? "{}",
                            isComplete: true
                        )
                        if state.markGeminiToolCallCompleted(toolCall) {
                            events.append(.toolCall(toolCall))
                        }
                    }
                }
            }
            if let finishReason = candidate["finishReason"] as? String {
                finish = Self.geminiFinish(
                    from: finishReason,
                    hasToolCalls: !state.geminiCompletedToolCallIDs.isEmpty,
                    metadata: state.geminiProviderMetadata
                )
            }
        }

        return CloudProviderStreamParseOutput(events: events, finish: finish)
    }

    private mutating func extractGeminiInteractionEvents(_ json: [String: Any]) -> CloudProviderStreamParseOutput {
        let eventType = json["event_type"] as? String
        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?

        if let interaction = json["interaction"] as? [String: Any] {
            state.recordGeminiInteraction(interaction)
        }
        if let interactionID = json["interaction_id"] as? String, !interactionID.isEmpty {
            state.geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiInteractionID] = interactionID
        }

        switch eventType {
        case "interaction.completed", "interaction.complete":
            if let interaction = json["interaction"] as? [String: Any],
               let usage = interaction["usage"] as? [String: Any],
               let metrics = Self.geminiInteractionMetrics(from: usage) {
                events.append(.metrics(metrics))
            }
            finish = InferenceFinish(
                reason: state.geminiInteractionCompletedToolCallIDs.isEmpty ? .stop : .toolCall,
                providerMetadata: state.geminiInteractionProviderMetadata
            )
        case "interaction.status_update":
            if let status = json["status"] as? String, status == "failed" || status == "cancelled" || status == "incomplete" {
                finish = InferenceFinish(
                    reason: status == "cancelled" ? .cancelled : .error,
                    message: "Gemini interaction ended with status \(status).",
                    providerMetadata: state.geminiInteractionProviderMetadata
                )
            }
        case "error":
            let error = json["error"] as? [String: Any]
            finish = InferenceFinish(
                reason: .error,
                message: error?["message"] as? String ?? "Gemini returned an interaction error.",
                providerMetadata: state.geminiInteractionProviderMetadata
            )
        case "step.start":
            if let index = json["index"] as? Int,
               let step = json["step"] as? [String: Any],
               step["type"] as? String == "function_call" {
                state.geminiInteractionToolIDs[index] = step["id"] as? String
                state.geminiInteractionToolNames[index] = step["name"] as? String
                if let arguments = step["arguments"] {
                    state.geminiInteractionArguments[index] = Self.jsonString(from: arguments) ?? "{}"
                }
            }
        case "step.delta", "content.delta":
            if let delta = json["delta"] as? [String: Any] {
                let index = json["index"] as? Int
                switch delta["type"] as? String {
                case "text":
                    if let text = delta["text"] as? String, !text.isEmpty {
                        events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                    }
                case "arguments_delta":
                    if let index, let arguments = delta["arguments"] as? String {
                        state.geminiInteractionArguments[index, default: ""] += arguments
                    }
                case "function_call":
                    if let index {
                        state.geminiInteractionToolIDs[index] = (delta["id"] as? String) ?? state.geminiInteractionToolIDs[index]
                        state.geminiInteractionToolNames[index] = (delta["name"] as? String) ?? state.geminiInteractionToolNames[index]
                        if let arguments = delta["arguments"] {
                            state.geminiInteractionArguments[index] = Self.jsonString(from: arguments) ?? state.geminiInteractionArguments[index]
                        }
                    }
                default:
                    break
                }
            }
        case "step.stop":
            if let index = json["index"] as? Int,
               let name = state.geminiInteractionToolNames[index] {
                let toolCall = ToolCallDelta(
                    id: state.geminiInteractionToolIDs[index] ?? UUID().uuidString,
                    name: name,
                    argumentsFragment: state.geminiInteractionArguments[index] ?? "{}",
                    isComplete: true
                )
                state.geminiInteractionToolIDs.removeValue(forKey: index)
                state.geminiInteractionToolNames.removeValue(forKey: index)
                state.geminiInteractionArguments.removeValue(forKey: index)
                if state.markGeminiInteractionToolCallCompleted(toolCall) {
                    events.append(.toolCall(toolCall))
                    finish = InferenceFinish(reason: .toolCall, providerMetadata: state.geminiInteractionProviderMetadata)
                }
            }
        default:
            break
        }

        return CloudProviderStreamParseOutput(events: events, finish: finish)
    }

    private mutating func extractChatCompletionEvents(
        _ json: [String: Any],
        providerKind: CloudProviderKind
    ) -> CloudProviderStreamParseOutput {
        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        state.recordOpenAIChatCompletionChunk(json)
        if providerKind == .openRouter {
            state.recordOpenRouterChatCompletionChunk(json)
        }

        if let usage = json["usage"] as? [String: Any],
           let metrics = Self.openAIChatCompletionMetrics(from: usage) {
            events.append(.metrics(metrics))
        }

        let choices = json["choices"] as? [[String: Any]]
        let delta = choices?.first?["delta"] as? [String: Any]

        if let text = Self.openAIChatCompletionText(from: delta?["content"]), !text.isEmpty {
            state.openAIChatCompletionTextEmitted = true
            events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
        }
        if let text = Self.openAIChatCompletionText(from: delta?["refusal"]), !text.isEmpty {
            state.openAIChatCompletionTextEmitted = true
            events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
        }
        let message = choices?.first?["message"] as? [String: Any]
        if !state.openAIChatCompletionTextEmitted,
           let text = Self.openAIChatCompletionText(from: message?["content"]),
           !text.isEmpty {
            state.openAIChatCompletionTextEmitted = true
            events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
        }

        if let toolCalls = delta?["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                let index = call["index"] as? Int ?? 0
                if let id = call["id"] as? String {
                    state.openAIToolIDs[index] = id
                }
                if let function = call["function"] as? [String: Any] {
                    if let name = function["name"] as? String {
                        state.openAIToolNames[index] = name
                    }
                    if let arguments = function["arguments"] as? String {
                        state.openAIArguments[index, default: ""] += arguments
                    }
                }
            }
        }

        if let finishReason = choices?.first?["finish_reason"] as? String {
            finish = Self.openAIFinish(from: finishReason, metadata: state.openAIProviderMetadata)
            if finishReason == "tool_calls" {
                for index in state.openAIToolNames.keys.sorted() {
                    guard let name = state.openAIToolNames[index] else { continue }
                    events.append(.toolCall(ToolCallDelta(
                        id: state.openAIToolIDs[index] ?? UUID().uuidString,
                        name: name,
                        argumentsFragment: state.openAIArguments[index] ?? "{}",
                        isComplete: true
                    )))
                }
                state.clearOpenAITools()
            }
        }

        return CloudProviderStreamParseOutput(events: events, finish: finish)
    }

    private mutating func extractOpenAIResponsesEvents(_ json: [String: Any]) -> CloudProviderStreamParseOutput {
        let type = json["type"] as? String
        if let type {
            state.openAIResponsesEventTypes.insert(type)
            state.recordOpenAIResponseEvent(json, eventType: type)
        }
        if let response = json["response"] as? [String: Any] {
            state.recordOpenAIResponse(response)
        }

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?

        switch type {
        case "error":
            finish = InferenceFinish(
                reason: .error,
                message: Self.openAIStreamErrorMessage(from: json),
                providerMetadata: state.openAIProviderMetadata
            )
        case "response.output_item.added":
            if let index = json["output_index"] as? Int,
               let item = json["item"] as? [String: Any],
               item["type"] as? String == "function_call" {
                state.openAIToolIDs[index] = (item["call_id"] as? String) ?? (item["id"] as? String)
                state.openAIToolNames[index] = item["name"] as? String
                if let arguments = item["arguments"] as? String {
                    state.openAIArguments[index] = arguments
                }
            }
            if !state.openAIResponsesTextEmitted,
               let item = json["item"] as? [String: Any],
               let text = Self.openAIResponsesOutputText(fromOutputItem: item),
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
        case "response.output_item.done":
            if let item = json["item"] as? [String: Any] {
                if !state.openAIResponsesTextEmitted,
                   let text = Self.openAIResponsesOutputText(fromOutputItem: item),
                   !text.isEmpty {
                    state.openAIResponsesTextEmitted = true
                    events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                }
                if let toolCall = Self.openAIResponsesFunctionCall(fromOutputItem: item),
                   state.markOpenAIToolCallCompleted(toolCall) {
                    finish = InferenceFinish(reason: .toolCall, providerMetadata: state.openAIProviderMetadata)
                    events.append(.toolCall(toolCall))
                }
            }
        case "response.output_text.delta":
            if let delta = Self.textValue(from: json["delta"]), !delta.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: delta, tokenCount: 1)))
            }
        case "response.output_text.done":
            if !state.openAIResponsesTextEmitted,
               let text = Self.openAIResponsesOutputText(fromTextEvent: json),
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
        case "response.content_part.done":
            if !state.openAIResponsesTextEmitted,
               let part = json["part"] as? [String: Any],
               let text = Self.openAIResponsesOutputText(fromContentPart: part),
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
        case "response.content_part.added":
            if !state.openAIResponsesTextEmitted,
               let part = json["part"] as? [String: Any],
               let text = Self.openAIResponsesOutputText(fromContentPart: part),
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
        case "response.refusal.delta":
            if let delta = Self.textValue(from: json["delta"]), !delta.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: delta, tokenCount: 1)))
            }
        case "response.refusal.done":
            if !state.openAIResponsesTextEmitted,
               let refusal = Self.textValue(from: json["refusal"]),
               !refusal.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: refusal, tokenCount: 1)))
            }
        case "response.function_call_arguments.delta":
            let index = json["output_index"] as? Int ?? 0
            if let itemID = json["item_id"] as? String {
                state.openAIToolIDs[index] = state.openAIToolIDs[index] ?? itemID
            }
            if let delta = json["delta"] as? String {
                state.openAIArguments[index, default: ""] += delta
            }
        case "response.function_call_arguments.done":
            let index = json["output_index"] as? Int ?? 0
            let item = json["item"] as? [String: Any]
            if let itemID = json["item_id"] as? String {
                state.openAIToolIDs[index] = state.openAIToolIDs[index] ?? itemID
            } else if let itemID = (item?["call_id"] as? String) ?? (item?["id"] as? String) {
                state.openAIToolIDs[index] = state.openAIToolIDs[index] ?? itemID
            }
            if let name = json["name"] as? String {
                state.openAIToolNames[index] = name
            } else if let name = item?["name"] as? String {
                state.openAIToolNames[index] = name
            }
            if let arguments = json["arguments"] as? String {
                state.openAIArguments[index] = arguments
            } else if let arguments = item?["arguments"] as? String {
                state.openAIArguments[index] = arguments
            }
            if let name = state.openAIToolNames[index] {
                let toolCall = ToolCallDelta(
                    id: state.openAIToolIDs[index] ?? UUID().uuidString,
                    name: name,
                    argumentsFragment: state.openAIArguments[index] ?? "{}",
                    isComplete: true
                )
                state.openAIToolIDs.removeValue(forKey: index)
                state.openAIToolNames.removeValue(forKey: index)
                state.openAIArguments.removeValue(forKey: index)
                if state.markOpenAIToolCallCompleted(toolCall) {
                    finish = InferenceFinish(reason: .toolCall, providerMetadata: state.openAIProviderMetadata)
                    events.append(.toolCall(toolCall))
                }
            }
        case "response.completed", "response.done":
            let response = json["response"] as? [String: Any]
            if !state.openAIResponsesTextEmitted,
               let response,
               let text = Self.openAIResponsesOutputText(from: response),
               !text.isEmpty {
                state.openAIResponsesTextEmitted = true
                events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
            }
            if let response {
                for toolCall in Self.openAIResponsesFunctionCalls(from: response) where state.markOpenAIToolCallCompleted(toolCall) {
                    events.append(.toolCall(toolCall))
                }
                if let metrics = Self.openAIResponsesMetrics(from: response) {
                    events.append(.metrics(metrics))
                }
            }
            let hasToolCalls = !state.completedOpenAIToolCallIDs.isEmpty || events.contains { event in
                if case .toolCall = event { return true }
                return false
            }
            let finishReason: InferenceFinishReason = hasToolCalls ? .toolCall : .stop
            finish = InferenceFinish(
                reason: finishReason,
                message: finishReason == .stop && !state.openAIResponsesTextEmitted
                    ? Self.openAIResponsesEmptyOutputMessage(response: response, eventTypes: state.openAIResponsesEventTypes)
                    : nil,
                providerMetadata: state.openAIProviderMetadata
            )
        case "response.incomplete":
            let response = json["response"] as? [String: Any]
            let details = response?["incomplete_details"] as? [String: Any]
            let reason = details?["reason"] as? String
            finish = InferenceFinish(
                reason: reason == "max_output_tokens" ? .length : .error,
                message: reason == "max_output_tokens"
                    ? "The selected OpenAI model used its max output token budget before producing visible output."
                    : "The selected OpenAI model returned an incomplete response.",
                providerMetadata: state.openAIProviderMetadata
            )
        case "response.failed":
            let response = json["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            finish = InferenceFinish(
                reason: .error,
                message: error?["message"] as? String ?? "The selected OpenAI model failed to produce a response.",
                providerMetadata: state.openAIProviderMetadata
            )
        default:
            break
        }

        return CloudProviderStreamParseOutput(events: events, finish: finish)
    }

    private static func openAIResponsesFunctionCalls(from response: [String: Any]) -> [ToolCallDelta] {
        guard let output = response["output"] as? [[String: Any]] else { return [] }
        return output.compactMap(openAIResponsesFunctionCall(fromOutputItem:))
    }

    private static func openAIResponsesFunctionCall(fromOutputItem item: [String: Any]) -> ToolCallDelta? {
        guard item["type"] as? String == "function_call",
              let name = item["name"] as? String
        else {
            return nil
        }
        return ToolCallDelta(
            id: (item["call_id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString,
            name: name,
            argumentsFragment: item["arguments"] as? String ?? "{}",
            isComplete: true
        )
    }

    private static func openAIResponsesMetrics(from response: [String: Any]) -> InferenceMetrics? {
        guard let usage = response["usage"] as? [String: Any] else { return nil }
        let inputTokens = valueOrAlias(usage["input_tokens"], usage["prompt_tokens"])
        let outputTokens = valueOrAlias(usage["output_tokens"], usage["completion_tokens"])
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return InferenceMetrics(promptTokens: inputTokens, completionTokens: outputTokens)
    }

    private static func openAIResponsesOutputText(from response: [String: Any]) -> String? {
        if let outputText = textValue(from: response["output_text"]), !outputText.isEmpty {
            return outputText
        }
        guard let output = response["output"] as? [[String: Any]] else { return nil }
        let text = output.compactMap(openAIResponsesOutputText(fromOutputItem:)).joined()
        return text.isEmpty ? nil : text
    }

    private static func openAIResponsesOutputText(fromOutputItem item: [String: Any]) -> String? {
        if let text = openAIResponsesOutputText(fromContentPart: item), !text.isEmpty {
            return text
        }
        let text: String?
        if let content = item["content"] as? [[String: Any]] {
            text = content.compactMap(openAIResponsesOutputText(fromContentPart:)).joined()
        } else {
            text = textValue(from: item["content"])
        }
        return text?.isEmpty == false ? text : nil
    }

    private static func openAIResponsesOutputText(fromTextEvent event: [String: Any]) -> String? {
        let text = textValue(from: event["text"])
            ?? textValue(from: event["delta"])
            ?? textValue(from: event["content"])
            ?? textValue(from: event["output_text"])
        return text?.isEmpty == false ? text : nil
    }

    private static func openAIResponsesOutputText(fromContentPart part: [String: Any]) -> String? {
        let type = part["type"] as? String
        guard type == nil || type == "output_text" || type == "text" || type == "refusal" else {
            return nil
        }
        let text = textValue(from: part["text"])
            ?? textValue(from: part["content"])
            ?? textValue(from: part["refusal"])
        return text?.isEmpty == false ? text : nil
    }

    private static func textValue(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let object = value as? [String: Any] {
            for key in ["text", "value", "content", "refusal", "output_text"] {
                if let text = textValue(from: object[key]), !text.isEmpty {
                    return text
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            let text = array.compactMap(textValue(from:)).joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func openAIChatCompletionText(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let parts = value as? [[String: Any]] {
            let text = parts.compactMap { part -> String? in
                let type = part["type"] as? String
                guard type == nil || type == "text" || type == "output_text" else { return nil }
                return (part["text"] as? String)
                    ?? ((part["text"] as? [String: Any])?["value"] as? String)
            }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func openAIResponsesEmptyOutputMessage(response: [String: Any]?, eventTypes: Set<String>) -> String {
        let status = response?["status"] as? String
        let outputItems = response?["output"] as? [[String: Any]]
        let outputCount = outputItems?.count
        var details = [String]()
        if let status {
            details.append("status: \(status)")
        }
        if let outputCount {
            details.append("output items: \(outputCount)")
        }
        if let outputItems {
            let outputTypes = outputItems.compactMap { item in
                let type = item["type"] as? String
                return type?.isEmpty == false ? type : nil
            }
            if !outputTypes.isEmpty {
                details.append("output types: \(outputTypes.joined(separator: ", "))")
            }
        }
        if !eventTypes.isEmpty {
            details.append("events: \(eventTypes.sorted().joined(separator: ", "))")
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))."
        return "OpenAI completed the Responses stream without visible output text\(suffix)"
    }

    private static func openAIStreamErrorMessage(from json: [String: Any]) -> String {
        let error = (json["error"] as? [String: Any]) ?? json
        if let message = textValue(from: error["message"]) ?? textValue(from: json["message"]), !message.isEmpty {
            return message
        }
        if let code = textValue(from: error["code"]), !code.isEmpty {
            return "OpenAI stream failed with error code \(code)."
        }
        return "OpenAI stream failed before producing a response."
    }

    private static func openAIFinish(from finishReason: String, metadata: [String: String]) -> InferenceFinish {
        switch finishReason {
        case "length":
            return InferenceFinish(
                reason: .length,
                message: "The selected OpenAI model used its completion token budget before producing visible output. Try again with a larger completion limit.",
                providerMetadata: metadata
            )
        case "tool_calls":
            return InferenceFinish(reason: .toolCall, providerMetadata: metadata)
        case "content_filter":
            return InferenceFinish(reason: .error, message: "The provider stopped the response because of its content filter.", providerMetadata: metadata)
        default:
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        }
    }

    private static func openAIChatCompletionMetrics(from usage: [String: Any]) -> InferenceMetrics? {
        let inputTokens = valueOrAlias(usage["prompt_tokens"], usage["input_tokens"])
        let outputTokens = valueOrAlias(usage["completion_tokens"], usage["output_tokens"])
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return InferenceMetrics(promptTokens: inputTokens, completionTokens: outputTokens)
    }

    private static func anthropicFinish(from stopReason: String, metadata: [String: String]) -> InferenceFinish {
        switch stopReason {
        case "tool_use":
            return InferenceFinish(reason: .toolCall, providerMetadata: metadata)
        case "max_tokens", "model_context_window_exceeded":
            return InferenceFinish(reason: .length, providerMetadata: metadata)
        case "stop_sequence", "end_turn":
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        case "refusal":
            return InferenceFinish(reason: .error, message: "Anthropic stopped the response with a refusal.", providerMetadata: metadata)
        case "pause_turn":
            return InferenceFinish(reason: .error, message: "Anthropic paused the turn before completing a response.", providerMetadata: metadata)
        default:
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        }
    }

    private static func anthropicMetrics(from usage: [String: Any]) -> InferenceMetrics? {
        let inputTokens = intValue(usage["input_tokens"])
            + intValue(usage["cache_creation_input_tokens"])
            + intValue(usage["cache_read_input_tokens"])
        let outputTokens = intValue(usage["output_tokens"])
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return InferenceMetrics(promptTokens: inputTokens, completionTokens: outputTokens)
    }

    private static func geminiFinish(from finishReason: String, hasToolCalls: Bool, metadata: [String: String]) -> InferenceFinish {
        if hasToolCalls {
            return InferenceFinish(reason: .toolCall, providerMetadata: metadata)
        }
        switch finishReason {
        case "STOP":
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        case "MAX_TOKENS":
            return InferenceFinish(reason: .length, providerMetadata: metadata)
        case "SAFETY":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because of safety settings.", providerMetadata: metadata)
        case "RECITATION":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because of recitation policy.", providerMetadata: metadata)
        case "LANGUAGE":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because the language is unsupported.", providerMetadata: metadata)
        case "BLOCKLIST":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because the prompt or output matched a blocklist.", providerMetadata: metadata)
        case "PROHIBITED_CONTENT":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because it contained prohibited content.", providerMetadata: metadata)
        case "SPII":
            return InferenceFinish(reason: .error, message: "Gemini stopped the response because it contained sensitive personal data.", providerMetadata: metadata)
        case "MALFORMED_FUNCTION_CALL":
            return InferenceFinish(reason: .error, message: "Gemini returned a malformed function call.", providerMetadata: metadata)
        default:
            return InferenceFinish(reason: .stop, providerMetadata: metadata)
        }
    }

    private static func geminiPromptFeedbackFinish(from promptFeedback: [String: Any], metadata: [String: String]) -> InferenceFinish? {
        guard let blockReason = promptFeedback["blockReason"] as? String, !blockReason.isEmpty else {
            return nil
        }
        let message = promptFeedback["blockReasonMessage"] as? String
            ?? "Gemini blocked the prompt with reason: \(blockReason)."
        return InferenceFinish(reason: .error, message: message, providerMetadata: metadata)
    }

    private static func geminiMetrics(from usage: [String: Any]) -> InferenceMetrics? {
        let inputTokens = intValue(usage["promptTokenCount"])
        let outputTokens = intValue(usage["candidatesTokenCount"])
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return InferenceMetrics(promptTokens: inputTokens, completionTokens: outputTokens)
    }

    private static func geminiInteractionMetrics(from usage: [String: Any]) -> InferenceMetrics? {
        let inputTokens = intValue(usage["total_input_tokens"])
        let outputTokens = intValue(usage["total_output_tokens"])
        guard inputTokens > 0 || outputTokens > 0 else { return nil }
        return InferenceMetrics(promptTokens: inputTokens, completionTokens: outputTokens)
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return 0
    }

    private static func valueOrAlias(_ primary: Any?, _ fallback: Any?) -> Int {
        let primaryValue = intValue(primary)
        return primaryValue > 0 ? primaryValue : intValue(fallback)
    }

    public static func jsonString(from value: Any?) -> String? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

public struct CloudProviderStreamState {
    public var openAIToolIDs: [Int: String] = [:]
    public var openAIToolNames: [Int: String] = [:]
    public var openAIArguments: [Int: String] = [:]
    public var openAIChatCompletionTextEmitted = false
    public var openAIResponsesTextEmitted = false
    public var openAIResponsesEventTypes = Set<String>()
    public var openAIProviderMetadata = [String: String]()
    public var completedOpenAIToolCallIDs = Set<String>()
    public var openAIHostedToolCalls = [[String: Any]]()
    public var openAIFileSearchResults = [[String: Any]]()
    public var openAIArtifacts = [[String: Any]]()

    public var anthropicToolIndex: Int?
    public var anthropicToolID: String?
    public var anthropicToolName: String?
    public var anthropicArguments = ""
    public var anthropicProviderMetadata = [String: String]()
    public var anthropicThinkingIndex: Int?
    public var anthropicThinkingText = ""
    public var anthropicThinkingSignature: String?
    public var anthropicThinkingBlocks = [[String: Any]]()
    public var anthropicServerToolIndex: Int?
    public var anthropicServerToolID: String?
    public var anthropicServerToolName: String?
    public var anthropicServerToolArguments = ""
    public var anthropicHostedToolCalls = [[String: Any]]()
    public var anthropicArtifacts = [[String: Any]]()
    public var anthropicFileReferences = [[String: Any]]()
    public var anthropicProviderCitations = [[String: Any]]()

    public var geminiProviderMetadata = [String: String]()
    public var geminiCompletedToolCallIDs = Set<String>()
    public var geminiModelContent: [String: Any]?
    public var geminiCodeExecution = [[String: Any]]()
    public var geminiURLContext = [[String: Any]]()
    public var geminiFileReferences = [[String: Any]]()
    public var geminiArtifacts = [[String: Any]]()

    public var geminiInteractionProviderMetadata = [String: String]()
    public var geminiInteractionToolIDs: [Int: String] = [:]
    public var geminiInteractionToolNames: [Int: String] = [:]
    public var geminiInteractionArguments: [Int: String] = [:]
    public var geminiInteractionCompletedToolCallIDs = Set<String>()
    public var geminiInteractionCodeExecution = [[String: Any]]()
    public var geminiInteractionURLContext = [[String: Any]]()
    public var geminiInteractionFileReferences = [[String: Any]]()
    public var geminiInteractionArtifacts = [[String: Any]]()

    public init() {}

    private static func recordSearchCitations(_ citations: [WebSearchCitation], into metadata: inout [String: String]) {
        guard !citations.isEmpty else { return }
        var combined = existingCitations(from: metadata)
        for citation in citations where !combined.contains(where: { $0.url == citation.url && $0.title == citation.title }) {
            combined.append(citation)
        }
        guard let data = try? JSONEncoder().encode(combined.prefix(24).map { $0 }) else { return }
        metadata[CloudProviderMetadataKeys.webSearchCitationsJSON] = String(decoding: data, as: UTF8.self)
    }

    private static func recordSearchQueries(_ queries: [String], into metadata: inout [String: String]) {
        let cleanQueries = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanQueries.isEmpty else { return }
        var combined = existingQueries(from: metadata)
        for query in cleanQueries where !combined.contains(query) {
            combined.append(query)
        }
        guard let data = try? JSONEncoder().encode(Array(combined.prefix(24))) else { return }
        metadata[CloudProviderMetadataKeys.webSearchQueriesJSON] = String(decoding: data, as: UTF8.self)
    }

    private static func recordSearchSuggestionsHTML(_ html: String?, into metadata: inout [String: String]) {
        guard let html = html?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty else { return }
        metadata[CloudProviderMetadataKeys.webSearchSuggestionsHTML] = html
    }

    private static func existingCitations(from metadata: [String: String]) -> [WebSearchCitation] {
        guard let raw = metadata[CloudProviderMetadataKeys.webSearchCitationsJSON],
              let data = raw.data(using: .utf8),
              let citations = try? JSONDecoder().decode([WebSearchCitation].self, from: data)
        else { return [] }
        return citations
    }

    private static func existingQueries(from metadata: [String: String]) -> [String] {
        guard let raw = metadata[CloudProviderMetadataKeys.webSearchQueriesJSON],
              let data = raw.data(using: .utf8),
              let queries = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return queries
    }

    private static func existingProviderCitations(from metadata: [String: String]) -> [ProviderCitation] {
        guard let raw = metadata[CloudProviderMetadataKeys.providerCitationsJSON],
              let data = raw.data(using: .utf8),
              let citations = try? JSONDecoder().decode([ProviderCitation].self, from: data)
        else { return [] }
        return citations
    }

    private static func openAIWebSearchCitations(from response: [String: Any]) -> [WebSearchCitation] {
        var citations = [WebSearchCitation]()
        for item in response["output"] as? [[String: Any]] ?? [] {
            if let content = item["content"] as? [[String: Any]] {
                for part in content {
                    citations.append(contentsOf: openAIAnnotationCitations(from: part["annotations"]))
                }
            }
            citations.append(contentsOf: openAIAnnotationCitations(from: item["annotations"]))
            if let sources = item["sources"] as? [[String: Any]] {
                citations.append(contentsOf: sourceCitations(from: sources, provider: "OpenAI"))
            }
        }
        if let sources = response["sources"] as? [[String: Any]] {
            citations.append(contentsOf: sourceCitations(from: sources, provider: "OpenAI"))
        }
        return citations
    }

    private static func openAIAnnotationCitations(from value: Any?) -> [WebSearchCitation] {
        (value as? [[String: Any]] ?? []).compactMap { annotation in
            guard annotation["type"] as? String == "url_citation",
                  let url = stringValue(annotation["url"]),
                  !url.isEmpty
            else { return nil }
            return WebSearchCitation(
                title: stringValue(annotation["title"]) ?? url,
                url: url,
                source: "OpenAI"
            )
        }
    }

    private static func openAIWebSearchQueries(from response: [String: Any]) -> [String] {
        var queries = [String]()
        for item in response["output"] as? [[String: Any]] ?? [] where item["type"] as? String == "web_search_call" {
            if let action = item["action"] as? [String: Any] {
                if let query = stringValue(action["query"]) {
                    queries.append(query)
                }
                queries.append(contentsOf: (action["queries"] as? [Any] ?? []).compactMap(stringValue))
            }
        }
        return queries
    }

    private static func openAIHostedToolCalls(from response: [String: Any]) -> [[String: Any]] {
        (response["output"] as? [[String: Any]] ?? []).compactMap(openAIHostedToolCallSummary(from:))
    }

    private static func openAIHostedToolCallSummary(from item: [String: Any]) -> [String: Any]? {
        guard let type = item["type"] as? String,
              Self.openAIHostedToolTypes.contains(type)
        else { return nil }
        var summary: [String: Any] = [
            "id": stringValue(item["id"]) ?? "",
            "type": type,
            "status": stringValue(item["status"]) ?? "",
        ]
        if let action = item["action"] as? [String: Any] {
            summary["action"] = action
        }
        if let containerID = stringValue(item["container_id"]) {
            summary["container_id"] = containerID
        }
        if let revisedPrompt = stringValue(item["revised_prompt"]) {
            summary["revised_prompt"] = revisedPrompt
        }
        if let toolName = stringValue(item["name"]) {
            summary["name"] = toolName
        }
        return summary
    }

    private static func openAIHostedToolCallSummary(fromStreamingEvent event: [String: Any], eventType: String) -> [String: Any]? {
        guard let toolType = openAIHostedToolType(fromStreamingEventType: eventType) else { return nil }
        let id = stringValue(event["item_id"])
            ?? stringValue(event["output_item_id"])
            ?? stringValue(event["call_id"])
            ?? stringValue(event["id"])
            ?? ""
        var summary: [String: Any] = [
            "id": id,
            "type": toolType,
            "status": stringValue(event["status"]) ?? openAIToolStatus(fromStreamingEventType: eventType),
        ]
        for key in [
            "action",
            "pending_safety_checks",
            "output",
            "input",
            "arguments",
        ] where event[key] != nil {
            summary[key] = event[key]
        }
        for key in [
            "container_id",
            "server_label",
            "server_url",
            "require_approval",
            "name",
        ] {
            if let value = stringValue(event[key]) {
                summary[key] = value
            }
        }
        return summary
    }

    private static func openAIHostedToolType(fromStreamingEventType eventType: String) -> String? {
        if eventType.contains("web_search_call") { return "web_search_call" }
        if eventType.contains("file_search_call") { return "file_search_call" }
        if eventType.contains("code_interpreter_call") { return "code_interpreter_call" }
        if eventType.contains("image_generation_call") { return "image_generation_call" }
        if eventType.contains("computer_call") { return "computer_call" }
        if eventType.contains("mcp_call") { return "mcp_call" }
        if eventType.contains("mcp_list_tools") { return "mcp_list_tools" }
        if eventType.contains("tool_search_call") { return "tool_search_call" }
        return nil
    }

    private static func openAIToolStatus(fromStreamingEventType eventType: String) -> String {
        if eventType.hasSuffix(".completed") || eventType.hasSuffix(".done") {
            return "completed"
        }
        if eventType.hasSuffix(".failed") {
            return "failed"
        }
        if eventType.hasSuffix(".requires_action") {
            return "requires_action"
        }
        return "in_progress"
    }

    private static let openAIHostedToolTypes: Set<String> = [
        "web_search_call",
        "file_search_call",
        "code_interpreter_call",
        "image_generation_call",
        "computer_call",
        "computer_call_output",
        "mcp_call",
        "mcp_list_tools",
        "tool_search_call",
        "shell_call",
    ]

    private static func openAIFileSearchResults(from response: [String: Any]) -> [[String: Any]] {
        (response["output"] as? [[String: Any]] ?? []).flatMap { item -> [[String: Any]] in
            guard item["type"] as? String == "file_search_call" else { return [] }
            if let results = item["results"] as? [[String: Any]] {
                return results
            }
            if let result = item["result"] as? [String: Any] {
                return [result]
            }
            return []
        }
    }

    private static func openAIArtifacts(from response: [String: Any]) -> [[String: Any]] {
        var artifacts = [[String: Any]]()
        for item in response["output"] as? [[String: Any]] ?? [] {
            if let artifact = openAIArtifactSummary(from: item) {
                artifacts.append(artifact)
            }
            artifacts.append(contentsOf: openAIArtifacts(fromCodeInterpreterOutputs: item))
            for content in item["content"] as? [[String: Any]] ?? [] {
                artifacts.append(contentsOf: openAIArtifacts(fromAnnotations: content["annotations"]))
            }
        }
        return artifacts
    }

    private static func openAIArtifactSummary(from item: [String: Any]) -> [String: Any]? {
        guard let type = item["type"] as? String else { return nil }
        if type == "image_generation_call" {
            var artifact: [String: Any] = [
                "type": "image",
                "provider_item_id": stringValue(item["id"]) ?? "",
                "status": stringValue(item["status"]) ?? "",
            ]
            if let revisedPrompt = stringValue(item["revised_prompt"]) {
                artifact["prompt"] = revisedPrompt
            }
            if let result = stringValue(item["result"]), !result.isEmpty {
                artifact["encoding"] = "base64"
                artifact["byte_hint"] = result.count
            }
            return artifact
        }
        if type == "code_interpreter_call" {
            var artifact: [String: Any] = [
                "type": "code_interpreter",
                "provider_item_id": stringValue(item["id"]) ?? "",
                "status": stringValue(item["status"]) ?? "",
            ]
            if let containerID = stringValue(item["container_id"]) {
                artifact["container_id"] = containerID
            }
            if let outputs = item["outputs"] as? [[String: Any]] {
                artifact["outputs"] = outputs
            }
            return artifact
        }
        return nil
    }

    private static func openAIArtifacts(fromStreamingEvent event: [String: Any], eventType: String) -> [[String: Any]] {
        var artifacts = [[String: Any]]()
        let providerItemID = stringValue(event["item_id"])
            ?? stringValue(event["output_item_id"])
            ?? stringValue(event["id"])
            ?? ""
        let containerID = stringValue(event["container_id"]) ?? ""

        if eventType.contains("image_generation_call"),
           eventType.contains("partial_image") || event["partial_image_b64"] != nil || event["partial_image"] != nil {
            let image = stringValue(event["partial_image_b64"])
                ?? stringValue(event["partial_image"])
                ?? stringValue(event["b64_json"])
                ?? stringValue(event["result"])
            var artifact: [String: Any] = [
                "type": "partial_image",
                "provider_item_id": providerItemID,
                "status": stringValue(event["status"]) ?? openAIToolStatus(fromStreamingEventType: eventType),
            ]
            if event["partial_image_index"] != nil {
                artifact["index"] = intValue(event["partial_image_index"])
            }
            if let image, !image.isEmpty {
                artifact["encoding"] = "base64"
                artifact["byte_hint"] = image.count
            }
            artifacts.append(artifact)
        }

        if eventType.contains("code_interpreter_call") {
            if let logs = stringValue(event["logs"]) ?? stringValue(event["delta"]) ?? stringValue(event["output"]), !logs.isEmpty {
                artifacts.append([
                    "type": "code_interpreter_logs",
                    "provider_item_id": providerItemID,
                    "container_id": containerID,
                    "logs": logs,
                ])
            }
            artifacts.append(contentsOf: openAIContainerFileArtifacts(from: event["files"], providerItemID: providerItemID, containerID: containerID))
            artifacts.append(contentsOf: openAIContainerFileArtifacts(from: event["generated_files"], providerItemID: providerItemID, containerID: containerID))
        }

        if let output = event["output"] as? [String: Any] {
            artifacts.append(contentsOf: openAIArtifacts(fromCodeInterpreterOutputs: [
                "id": providerItemID,
                "type": "code_interpreter_call",
                "container_id": containerID,
                "outputs": [output],
            ]))
        } else if let outputs = event["output"] as? [[String: Any]] {
            artifacts.append(contentsOf: openAIArtifacts(fromCodeInterpreterOutputs: [
                "id": providerItemID,
                "type": "code_interpreter_call",
                "container_id": containerID,
                "outputs": outputs,
            ]))
        }
        return artifacts
    }

    private static func openAIArtifacts(fromAnnotations value: Any?) -> [[String: Any]] {
        (value as? [[String: Any]] ?? []).compactMap { annotation in
            guard ["container_file_citation", "file_citation"].contains(annotation["type"] as? String) else { return nil }
            return [
                "type": "container_file",
                "container_id": stringValue(annotation["container_id"]) ?? "",
                "file_id": stringValue(annotation["file_id"]) ?? "",
                "filename": stringValue(annotation["filename"]) ?? stringValue(annotation["file_name"]) ?? "",
            ]
        }
    }

    private static func openAIArtifacts(fromCodeInterpreterOutputs item: [String: Any]) -> [[String: Any]] {
        guard item["type"] as? String == "code_interpreter_call" else { return [] }
        let providerItemID = stringValue(item["id"]) ?? ""
        let containerID = stringValue(item["container_id"]) ?? ""
        return (item["outputs"] as? [[String: Any]] ?? []).flatMap { output -> [[String: Any]] in
            var artifacts = [[String: Any]]()
            if let logs = stringValue(output["logs"]) ?? stringValue(output["output"]), !logs.isEmpty {
                artifacts.append([
                    "type": "code_interpreter_logs",
                    "provider_item_id": providerItemID,
                    "container_id": containerID,
                    "logs": logs,
                ])
            }
            artifacts.append(contentsOf: openAIContainerFileArtifacts(from: output["files"], providerItemID: providerItemID, containerID: containerID))
            artifacts.append(contentsOf: openAIContainerFileArtifacts(from: output["generated_files"], providerItemID: providerItemID, containerID: containerID))
            return artifacts
        }
    }

    private static func openAIContainerFileArtifacts(from value: Any?, providerItemID: String, containerID: String) -> [[String: Any]] {
        (value as? [[String: Any]] ?? []).compactMap { file in
            guard let fileID = stringValue(file["file_id"]) ?? stringValue(file["id"]), !fileID.isEmpty else { return nil }
            return [
                "type": "container_file",
                "provider_item_id": providerItemID,
                "container_id": stringValue(file["container_id"]) ?? containerID,
                "file_id": fileID,
                "filename": stringValue(file["filename"]) ?? stringValue(file["file_name"]) ?? "",
            ]
        }
    }

    private static func anthropicWebSearchCitations(from value: [String: Any]) -> [WebSearchCitation] {
        var citations = [WebSearchCitation]()
        let contentArray = value["content"] as? [[String: Any]] ?? []
        citations.append(contentsOf: sourceCitations(from: contentArray, provider: "Anthropic"))
        citations.append(contentsOf: anthropicCitationLocations(from: value["citations"]))
        for block in contentArray {
            citations.append(contentsOf: anthropicCitationLocations(from: block["citations"]))
            if let nested = block["content"] as? [[String: Any]] {
                citations.append(contentsOf: sourceCitations(from: nested, provider: "Anthropic"))
            }
        }
        return citations
    }

    private static func anthropicCitationLocations(from value: Any?) -> [WebSearchCitation] {
        (value as? [[String: Any]] ?? []).compactMap { citation in
            guard let url = stringValue(citation["url"]), !url.isEmpty else { return nil }
            return WebSearchCitation(
                title: stringValue(citation["title"]) ?? url,
                url: url,
                source: "Anthropic"
            )
        }
    }

    private static func anthropicProviderCitations(from value: [String: Any]) -> [ProviderCitation] {
        var citations = [ProviderCitation]()
        citations.append(contentsOf: anthropicProviderCitations(fromCitationValue: value["citations"]))
        for block in value["content"] as? [[String: Any]] ?? [] {
            citations.append(contentsOf: anthropicProviderCitations(fromCitationValue: block["citations"]))
            if let nested = block["content"] as? [[String: Any]] {
                for nestedBlock in nested {
                    citations.append(contentsOf: anthropicProviderCitations(fromCitationValue: nestedBlock["citations"]))
                }
            }
        }
        return citations
    }

    private static func anthropicProviderCitations(fromCitationValue value: Any?) -> [ProviderCitation] {
        (value as? [[String: Any]] ?? []).compactMap { citation in
            let type = stringValue(citation["type"]) ?? "unknown"
            let url = stringValue(citation["url"])
            let fileID = stringValue(citation["file_id"]) ?? stringValue(citation["fileId"])
            let title = stringValue(citation["title"])
                ?? stringValue(citation["document_title"])
                ?? stringValue(citation["cited_text"])
                ?? url
                ?? fileID
            let startOffset = citation["start_char_index"] == nil ? nil : intValue(citation["start_char_index"])
            let endOffset = citation["end_char_index"] == nil ? nil : intValue(citation["end_char_index"])
            let page = positiveInt(citation["page"])
                ?? positiveInt(citation["page_number"])
                ?? positiveInt(citation["start_page_number"])
            var idParts = [String]()
            idParts.append(type)
            if let url, !url.isEmpty { idParts.append(url) }
            if let fileID, !fileID.isEmpty { idParts.append(fileID) }
            if let page { idParts.append(String(page)) }
            if let startOffset { idParts.append(String(startOffset)) }
            if let endOffset { idParts.append(String(endOffset)) }
            if let citedText = stringValue(citation["cited_text"]), !citedText.isEmpty {
                idParts.append(citedText)
            }
            let raw = jsonValue(from: citation)
            return ProviderCitation(
                id: idParts.isEmpty ? UUID().uuidString : idParts.joined(separator: "#"),
                providerKind: .anthropic,
                sourceType: anthropicCitationSourceType(type: type, url: url, fileID: fileID),
                title: title,
                url: url,
                fileID: fileID,
                page: page,
                chunkID: stringValue(citation["chunk_id"]) ?? stringValue(citation["content_block_id"]),
                documentID: stringValue(citation["document_id"]),
                startOffset: startOffset,
                endOffset: endOffset,
                citedText: stringValue(citation["cited_text"]) ?? stringValue(citation["text"]),
                source: "Anthropic",
                raw: raw
            )
        }
    }

    private static func anthropicCitationSourceType(type: String, url: String?, fileID: String?) -> ProviderCitationSourceType {
        if url != nil || type.contains("web") {
            return .web
        }
        if type.contains("page") || type.contains("pdf") {
            return .pdf
        }
        if fileID != nil {
            return .file
        }
        if type.contains("search") {
            return .searchResult
        }
        if type.contains("char") || type.contains("content_block") {
            return .text
        }
        return .unknown
    }

    private static func anthropicHostedToolSummary(from block: [String: Any], status: String) -> [String: Any]? {
        guard let type = stringValue(block["type"]), !type.isEmpty else { return nil }
        let isHosted = type == "server_tool_use"
            || type.hasSuffix("_tool_result")
            || type.contains("web_search")
            || type.contains("web_fetch")
            || type.contains("code_execution")
            || type.contains("mcp")
        guard isHosted else { return nil }
        var summary: [String: Any] = [
            "id": stringValue(block["id"]) ?? stringValue(block["tool_use_id"]) ?? "",
            "type": type,
            "status": status,
        ]
        if let name = stringValue(block["name"]) {
            summary["name"] = name
        }
        if let toolUseID = stringValue(block["tool_use_id"]) {
            summary["tool_use_id"] = toolUseID
        }
        for key in ["input", "content", "result", "error", "is_error", "server_name", "server_label"] where block[key] != nil {
            summary[key] = block[key]
        }
        return summary
    }

    private static func anthropicArtifacts(from value: [String: Any]) -> [[String: Any]] {
        var artifacts = [[String: Any]]()
        collectAnthropicArtifacts(in: value, records: &artifacts)
        return artifacts
    }

    private static func collectAnthropicArtifacts(in value: Any?, records: inout [[String: Any]]) {
        if let object = value as? [String: Any] {
            if let fileID = stringValue(object["file_id"]) ?? stringValue((object["file"] as? [String: Any])?["id"]) {
                var artifact: [String: Any] = [
                    "type": stringValue(object["type"]) ?? "file_reference",
                    "file_id": fileID,
                ]
                for key in ["filename", "file_name", "name", "mime_type", "mimeType", "size_bytes", "bytes", "tool_use_id", "id"] {
                    if let value = object[key] {
                        artifact[key] = value
                    }
                }
                records.append(artifact)
            }
            for child in object.values {
                collectAnthropicArtifacts(in: child, records: &records)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectAnthropicArtifacts(in: child, records: &records)
            }
        }
    }

    private static func anthropicFileReferences(from value: [String: Any]) -> [[String: Any]] {
        anthropicArtifacts(from: value).filter { object in
            object["file_id"] != nil
        }
    }

    private static func geminiWebSearchCitations(from response: [String: Any]) -> [WebSearchCitation] {
        (response["candidates"] as? [[String: Any]] ?? []).flatMap { candidate in
            geminiGroundingCitations(from: candidate["groundingMetadata"] as? [String: Any])
        }
    }

    private static func geminiWebSearchQueries(from response: [String: Any]) -> [String] {
        (response["candidates"] as? [[String: Any]] ?? []).flatMap { candidate in
            geminiGroundingQueries(from: candidate["groundingMetadata"] as? [String: Any])
        }
    }

    private static func geminiInteractionWebSearchCitations(from interaction: [String: Any]) -> [WebSearchCitation] {
        var citations = geminiGroundingCitations(from: interaction["groundingMetadata"] as? [String: Any])
        for output in interaction["outputs"] as? [[String: Any]] ?? [] {
            citations.append(contentsOf: geminiGroundingCitations(from: output["groundingMetadata"] as? [String: Any]))
            citations.append(contentsOf: sourceCitations(from: output["groundingChunks"] as? [[String: Any]] ?? [], provider: "Gemini"))
        }
        return citations
    }

    private static func geminiInteractionWebSearchQueries(from interaction: [String: Any]) -> [String] {
        var queries = geminiGroundingQueries(from: interaction["groundingMetadata"] as? [String: Any])
        for output in interaction["outputs"] as? [[String: Any]] ?? [] {
            queries.append(contentsOf: geminiGroundingQueries(from: output["groundingMetadata"] as? [String: Any]))
            queries.append(contentsOf: (output["webSearchQueries"] as? [Any] ?? []).compactMap(stringValue))
        }
        return queries
    }

    private static func geminiGroundingCitations(from metadata: [String: Any]?) -> [WebSearchCitation] {
        guard let metadata else { return [] }
        return sourceCitations(from: metadata["groundingChunks"] as? [[String: Any]] ?? [], provider: "Gemini")
    }

    private static func geminiGroundingQueries(from metadata: [String: Any]?) -> [String] {
        guard let metadata else { return [] }
        return (metadata["webSearchQueries"] as? [Any] ?? []).compactMap(stringValue)
    }

    private static func geminiGroundingSearchSuggestionsHTML(from metadata: [String: Any]?) -> String? {
        guard let metadata,
              let searchEntryPoint = metadata["searchEntryPoint"] as? [String: Any]
        else { return nil }
        return stringValue(searchEntryPoint["renderedContent"])
    }

    private static func geminiSearchSuggestionsHTML(from response: [String: Any]) -> String? {
        for candidate in response["candidates"] as? [[String: Any]] ?? [] {
            if let html = geminiGroundingSearchSuggestionsHTML(from: candidate["groundingMetadata"] as? [String: Any]) {
                return html
            }
        }
        return nil
    }

    private static func geminiInteractionSearchSuggestionsHTML(from interaction: [String: Any]) -> String? {
        if let html = geminiGroundingSearchSuggestionsHTML(from: interaction["groundingMetadata"] as? [String: Any]) {
            return html
        }
        for output in interaction["outputs"] as? [[String: Any]] ?? [] {
            if let html = geminiGroundingSearchSuggestionsHTML(from: output["groundingMetadata"] as? [String: Any]) {
                return html
            }
        }
        return nil
    }

    private static func extractedGeminiCacheUsage(from usage: [String: Any]?) -> [String: Any]? {
        guard let usage else { return nil }
        var summary = [String: Any]()
        for key in [
            "cachedContentTokenCount",
            "cacheTokensDetails",
            "promptTokensDetails",
            "candidatesTokensDetails",
            "toolUsePromptTokenCount",
            "thoughtsTokenCount",
            "totalTokenCount",
            "total_input_tokens",
            "cached_input_tokens",
            "cache_read_input_tokens",
            "cache_creation_input_tokens",
        ] {
            if let value = usage[key] {
                summary[key] = value
            }
        }
        return summary.isEmpty ? nil : summary
    }

    private static func extractedGeminiCodeExecution(fromGenerateContentResponse response: [String: Any]) -> [[String: Any]] {
        (response["candidates"] as? [[String: Any]] ?? []).flatMap { candidate in
            extractedGeminiCodeExecution(fromContent: candidate["content"] as? [String: Any])
        }
    }

    private static func extractedGeminiCodeExecution(fromInteraction interaction: [String: Any]) -> [[String: Any]] {
        var values = [[String: Any]]()
        for output in interactionOutputs(from: interaction) {
            values.append(contentsOf: extractedGeminiCodeExecution(fromContent: output["content"] as? [String: Any]))
            values.append(contentsOf: extractedGeminiCodeExecution(fromParts: output["parts"] as? [[String: Any]] ?? []))
            values.append(contentsOf: codeExecutionObjects(from: output))
        }
        values.append(contentsOf: codeExecutionObjects(from: interaction))
        return values
    }

    private static func extractedGeminiCodeExecution(fromContent content: [String: Any]?) -> [[String: Any]] {
        extractedGeminiCodeExecution(fromParts: content?["parts"] as? [[String: Any]] ?? [])
    }

    private static func extractedGeminiCodeExecution(fromParts parts: [[String: Any]]) -> [[String: Any]] {
        parts.flatMap(codeExecutionObjects(from:))
    }

    private static func codeExecutionObjects(from object: [String: Any]) -> [[String: Any]] {
        var values = [[String: Any]]()
        if let executableCode = object["executableCode"] as? [String: Any] ?? object["executable_code"] as? [String: Any] {
            values.append(["type": "executable_code", "value": executableCode])
        }
        if let result = object["codeExecutionResult"] as? [String: Any] ?? object["code_execution_result"] as? [String: Any] {
            values.append(["type": "code_execution_result", "value": result])
        }
        return values
    }

    private static func extractedGeminiURLContext(fromGenerateContentResponse response: [String: Any]) -> [[String: Any]] {
        var values = [[String: Any]]()
        for candidate in response["candidates"] as? [[String: Any]] ?? [] {
            values.append(contentsOf: urlContextObjects(from: candidate))
            if let metadata = candidate["urlContextMetadata"] as? [String: Any] ?? candidate["url_context_metadata"] as? [String: Any] {
                values.append(metadata)
            }
            if let groundingMetadata = candidate["groundingMetadata"] as? [String: Any] {
                values.append(contentsOf: urlContextObjects(from: groundingMetadata))
            }
        }
        return values
    }

    private static func extractedGeminiURLContext(fromInteraction interaction: [String: Any]) -> [[String: Any]] {
        var values = urlContextObjects(from: interaction)
        for output in interactionOutputs(from: interaction) {
            values.append(contentsOf: urlContextObjects(from: output))
            if let metadata = output["urlContextMetadata"] as? [String: Any] ?? output["url_context_metadata"] as? [String: Any] {
                values.append(metadata)
            }
        }
        return values
    }

    private static func urlContextObjects(from object: [String: Any]) -> [[String: Any]] {
        var values = [[String: Any]]()
        for key in ["urlContextMetadata", "url_context_metadata", "urlMetadata", "url_metadata"] {
            if let value = object[key] as? [String: Any] {
                values.append(value)
            } else if let value = object[key] as? [[String: Any]] {
                values.append(contentsOf: value)
            }
        }
        return values
    }

    private static func extractedGeminiFileReferences(fromGenerateContentResponse response: [String: Any]) -> [[String: Any]] {
        (response["candidates"] as? [[String: Any]] ?? []).flatMap { candidate in
            extractedGeminiFileReferences(fromContent: candidate["content"] as? [String: Any])
        }
    }

    private static func extractedGeminiFileReferences(fromInteraction interaction: [String: Any]) -> [[String: Any]] {
        interactionOutputs(from: interaction).flatMap { output in
            extractedGeminiFileReferences(fromContent: output["content"] as? [String: Any])
                + fileReferenceObjects(from: output)
        }
    }

    private static func extractedGeminiFileReferences(fromContent content: [String: Any]?) -> [[String: Any]] {
        (content?["parts"] as? [[String: Any]] ?? []).flatMap(fileReferenceObjects(from:))
    }

    private static func fileReferenceObjects(from object: [String: Any]) -> [[String: Any]] {
        var values = [[String: Any]]()
        if let fileData = object["fileData"] as? [String: Any] ?? object["file_data"] as? [String: Any] {
            values.append(fileData)
        }
        if let uri = stringValue(object["fileUri"]) ?? stringValue(object["file_uri"]) ?? stringValue(object["uri"]) {
            values.append([
                "fileUri": uri,
                "mimeType": stringValue(object["mimeType"]) ?? stringValue(object["mime_type"]) ?? "",
            ])
        }
        return values
    }

    private static func extractedGeminiArtifacts(fromGenerateContentResponse response: [String: Any]) -> [[String: Any]] {
        (response["candidates"] as? [[String: Any]] ?? []).flatMap { candidate in
            extractedGeminiArtifacts(fromContent: candidate["content"] as? [String: Any])
        }
    }

    private static func extractedGeminiArtifacts(fromInteraction interaction: [String: Any]) -> [[String: Any]] {
        interactionOutputs(from: interaction).flatMap { output in
            extractedGeminiArtifacts(fromContent: output["content"] as? [String: Any])
                + artifactObjects(from: output)
        }
    }

    private static func extractedGeminiArtifacts(fromContent content: [String: Any]?) -> [[String: Any]] {
        (content?["parts"] as? [[String: Any]] ?? []).flatMap(artifactObjects(from:))
    }

    private static func artifactObjects(from object: [String: Any]) -> [[String: Any]] {
        var values = [[String: Any]]()
        if let inlineData = object["inlineData"] as? [String: Any] ?? object["inline_data"] as? [String: Any] {
            values.append([
                "type": "inline_data",
                "mimeType": stringValue(inlineData["mimeType"]) ?? stringValue(inlineData["mime_type"]) ?? "",
                "byte_hint": stringValue(inlineData["data"])?.count ?? 0,
            ])
        }
        for key in ["generatedFiles", "generated_files", "artifacts"] {
            if let value = object[key] as? [[String: Any]] {
                values.append(contentsOf: value)
            }
        }
        return values
    }

    private static func interactionOutputs(from interaction: [String: Any]) -> [[String: Any]] {
        var outputs = interaction["outputs"] as? [[String: Any]] ?? []
        if let output = interaction["output"] as? [String: Any] {
            outputs.append(output)
        }
        if let steps = interaction["steps"] as? [[String: Any]] {
            outputs.append(contentsOf: steps)
        }
        return outputs
    }

    private static func sourceCitations(from sources: [[String: Any]], provider: String) -> [WebSearchCitation] {
        sources.compactMap { source in
            let web = source["web"] as? [String: Any]
            let url = stringValue(source["url"])
                ?? stringValue(source["uri"])
                ?? stringValue(web?["url"])
                ?? stringValue(web?["uri"])
            guard let url, !url.isEmpty else { return nil }
            let title = stringValue(source["title"])
                ?? stringValue(web?["title"])
                ?? url
            return WebSearchCitation(title: title, url: url, source: provider)
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        let value = intValue(value)
        return value > 0 ? value : nil
    }

    private static func jsonValue(from value: Any?) -> JSONValue? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public mutating func clearOpenAITools() {
        openAIToolIDs.removeAll(keepingCapacity: true)
        openAIToolNames.removeAll(keepingCapacity: true)
        openAIArguments.removeAll(keepingCapacity: true)
    }

    public mutating func recordRequestMetadata(providerKind: CloudProviderKind, serverRequestID: String?, clientRequestID: String?) {
        switch providerKind {
        case .anthropic:
            if let serverRequestID, !serverRequestID.isEmpty {
                anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicRequestID] = serverRequestID
            }
        case .gemini:
            if let serverRequestID, !serverRequestID.isEmpty {
                geminiProviderMetadata[CloudProviderMetadataKeys.geminiRequestID] = serverRequestID
                geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiRequestID] = serverRequestID
            }
        case .openAI, .openAICompatible, .openRouter, .voyageAI, .custom:
            recordOpenAIRequestMetadata(serverRequestID: serverRequestID, clientRequestID: clientRequestID)
        }
    }

    public mutating func recordOpenAIRequestMetadata(serverRequestID: String?, clientRequestID: String?) {
        if let serverRequestID, !serverRequestID.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIRequestID] = serverRequestID
        }
        if let clientRequestID, !clientRequestID.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIClientRequestID] = clientRequestID
        }
    }

    public mutating func recordOpenAIChatCompletionChunk(_ chunk: [String: Any]) {
        if let completionID = chunk["id"] as? String, !completionID.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIChatCompletionID] = completionID
        }
        if let model = chunk["model"] as? String, !model.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIModel] = model
        }
        if let fingerprint = chunk["system_fingerprint"] as? String, !fingerprint.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAISystemFingerprint] = fingerprint
        }
    }

    public mutating func recordOpenRouterChatCompletionChunk(_ chunk: [String: Any]) {
        if let generationID = Self.nonEmptyString(chunk["id"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterGenerationID] = generationID
        }
        if let provider = Self.nonEmptyString(chunk["provider"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterProvider] = provider
        }
        if let model = Self.nonEmptyString(chunk["model"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterResolvedModel] = model
        }
        if let serviceTier = Self.nonEmptyString(chunk["service_tier"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterServiceTier] = serviceTier
        }
        if let choice = (chunk["choices"] as? [[String: Any]])?.first,
           let nativeFinishReason = Self.nonEmptyString(choice["native_finish_reason"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterNativeFinishReason] = nativeFinishReason
        }

        if let usage = chunk["usage"] as? [String: Any] {
            Self.recordJSON(
                Self.privacyMinimizedOpenRouterUsage(usage),
                key: CloudProviderMetadataKeys.openRouterUsageJSON,
                into: &openAIProviderMetadata
            )
            Self.recordInteger(usage["prompt_tokens"], key: CloudProviderMetadataKeys.openRouterPromptTokens, into: &openAIProviderMetadata)
            Self.recordInteger(usage["completion_tokens"], key: CloudProviderMetadataKeys.openRouterCompletionTokens, into: &openAIProviderMetadata)
            Self.recordInteger(usage["total_tokens"], key: CloudProviderMetadataKeys.openRouterTotalTokens, into: &openAIProviderMetadata)
            Self.recordNumber(usage["cost"], key: CloudProviderMetadataKeys.openRouterCostCredits, into: &openAIProviderMetadata)
            if let costDetails = usage["cost_details"] as? [String: Any] {
                Self.recordNumber(
                    costDetails["upstream_inference_cost"],
                    key: CloudProviderMetadataKeys.openRouterUpstreamInferenceCost,
                    into: &openAIProviderMetadata
                )
            }
            if let isBYOK = usage["is_byok"] as? Bool {
                openAIProviderMetadata[CloudProviderMetadataKeys.openRouterIsBYOK] = String(isBYOK)
            }
        }

        guard let routerMetadata = chunk["openrouter_metadata"] as? [String: Any] else { return }
        Self.recordJSON(
            Self.privacyMinimizedOpenRouterMetadata(routerMetadata),
            key: CloudProviderMetadataKeys.openRouterMetadataJSON,
            into: &openAIProviderMetadata
        )
        if let requestedModel = Self.nonEmptyString(routerMetadata["requested"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterRequestedModel] = requestedModel
        }
        if let strategy = Self.nonEmptyString(routerMetadata["strategy"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterStrategy] = strategy
        }
        if let region = Self.nonEmptyString(routerMetadata["region"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterRegion] = region
        }
        if let summary = Self.nonEmptyString(routerMetadata["summary"]) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterSummary] = summary
        }
        Self.recordInteger(routerMetadata["attempt"], key: CloudProviderMetadataKeys.openRouterAttempt, into: &openAIProviderMetadata)
        if let isBYOK = routerMetadata["is_byok"] as? Bool {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterIsBYOK] = String(isBYOK)
        }
        if let attempts = routerMetadata["attempts"] as? [[String: Any]] {
            openAIProviderMetadata[CloudProviderMetadataKeys.openRouterAttemptCount] = String(attempts.count)
            let safeAttempts = attempts.compactMap(Self.privacyMinimizedOpenRouterAttempt)
            if !safeAttempts.isEmpty {
                Self.recordJSON(
                    safeAttempts,
                    key: CloudProviderMetadataKeys.openRouterAttemptsJSON,
                    into: &openAIProviderMetadata
                )
            }
        }
        if let endpoints = routerMetadata["endpoints"] as? [String: Any],
           let available = endpoints["available"] as? [[String: Any]],
           let selected = available.first(where: { $0["selected"] as? Bool == true }) {
            if let provider = Self.nonEmptyString(selected["provider"]) {
                openAIProviderMetadata[CloudProviderMetadataKeys.openRouterSelectedProvider] = provider
            }
            if let model = Self.nonEmptyString(selected["model"]) {
                openAIProviderMetadata[CloudProviderMetadataKeys.openRouterSelectedModel] = model
            }
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(512))
    }

    private static func recordInteger(_ value: Any?, key: String, into metadata: inout [String: String]) {
        guard let number = value as? NSNumber else { return }
        metadata[key] = String(number.intValue)
    }

    private static func recordNumber(_ value: Any?, key: String, into metadata: inout [String: String]) {
        guard let number = value as? NSNumber, number.doubleValue.isFinite, number.doubleValue >= 0 else { return }
        metadata[key] = number.stringValue
    }

    private static func recordJSON(_ value: Any, key: String, into metadata: inout [String: String]) {
        guard let json = CloudProviderStreamParser.jsonString(from: value) else { return }
        metadata[key] = json
    }

    private static func privacyMinimizedOpenRouterMetadata(_ metadata: [String: Any]) -> [String: Any] {
        var safe = [String: Any]()
        for key in ["requested", "strategy", "region", "summary"] {
            if let value = nonEmptyString(metadata[key]) {
                safe[key] = value
            }
        }
        if let attempt = metadata["attempt"] as? NSNumber {
            safe["attempt"] = attempt
        }
        if let isBYOK = metadata["is_byok"] as? Bool {
            safe["is_byok"] = isBYOK
        }
        if let endpoints = metadata["endpoints"] as? [String: Any],
           let available = endpoints["available"] as? [[String: Any]] {
            var safeEndpoints: [String: Any] = [
                "available": available.prefix(32).map { endpoint in
                    var safeEndpoint = [String: Any]()
                    for key in ["provider", "model"] {
                        if let value = nonEmptyString(endpoint[key]) {
                            safeEndpoint[key] = value
                        }
                    }
                    if let selected = endpoint["selected"] as? Bool {
                        safeEndpoint["selected"] = selected
                    }
                    return safeEndpoint
                }
            ]
            if let total = endpoints["total"] as? NSNumber {
                safeEndpoints["total"] = total
            }
            safe["endpoints"] = safeEndpoints
        }
        if let attempts = metadata["attempts"] as? [[String: Any]] {
            safe["attempts"] = attempts.prefix(32).compactMap(privacyMinimizedOpenRouterAttempt)
        }
        return safe
    }

    private static func privacyMinimizedOpenRouterAttempt(_ attempt: [String: Any]) -> [String: Any]? {
        var safe = [String: Any]()
        for key in ["provider", "model"] {
            if let value = nonEmptyString(attempt[key]) {
                safe[key] = value
            }
        }
        if let status = attempt["status"] as? NSNumber {
            safe["status"] = status
        }
        return safe.isEmpty ? nil : safe
    }

    private static func privacyMinimizedOpenRouterUsage(_ usage: [String: Any]) -> [String: Any] {
        var safe = [String: Any]()
        for key in ["prompt_tokens", "completion_tokens", "total_tokens", "cost"] {
            if let value = usage[key] as? NSNumber {
                safe[key] = value
            }
        }
        if let isBYOK = usage["is_byok"] as? Bool {
            safe["is_byok"] = isBYOK
        }
        Self.copyNumericFields(
            ["cached_tokens", "cache_write_tokens", "audio_tokens", "video_tokens"],
            from: usage["prompt_tokens_details"],
            to: "prompt_tokens_details",
            in: &safe
        )
        Self.copyNumericFields(
            ["reasoning_tokens", "audio_tokens", "image_tokens"],
            from: usage["completion_tokens_details"],
            to: "completion_tokens_details",
            in: &safe
        )
        Self.copyNumericFields(
            ["upstream_inference_cost", "upstream_inference_prompt_cost", "upstream_inference_completions_cost"],
            from: usage["cost_details"],
            to: "cost_details",
            in: &safe
        )
        Self.copyNumericFields(
            ["web_search_requests"],
            from: usage["server_tool_use"],
            to: "server_tool_use",
            in: &safe
        )
        return safe
    }

    private static func copyNumericFields(
        _ keys: [String],
        from value: Any?,
        to destinationKey: String,
        in destination: inout [String: Any]
    ) {
        guard let source = value as? [String: Any] else { return }
        var safe = [String: Any]()
        for key in keys where source[key] is NSNumber {
            safe[key] = source[key]
        }
        if !safe.isEmpty {
            destination[destinationKey] = safe
        }
    }

    public mutating func recordOpenAIResponseEvent(_ event: [String: Any], eventType: String) {
        if let item = event["item"] as? [String: Any] {
            recordOpenAIHostedToolCalls([Self.openAIHostedToolCallSummary(from: item)].compactMap { $0 })
            recordOpenAIArtifacts(Self.openAIArtifacts(from: ["output": [item]]))
        }
        if let summary = Self.openAIHostedToolCallSummary(fromStreamingEvent: event, eventType: eventType) {
            recordOpenAIHostedToolCalls([summary])
        }
        recordOpenAIArtifacts(Self.openAIArtifacts(fromStreamingEvent: event, eventType: eventType))
    }

    public mutating func recordOpenAIResponse(_ response: [String: Any]) {
        if let responseID = response["id"] as? String, !responseID.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIResponseID] = responseID
        }
        if let status = response["status"] as? String, !status.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIResponseStatus] = status
        }
        if let previousResponseID = response["previous_response_id"] as? String, !previousResponseID.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIResponsePreviousID] = previousResponseID
        }
        if let serviceTier = response["service_tier"] as? String, !serviceTier.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIResponseServiceTier] = serviceTier
        }
        if let stored = response["store"] as? Bool {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIResponseStored] = String(stored)
        }
        if let incompleteDetails = response["incomplete_details"] as? [String: Any],
           let reason = incompleteDetails["reason"] as? String,
           !reason.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIResponseIncompleteReason] = reason
        }
        if let usage = response["usage"] as? [String: Any] {
            if let reasoningTokens = Self.openAIUsageDetailTokenCount(usage, detailKeys: ["output_tokens_details", "completion_tokens_details"], tokenKey: "reasoning_tokens") {
                openAIProviderMetadata[CloudProviderMetadataKeys.openAIReasoningTokens] = String(reasoningTokens)
            }
            if let cachedInputTokens = Self.openAIUsageDetailTokenCount(usage, detailKeys: ["input_tokens_details", "prompt_tokens_details"], tokenKey: "cached_tokens") {
                openAIProviderMetadata[CloudProviderMetadataKeys.openAICachedInputTokens] = String(cachedInputTokens)
            }
        }
        if let metadata = response["metadata"] as? [String: Any],
           let promptCacheKey = metadata["pines_prompt_cache_key"] as? String,
           !promptCacheKey.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIPromptCacheKey] = promptCacheKey
        }
        if let requestID = response["_request_id"] as? String, !requestID.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIRequestID] = requestID
        }
        if let output = response["output"] as? [[String: Any]],
           JSONSerialization.isValidJSONObject(output),
           let data = try? JSONSerialization.data(withJSONObject: output),
           let json = String(data: data, encoding: .utf8),
           !json.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIOutputItemsJSON] = json
        }
        Self.recordSearchCitations(Self.openAIWebSearchCitations(from: response), into: &openAIProviderMetadata)
        Self.recordSearchQueries(Self.openAIWebSearchQueries(from: response), into: &openAIProviderMetadata)
        recordOpenAIHostedToolCalls(Self.openAIHostedToolCalls(from: response))
        recordOpenAIFileSearchResults(Self.openAIFileSearchResults(from: response))
        recordOpenAIArtifacts(Self.openAIArtifacts(from: response))
    }

    private static func openAIUsageDetailTokenCount(_ usage: [String: Any], detailKeys: [String], tokenKey: String) -> Int? {
        for detailKey in detailKeys {
            if let details = usage[detailKey] as? [String: Any] {
                let value = intValue(details[tokenKey])
                if value > 0 {
                    return value
                }
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return 0
    }

    public mutating func recordOpenAIHostedToolCalls(_ calls: [[String: Any]]) {
        openAIHostedToolCalls = Self.appendingJSONObjectSummaries(calls, to: openAIHostedToolCalls)
        if let json = Self.jsonString(fromJSONObjectSummaries: openAIHostedToolCalls) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIHostedToolCallsJSON] = json
        }
    }

    public mutating func recordOpenAIFileSearchResults(_ results: [[String: Any]]) {
        openAIFileSearchResults = Self.appendingJSONObjectSummaries(results, to: openAIFileSearchResults)
        if let json = Self.jsonString(fromJSONObjectSummaries: openAIFileSearchResults) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIFileSearchResultsJSON] = json
        }
    }

    public mutating func recordOpenAIArtifacts(_ artifacts: [[String: Any]]) {
        openAIArtifacts = Self.appendingJSONObjectSummaries(artifacts, to: openAIArtifacts)
        if let json = Self.jsonString(fromJSONObjectSummaries: openAIArtifacts) {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIArtifactsJSON] = json
        }
    }

    private static func appendingJSONObjectSummaries(_ values: [[String: Any]], to storage: [[String: Any]]) -> [[String: Any]] {
        guard !values.isEmpty else { return storage }
        return Array((storage + values).prefix(64))
    }

    private static func jsonString(fromJSONObjectSummaries summaries: [[String: Any]]) -> String? {
        guard JSONSerialization.isValidJSONObject(summaries),
              let data = try? JSONSerialization.data(withJSONObject: summaries)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public mutating func markOpenAIToolCallCompleted(_ toolCall: ToolCallDelta) -> Bool {
        completedOpenAIToolCallIDs.insert(toolCall.id).inserted
    }

    public mutating func clearAnthropicTool() {
        anthropicToolIndex = nil
        anthropicToolID = nil
        anthropicToolName = nil
        anthropicArguments.removeAll(keepingCapacity: true)
    }

    public mutating func clearAnthropicServerTool() {
        anthropicServerToolIndex = nil
        anthropicServerToolID = nil
        anthropicServerToolName = nil
        anthropicServerToolArguments.removeAll(keepingCapacity: true)
    }

    public mutating func recordAnthropicMessage(_ message: [String: Any]) {
        if let messageID = message["id"] as? String, !messageID.isEmpty {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicMessageID] = messageID
        }
        if let model = message["model"] as? String, !model.isEmpty {
            anthropicProviderMetadata["anthropic.model"] = model
        }
        if let usage = message["usage"] as? [String: Any] {
            recordAnthropicUsage(usage)
        }
        Self.recordSearchCitations(CloudProviderStreamState.anthropicWebSearchCitations(from: message), into: &anthropicProviderMetadata)
        recordAnthropicCitations(from: Self.anthropicProviderCitations(from: message))
        recordAnthropicArtifacts(Self.anthropicArtifacts(from: message))
        recordAnthropicFileReferences(Self.anthropicFileReferences(from: message))
    }

    public mutating func recordAnthropicSearchBlock(_ block: [String: Any]) {
        Self.recordSearchCitations(Self.anthropicWebSearchCitations(from: block), into: &anthropicProviderMetadata)
    }

    public mutating func recordAnthropicContentBlock(_ block: [String: Any]) {
        recordAnthropicSearchBlock(block)
        recordAnthropicCitations(from: Self.anthropicProviderCitations(from: block))
        recordAnthropicArtifacts(Self.anthropicArtifacts(from: block))
        recordAnthropicFileReferences(Self.anthropicFileReferences(from: block))
    }

    public mutating func recordAnthropicUsage(_ usage: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(usage),
              let data = try? JSONSerialization.data(withJSONObject: usage),
              let json = String(data: data, encoding: .utf8)
        else { return }
        anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicUsageJSON] = json

        var cacheUsage = [String: Any]()
        for key in [
            "cache_creation_input_tokens",
            "cache_read_input_tokens",
            "cache_creation",
            "cache_read",
            "input_tokens_details",
        ] where usage[key] != nil {
            cacheUsage[key] = usage[key]
        }
        if !cacheUsage.isEmpty,
           JSONSerialization.isValidJSONObject(cacheUsage),
           let data = try? JSONSerialization.data(withJSONObject: cacheUsage),
           let json = String(data: data, encoding: .utf8) {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicCacheUsageJSON] = json
        }
        let cacheReadTokens = Self.intValue(usage["cache_read_input_tokens"])
        if cacheReadTokens > 0 {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicCacheReadInputTokens] = String(cacheReadTokens)
        }
        let cacheCreationTokens = Self.intValue(usage["cache_creation_input_tokens"])
        if cacheCreationTokens > 0 {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicCacheCreationInputTokens] = String(cacheCreationTokens)
        }
    }

    public mutating func recordAnthropicHostedToolBlock(_ block: [String: Any], status: String) {
        guard let summary = Self.anthropicHostedToolSummary(from: block, status: status) else { return }
        anthropicHostedToolCalls = Self.appendingJSONObjectSummaries([summary], to: anthropicHostedToolCalls)
        if let json = Self.jsonString(fromJSONObjectSummaries: anthropicHostedToolCalls) {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicHostedToolCallsJSON] = json
        }
    }

    public mutating func recordAnthropicCompletedServerTool() {
        var block: [String: Any] = [
            "type": "server_tool_use",
            "status": "completed",
        ]
        if let id = anthropicServerToolID, !id.isEmpty {
            block["id"] = id
        }
        if let name = anthropicServerToolName, !name.isEmpty {
            block["name"] = name
        }
        if !anthropicServerToolArguments.isEmpty {
            if let data = anthropicServerToolArguments.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                block["input"] = object
            } else {
                block["input"] = anthropicServerToolArguments
            }
        }
        recordAnthropicHostedToolBlock(block, status: "completed")
    }

    public mutating func recordAnthropicArtifacts(_ values: [[String: Any]]) {
        anthropicArtifacts = Self.appendingJSONObjectSummaries(values, to: anthropicArtifacts)
        if let json = Self.jsonString(fromJSONObjectSummaries: anthropicArtifacts) {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicArtifactsJSON] = json
        }
    }

    public mutating func recordAnthropicFileReferences(_ values: [[String: Any]]) {
        anthropicFileReferences = Self.appendingJSONObjectSummaries(values, to: anthropicFileReferences)
        if let json = Self.jsonString(fromJSONObjectSummaries: anthropicFileReferences) {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicFileReferencesJSON] = json
        }
    }

    public mutating func recordAnthropicCitations(from citations: [ProviderCitation]) {
        guard !citations.isEmpty else { return }
        var combined = Self.existingProviderCitations(from: anthropicProviderMetadata)
        for citation in citations where !combined.contains(where: { $0.id == citation.id }) {
            combined.append(citation)
        }
        guard let data = try? JSONEncoder().encode(Array(combined.prefix(64))) else { return }
        anthropicProviderMetadata[CloudProviderMetadataKeys.providerCitationsJSON] = String(decoding: data, as: UTF8.self)
    }

    public mutating func recordAnthropicCitationObjects(_ citations: [[String: Any]]) {
        recordAnthropicCitations(from: Self.anthropicProviderCitations(fromCitationValue: citations))
    }

    public mutating func recordAnthropicError(_ error: [String: Any]?) {
        guard let error else { return }
        if let type = error["type"] as? String, !type.isEmpty {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicErrorType] = type
        }
        if let json = CloudProviderStreamParser.jsonString(from: error) {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicErrorJSON] = json
        }
    }

    public mutating func recordAnthropicThinkingBlock() {
        var block: [String: Any] = [
            "type": "thinking",
            "thinking": anthropicThinkingText,
        ]
        if let signature = anthropicThinkingSignature, !signature.isEmpty {
            block["signature"] = signature
        }
        anthropicThinkingBlocks.append(block)
        if let json = CloudProviderStreamParser.jsonString(from: anthropicThinkingBlocks) {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicThinkingContentJSON] = json
        }
        anthropicThinkingIndex = nil
        anthropicThinkingText.removeAll(keepingCapacity: true)
        anthropicThinkingSignature = nil
    }

    public mutating func recordGeminiResponse(_ response: [String: Any]) {
        if let responseID = response["responseId"] as? String, !responseID.isEmpty {
            geminiProviderMetadata[CloudProviderMetadataKeys.geminiResponseID] = responseID
        }
        if let modelVersion = response["modelVersion"] as? String, !modelVersion.isEmpty {
            geminiProviderMetadata[CloudProviderMetadataKeys.geminiModelVersion] = modelVersion
        }
        Self.recordGeminiCacheUsage(Self.extractedGeminiCacheUsage(from: response["usageMetadata"] as? [String: Any]), into: &geminiProviderMetadata)
        Self.recordSearchCitations(Self.geminiWebSearchCitations(from: response), into: &geminiProviderMetadata)
        Self.recordSearchQueries(Self.geminiWebSearchQueries(from: response), into: &geminiProviderMetadata)
        Self.recordSearchSuggestionsHTML(Self.geminiSearchSuggestionsHTML(from: response), into: &geminiProviderMetadata)
        recordGeminiCodeExecution(Self.extractedGeminiCodeExecution(fromGenerateContentResponse: response), interactionsAPI: false)
        recordGeminiURLContext(Self.extractedGeminiURLContext(fromGenerateContentResponse: response), interactionsAPI: false)
        recordGeminiFileReferences(Self.extractedGeminiFileReferences(fromGenerateContentResponse: response), interactionsAPI: false)
        recordGeminiArtifacts(Self.extractedGeminiArtifacts(fromGenerateContentResponse: response), interactionsAPI: false)
    }

    public mutating func recordGeminiInteraction(_ interaction: [String: Any]) {
        if let interactionID = interaction["id"] as? String, !interactionID.isEmpty {
            geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiInteractionID] = interactionID
        }
        if let model = interaction["model"] as? String, !model.isEmpty {
            geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiModelVersion] = model
        }
        let usage = interaction["usage"] as? [String: Any] ?? interaction["usageMetadata"] as? [String: Any]
        Self.recordGeminiCacheUsage(Self.extractedGeminiCacheUsage(from: usage), into: &geminiInteractionProviderMetadata)
        Self.recordSearchCitations(Self.geminiInteractionWebSearchCitations(from: interaction), into: &geminiInteractionProviderMetadata)
        Self.recordSearchQueries(Self.geminiInteractionWebSearchQueries(from: interaction), into: &geminiInteractionProviderMetadata)
        Self.recordSearchSuggestionsHTML(Self.geminiInteractionSearchSuggestionsHTML(from: interaction), into: &geminiInteractionProviderMetadata)
        recordGeminiCodeExecution(Self.extractedGeminiCodeExecution(fromInteraction: interaction), interactionsAPI: true)
        recordGeminiURLContext(Self.extractedGeminiURLContext(fromInteraction: interaction), interactionsAPI: true)
        recordGeminiFileReferences(Self.extractedGeminiFileReferences(fromInteraction: interaction), interactionsAPI: true)
        recordGeminiArtifacts(Self.extractedGeminiArtifacts(fromInteraction: interaction), interactionsAPI: true)
    }

    public mutating func recordGeminiCodeExecution(_ values: [[String: Any]], interactionsAPI: Bool) {
        if interactionsAPI {
            geminiInteractionCodeExecution = Self.appendingJSONObjectSummaries(values, to: geminiInteractionCodeExecution)
            if let json = Self.jsonString(fromJSONObjectSummaries: geminiInteractionCodeExecution) {
                geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiCodeExecutionJSON] = json
            }
        } else {
            geminiCodeExecution = Self.appendingJSONObjectSummaries(values, to: geminiCodeExecution)
            if let json = Self.jsonString(fromJSONObjectSummaries: geminiCodeExecution) {
                geminiProviderMetadata[CloudProviderMetadataKeys.geminiCodeExecutionJSON] = json
            }
        }
    }

    public mutating func recordGeminiURLContext(_ values: [[String: Any]], interactionsAPI: Bool) {
        if interactionsAPI {
            geminiInteractionURLContext = Self.appendingJSONObjectSummaries(values, to: geminiInteractionURLContext)
            if let json = Self.jsonString(fromJSONObjectSummaries: geminiInteractionURLContext) {
                geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiURLContextJSON] = json
            }
        } else {
            geminiURLContext = Self.appendingJSONObjectSummaries(values, to: geminiURLContext)
            if let json = Self.jsonString(fromJSONObjectSummaries: geminiURLContext) {
                geminiProviderMetadata[CloudProviderMetadataKeys.geminiURLContextJSON] = json
            }
        }
    }

    public mutating func recordGeminiFileReferences(_ values: [[String: Any]], interactionsAPI: Bool) {
        if interactionsAPI {
            geminiInteractionFileReferences = Self.appendingJSONObjectSummaries(values, to: geminiInteractionFileReferences)
            if let json = Self.jsonString(fromJSONObjectSummaries: geminiInteractionFileReferences) {
                geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiFileReferencesJSON] = json
            }
        } else {
            geminiFileReferences = Self.appendingJSONObjectSummaries(values, to: geminiFileReferences)
            if let json = Self.jsonString(fromJSONObjectSummaries: geminiFileReferences) {
                geminiProviderMetadata[CloudProviderMetadataKeys.geminiFileReferencesJSON] = json
            }
        }
    }

    public mutating func recordGeminiArtifacts(_ values: [[String: Any]], interactionsAPI: Bool) {
        if interactionsAPI {
            geminiInteractionArtifacts = Self.appendingJSONObjectSummaries(values, to: geminiInteractionArtifacts)
            if let json = Self.jsonString(fromJSONObjectSummaries: geminiInteractionArtifacts) {
                geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiArtifactsJSON] = json
            }
        } else {
            geminiArtifacts = Self.appendingJSONObjectSummaries(values, to: geminiArtifacts)
            if let json = Self.jsonString(fromJSONObjectSummaries: geminiArtifacts) {
                geminiProviderMetadata[CloudProviderMetadataKeys.geminiArtifactsJSON] = json
            }
        }
    }

    public mutating func recordGeminiPartMetadata(_ part: [String: Any], interactionsAPI: Bool) {
        var codeExecution = [[String: Any]]()
        if let executableCode = part["executableCode"] as? [String: Any] {
            codeExecution.append(["type": "executable_code", "value": executableCode])
        }
        if let result = part["codeExecutionResult"] as? [String: Any] {
            codeExecution.append(["type": "code_execution_result", "value": result])
        }
        recordGeminiCodeExecution(codeExecution, interactionsAPI: interactionsAPI)

        if let fileData = part["fileData"] as? [String: Any] {
            recordGeminiFileReferences([fileData], interactionsAPI: interactionsAPI)
        }

        if let inlineData = part["inlineData"] as? [String: Any] {
            recordGeminiArtifacts([[
                "type": "inline_data",
                "mimeType": Self.stringValue(inlineData["mimeType"]) ?? "",
                "byte_hint": Self.stringValue(inlineData["data"])?.count ?? 0,
            ]], interactionsAPI: interactionsAPI)
        }
    }

    private static func recordGeminiCacheUsage(_ value: [String: Any]?, into metadata: inout [String: String]) {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8)
        else { return }
        metadata[CloudProviderMetadataKeys.geminiCacheUsageJSON] = json
    }

    public mutating func recordGeminiModelContent(_ content: [String: Any]) {
        guard let parts = content["parts"] as? [[String: Any]], !parts.isEmpty else { return }
        var existingParts = (geminiModelContent?["parts"] as? [[String: Any]]) ?? []
        for part in parts {
            if let text = part["text"] as? String,
               part["thought"] as? Bool != true,
               !text.isEmpty {
                existingParts.append(["text": text])
                continue
            }
            if let functionCall = part["functionCall"] as? [String: Any] {
                existingParts.append(["functionCall": functionCall])
                continue
            }
            if part["thoughtSignature"] != nil || part["thought"] as? Bool == true {
                existingParts.append(part)
            }
        }
        guard !existingParts.isEmpty else { return }
        geminiModelContent = [
            "role": "model",
            "parts": existingParts,
        ]
        if let json = CloudProviderStreamParser.jsonString(from: geminiModelContent) {
            geminiProviderMetadata[CloudProviderMetadataKeys.geminiModelContentJSON] = json
        }
    }

    public mutating func markGeminiToolCallCompleted(_ toolCall: ToolCallDelta) -> Bool {
        geminiCompletedToolCallIDs.insert(toolCall.id).inserted
    }

    public mutating func markGeminiInteractionToolCallCompleted(_ toolCall: ToolCallDelta) -> Bool {
        geminiInteractionCompletedToolCallIDs.insert(toolCall.id).inserted
    }
}
