import Foundation
import PinesCore
import Testing

@Suite("Core contracts")
struct CoreContractTests {
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

        #expect(decision.destination == .denied(reason: .unsupportedCapability("No local model satisfies this request.")))
    }

    @Test
    func executionRouterPrefersMatchingLocalProvider() {
        let localID = ProviderID(rawValue: "local")
        let decision = ExecutionRouter().routeChat(
            mode: .preferLocal,
            local: (
                localID,
                ProviderCapabilities(local: true, textGeneration: true, vision: true, imageInputs: true, toolCalling: true)
            ),
            cloud: (
                ProviderID(rawValue: "cloud"),
                ProviderCapabilities(local: false, textGeneration: true, vision: true, imageInputs: true, toolCalling: true)
            ),
            requiredInputs: .init(requiresImages: true),
            requiresTools: true
        )

        #expect(decision.destination == .local(localID))
    }

    @Test
    func providerInputRequirementsRouteByAttachmentSupport() {
        let imageRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "describe",
                    attachments: [ChatAttachment(kind: .image, fileName: "image.png", contentType: "image/png")]
                ),
            ]
        )
        #expect(imageRequirements.requiresImages)

        let heicRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "describe",
                    attachments: [ChatAttachment(kind: .image, fileName: "photo.heic", contentType: "image/heic")]
                ),
            ]
        )
        #expect(heicRequirements.requiresImages)
        #expect(ChatAttachment(kind: .image, fileName: "photo.heif", contentType: "").cloudInputKind == .image)
        #expect(ChatAttachment(kind: .image, fileName: "sequence.heics", contentType: "").normalizedContentType == "image/heic-sequence")

        let pdfRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "summarize",
                    attachments: [ChatAttachment(kind: .document, fileName: "doc.pdf", contentType: "application/pdf")]
                ),
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
                    attachments: [ChatAttachment(kind: .document, fileName: "notes.md", contentType: "text/markdown")]
                ),
            ]
        )
        #expect(!textRequirements.isSatisfied(by: ProviderCapabilities(local: false, imageInputs: true, pdfInputs: true)))
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
        #expect(!anthropic.capabilities.embeddings)

        let gemini = cloudConfiguration(kind: .gemini, baseURL: "https://generativelanguage.googleapis.com")
        #expect(gemini.capabilities.imageInputs)
        #expect(gemini.capabilities.pdfInputs)
        #expect(gemini.capabilities.textDocumentInputs)
        #expect(gemini.capabilities.embeddings)

        let openRouter = cloudConfiguration(kind: .openRouter, baseURL: "https://openrouter.ai/api/v1")
        #expect(openRouter.capabilities.imageInputs)
        #expect(openRouter.capabilities.pdfInputs)
        #expect(!openRouter.capabilities.textDocumentInputs)
        #expect(openRouter.capabilities.embeddings)

        let voyage = cloudConfiguration(kind: .voyageAI, baseURL: "https://api.voyageai.com/v1")
        #expect(!voyage.capabilities.textGeneration)
        #expect(voyage.capabilities.embeddings)

        let compatible = cloudConfiguration(kind: .openAICompatible, baseURL: "https://llm.example.test/v1")
        #expect(!compatible.capabilities.imageInputs)
        #expect(!compatible.capabilities.pdfInputs)
        #expect(!compatible.capabilities.textDocumentInputs)

        let customOpenAIHost = cloudConfiguration(kind: .custom, baseURL: "https://api.openai.com/v1")
        #expect(customOpenAIHost.capabilities.imageInputs)
        #expect(customOpenAIHost.capabilities.pdfInputs)
        #expect(customOpenAIHost.capabilities.textDocumentInputs)
    }

    @Test
    func vaultEmbeddingProfilesUseStableProviderScopedIDsAndDefaults() {
        let openAI = cloudConfiguration(kind: .openAI, baseURL: "https://api.openai.com/v1")
        let openAIProfile = VaultEmbeddingProfile.cloud(provider: openAI)
        #expect(openAIProfile?.modelID == ModelID(rawValue: "text-embedding-3-small"))
        #expect(openAIProfile?.dimensions == 1536)
        #expect(openAIProfile?.kind == .openAI)

        let gemini = cloudConfiguration(kind: .gemini, baseURL: "https://generativelanguage.googleapis.com")
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
        guard case let .array(requestArray) = geminiRequests,
              case let .object(firstRequest) = requestArray.first,
              case let .object(content) = firstRequest["content"],
              case let .array(parts) = content["parts"],
              case let .object(firstPart) = parts.first
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
        let text = "openai=\(openAIKey) hf=\(huggingFaceKey) bearer=\(bearerToken)"
        let redacted = Redactor().redact(text)

        #expect(!redacted.contains(openAIKey))
        #expect(!redacted.contains(huggingFaceKey))
        #expect(!redacted.contains(bearerToken))
        #expect(redacted.contains("[redacted-key]"))
        #expect(redacted.contains("Bearer [redacted-token]"))
    }

    @Test
    func openAIReasoningChatRequestsUseCompatibleTokenParameters() throws {
        let request = ChatRequest(
            modelID: "gpt-5.5",
            messages: [ChatMessage(role: .user, content: "Hello")],
            sampling: ChatSampling(maxTokens: 256, temperature: 0.6, topP: 1, openAIReasoningEffort: .high, openAITextVerbosity: .medium)
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
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
    }

    @Test
    func openAIReasoningEffortNormalizesModelSpecificValues() {
        #expect(CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5.5", requested: .xhigh) == .xhigh)
        #expect(CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5.5-pro", requested: .low) == .high)
        #expect(CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5", requested: .none) == .low)
        #expect(CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5", requested: .xhigh) == .low)
        #expect(CloudProviderModelEligibility.openAIReasoningEffort(for: "gpt-5.1", requested: .none) == .none)
        #expect(CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.5") == [.none, .low, .medium, .high, .xhigh])
        #expect(CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.4") == [.none, .low, .medium, .high, .xhigh])
        #expect(CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5") == [.minimal, .low, .medium, .high])
        #expect(CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.5-pro") == [.high])
        #expect(!CloudProviderModelEligibility.supportsOpenAITextVerbosity(modelID: "gpt-4o"))
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
                        ChatAttachment(kind: .image, fileName: "pines-test-image.png", contentType: "image/png", localURL: imageURL),
                    ]
                ),
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
                        ChatAttachment(kind: .document, fileName: "doc.pdf", contentType: "application/pdf", localURL: imageURL),
                    ]
                ),
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
    func openAICloudModelEligibilityKeepsGPT5MiniNanoAndFiltersOSeries() {
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5-mini", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5-nano", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.1-mini", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.1-nano", providerKind: .openAI))

        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o1", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o3", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o4-mini", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "openai/o3-mini", providerKind: .openRouter))
    }

    @Test
    func geminiModelEligibilityAcceptsInteractionsModels() {
        #expect(CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3-flash-preview",
            providerKind: .gemini,
            supportedGenerationMethods: ["createInteraction"]
        ))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(
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
        parser.recordRequestMetadata(providerKind: .anthropic, serverRequestID: "req_123", clientRequestID: nil)

        var allEvents = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for payload in [
            #"{"type":"message_start","message":{"id":"msg_123","usage":{"input_tokens":10}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"plan"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig_123"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"hello"}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"tool_1","name":"lookup","input":{}}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"q\":\"pines\"}"}}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":3}}"#,
        ] {
            let output = parser.parse(data: Data(payload.utf8), format: .anthropicMessages, providerKind: .anthropic)
            allEvents.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(allEvents.contains(.token(TokenDelta(kind: .token, text: "hello", tokenCount: 1))))
        #expect(allEvents.contains(.metrics(InferenceMetrics(promptTokens: 10, completionTokens: 0))))
        #expect(allEvents.contains(.metrics(InferenceMetrics(promptTokens: 0, completionTokens: 3))))
        #expect(allEvents.contains(.toolCall(ToolCallDelta(id: "tool_1", name: "lookup", argumentsFragment: #"{"q":"pines"}"#, isComplete: true))))
        #expect(finish?.reason == .toolCall)
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.anthropicRequestID] == "req_123")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.anthropicMessageID] == "msg_123")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.anthropicThinkingContentJSON]?.contains("sig_123") == true)
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

        let output = parser.parse(data: Data(payload.utf8), format: .geminiGenerateContent, providerKind: .gemini)

        #expect(output.events.contains(.token(TokenDelta(kind: .token, text: "visible", tokenCount: 1))))
        #expect(output.events.contains(.metrics(InferenceMetrics(promptTokens: 7, completionTokens: 5))))
        #expect(output.events.contains(.toolCall(ToolCallDelta(id: "call_1", name: "lookup", argumentsFragment: #"{"q":"pines"}"#, isComplete: true))))
        #expect(output.finish?.reason == .toolCall)
        #expect(output.finish?.providerMetadata[CloudProviderMetadataKeys.geminiResponseID] == "resp_1")
        #expect(parser.state.geminiProviderMetadata[CloudProviderMetadataKeys.geminiModelContentJSON]?.contains("thought_sig") == true)
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
            let output = parser.parse(data: Data(payload.utf8), format: .geminiInteractions, providerKind: .gemini)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "hello", tokenCount: 1))))
        #expect(events.contains(.toolCall(ToolCallDelta(id: "fn_1", name: "lookup", argumentsFragment: #"{"q":"pines"}"#, isComplete: true))))
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
            let output = parser.parse(data: Data(payload.utf8), format: .geminiInteractions, providerKind: .gemini)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "alias", tokenCount: 1))))
        #expect(events.contains(.metrics(InferenceMetrics(promptTokens: 2, completionTokens: 1))))
        #expect(finish?.reason == .stop)
    }

    @Test
    func openAIResponsesParserReportsEmptyCompletions() {
        var parser = CloudProviderStreamParser()
        let payload = #"{"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[]}}"#
        let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.isEmpty)
        #expect(output.finish?.reason == .stop)
        #expect(output.finish?.message?.contains("without visible output text") == true)
        #expect(output.finish?.providerMetadata[CloudProviderMetadataKeys.openAIResponseID] == "resp_1")
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
            let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
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
        let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.contains(.token(TokenDelta(kind: .token, text: "top level", tokenCount: 1))))
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
            let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        let toolCall = events.compactMap { event -> ToolCallDelta? in
            if case let .toolCall(toolCall) = event { return toolCall }
            return nil
        }.first
        #expect(toolCall?.id == "call_1")
        #expect(toolCall?.name == "lookup")
        #expect(toolCall?.argumentsFragment == #"{"query":"pines"}"#)
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIOutputItemsJSON]?.contains(#""function_call""#) == true)
    }

    @Test
    func appSettingsDecodesGenerationDefaultsAndClampsLimits() throws {
        let legacyJSON = #"{"executionMode":"cloudAllowed","themeTemplate":"graphite","interfaceMode":"dark"}"#
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(decoded.cloudMaxCompletionTokens == AppSettingsSnapshot.defaultCloudMaxCompletionTokens)
        #expect(decoded.localMaxCompletionTokens == AppSettingsSnapshot.defaultLocalMaxCompletionTokens)
        #expect(decoded.localMaxContextTokens == AppSettingsSnapshot.defaultLocalMaxContextTokens)
        #expect(decoded.openAIReasoningEffort == .low)
        #expect(decoded.openAITextVerbosity == .low)

        let clamped = AppSettingsSnapshot(
            cloudMaxCompletionTokens: 1,
            localMaxCompletionTokens: 1_000_000,
            localMaxContextTokens: 1,
            openAIReasoningEffort: .high,
            openAITextVerbosity: .medium
        )
        #expect(clamped.cloudMaxCompletionTokens == AppSettingsSnapshot.minCompletionTokens)
        #expect(clamped.localMaxCompletionTokens == AppSettingsSnapshot.maxCompletionTokens)
        #expect(clamped.localMaxContextTokens == AppSettingsSnapshot.minLocalContextTokens)
        #expect(clamped.openAIReasoningEffort == .high)
        #expect(clamped.openAITextVerbosity == .medium)

        let legacySampling = try JSONDecoder().decode(ChatSampling.self, from: Data(#"{"maxTokens":256,"temperature":0.2}"#.utf8))
        #expect(legacySampling.maxTokens == 256)
        #expect(legacySampling.temperature == 0.2)
        #expect(legacySampling.openAIReasoningEffort == .low)
        #expect(legacySampling.openAITextVerbosity == .low)
        #expect(legacySampling.openAIResponseStorage == .stateful)
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
    func calculatorHonorsOperatorPrecedenceAndRejectsDivisionByZero() throws {
        let evaluator = SafeCalculatorEvaluator()

        #expect(try evaluator.evaluate("2 + 3 * 4") == 14)
        #expect(try evaluator.evaluate("(2 + 3) * 4") == 20)
        #expect(throws: CalculatorEvaluationError.divisionByZero) {
            try evaluator.evaluate("1 / 0")
        }
    }

    private func cloudConfiguration(kind: CloudProviderKind, baseURL: String) -> CloudProviderConfiguration {
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
