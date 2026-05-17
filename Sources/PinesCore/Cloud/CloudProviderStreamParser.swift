import Foundation

public enum CloudProviderMetadataKeys {
    public static let openAIResponseID = "openai.response_id"
    public static let openAIChatCompletionID = "openai.chat_completion_id"
    public static let openAIRequestID = "openai.request_id"
    public static let openAIClientRequestID = "openai.client_request_id"
    public static let openAIModel = "openai.model"
    public static let openAISystemFingerprint = "openai.system_fingerprint"
    public static let openAIOutputItemsJSON = "openai.output_items_json"
    public static let anthropicMessageID = "anthropic.message_id"
    public static let anthropicRequestID = "anthropic.request_id"
    public static let anthropicThinkingContentJSON = "anthropic.thinking_content_json"
    public static let geminiResponseID = "gemini.response_id"
    public static let geminiModelVersion = "gemini.model_version"
    public static let geminiRequestID = "gemini.request_id"
    public static let geminiModelContentJSON = "gemini.model_content_json"
    public static let geminiInteractionID = "gemini.interaction_id"
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
            return extractChatCompletionEvents(json)
        }
    }

    public func fallbackFinish(format: CloudProviderStreamFormat, providerKind: CloudProviderKind, modelID: ModelID, usesOfficialOpenAIReasoningChat: Bool) -> InferenceFinish {
        switch format {
        case .openAIResponses:
            return InferenceFinish(
                reason: .stop,
                message: Self.openAIResponsesEmptyOutputMessage(response: nil, eventTypes: state.openAIResponsesEventTypes),
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
                if let text = block["text"] as? String, !text.isEmpty {
                    events.append(.token(TokenDelta(kind: .token, text: text, tokenCount: 1)))
                }
            default:
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
                state.anthropicArguments += partial
            }
            if delta["type"] as? String == "thinking_delta",
               let thinking = delta["thinking"] as? String {
                state.anthropicThinkingText += thinking
            }
            if delta["type"] as? String == "signature_delta",
               let signature = delta["signature"] as? String {
                state.anthropicThinkingSignature = signature
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
           index == state.anthropicThinkingIndex {
            state.recordAnthropicThinkingBlock()
        }

        if type == "message_delta" {
            if let usage = json["usage"] as? [String: Any],
               let metrics = Self.anthropicMetrics(from: usage) {
                events.append(.metrics(metrics))
            }
            if let delta = json["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String {
                finish = Self.anthropicFinish(from: stopReason, metadata: state.anthropicProviderMetadata)
            }
        }

        if type == "error" {
            let error = json["error"] as? [String: Any]
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

    private mutating func extractChatCompletionEvents(_ json: [String: Any]) -> CloudProviderStreamParseOutput {
        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        state.recordOpenAIChatCompletionChunk(json)

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
        }
        if let response = json["response"] as? [String: Any] {
            state.recordOpenAIResponse(response)
        }

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?

        switch type {
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
               let text = Self.textValue(from: json["text"]),
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
            let finishReason: InferenceFinishReason = events.contains { event in
                if case .toolCall = event { return true }
                return false
            } ? .toolCall : .stop
            finish = InferenceFinish(
                reason: finishReason,
                message: finishReason == .stop && events.isEmpty && !state.openAIResponsesTextEmitted
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
        guard let content = item["content"] as? [[String: Any]] else { return nil }
        let text = content.compactMap(openAIResponsesOutputText(fromContentPart:)).joined()
        return text.isEmpty ? nil : text
    }

    private static func openAIResponsesOutputText(fromContentPart part: [String: Any]) -> String? {
        let type = part["type"] as? String
        guard type == nil || type == "output_text" || type == "text" || type == "refusal" else {
            return nil
        }
        return textValue(from: part["text"]) ?? textValue(from: part["refusal"])
    }

    private static func textValue(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let object = value as? [String: Any] {
            return (object["text"] as? String)
                ?? (object["value"] as? String)
                ?? (object["content"] as? String)
                ?? (object["refusal"] as? String)
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
        let outputCount = (response?["output"] as? [[String: Any]])?.count
        var details = [String]()
        if let status {
            details.append("status: \(status)")
        }
        if let outputCount {
            details.append("output items: \(outputCount)")
        }
        if !eventTypes.isEmpty {
            details.append("events: \(eventTypes.sorted().joined(separator: ", "))")
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))."
        return "OpenAI completed the Responses stream without visible output text\(suffix)"
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

    public var anthropicToolIndex: Int?
    public var anthropicToolID: String?
    public var anthropicToolName: String?
    public var anthropicArguments = ""
    public var anthropicProviderMetadata = [String: String]()
    public var anthropicThinkingIndex: Int?
    public var anthropicThinkingText = ""
    public var anthropicThinkingSignature: String?
    public var anthropicThinkingBlocks = [[String: Any]]()

    public var geminiProviderMetadata = [String: String]()
    public var geminiCompletedToolCallIDs = Set<String>()
    public var geminiModelContent: [String: Any]?

    public var geminiInteractionProviderMetadata = [String: String]()
    public var geminiInteractionToolIDs: [Int: String] = [:]
    public var geminiInteractionToolNames: [Int: String] = [:]
    public var geminiInteractionArguments: [Int: String] = [:]
    public var geminiInteractionCompletedToolCallIDs = Set<String>()

    public init() {}

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

    public mutating func recordOpenAIResponse(_ response: [String: Any]) {
        if let responseID = response["id"] as? String, !responseID.isEmpty {
            openAIProviderMetadata[CloudProviderMetadataKeys.openAIResponseID] = responseID
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

    public mutating func recordAnthropicMessage(_ message: [String: Any]) {
        if let messageID = message["id"] as? String, !messageID.isEmpty {
            anthropicProviderMetadata[CloudProviderMetadataKeys.anthropicMessageID] = messageID
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
    }

    public mutating func recordGeminiInteraction(_ interaction: [String: Any]) {
        if let interactionID = interaction["id"] as? String, !interactionID.isEmpty {
            geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiInteractionID] = interactionID
        }
        if let model = interaction["model"] as? String, !model.isEmpty {
            geminiInteractionProviderMetadata[CloudProviderMetadataKeys.geminiModelVersion] = model
        }
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
