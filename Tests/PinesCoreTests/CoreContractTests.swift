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

        let mediaRequirements = ProviderInputRequirements(
            messages: [
                ChatMessage(
                    role: .user,
                    content: "analyze",
                    attachments: [
                        ChatAttachment(kind: .audio, fileName: "clip.mp3", contentType: ""),
                        ChatAttachment(kind: .video, fileName: "scene.mov", contentType: ""),
                    ]
                ),
            ]
        )
        #expect(ChatAttachment(kind: .audio, fileName: "clip.wav", contentType: "").cloudMediaInputKind == .audio)
        #expect(ChatAttachment(kind: .video, fileName: "scene.webm", contentType: "").cloudMediaInputKind == .video)
        #expect(mediaRequirements.requiresAudio)
        #expect(mediaRequirements.requiresVideo)
        #expect(!mediaRequirements.isSatisfied(by: ProviderCapabilities(local: false, audioInputs: true)))
        #expect(mediaRequirements.isSatisfied(by: ProviderCapabilities(local: false, audioInputs: true, videoInputs: true)))

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
    func conversationTitleDeriverNamesPlaceholderChatsFromUserContent() {
        let messages = [
            ChatMessage(role: .assistant, content: "Sure."),
            ChatMessage(
                role: .user,
                content: "Can we properly derive chat titles from chat conversation content? So chats are not just new chat."
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
                        ChatAttachment(kind: .document, fileName: "meeting_notes.md", contentType: "text/markdown"),
                    ]
                ),
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
        #expect(!anthropic.capabilities.embeddings)

        let gemini = cloudConfiguration(kind: .gemini, baseURL: "https://generativelanguage.googleapis.com")
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

        let compatible = cloudConfiguration(kind: .openAICompatible, baseURL: "https://llm.example.test/v1")
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
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwZW5lcyJ9.TJVA95OrM7E2cBab30RMHrHDcEfxjoYZgeFONFh7HgQ"
        let cookie = "Cookie: session=abcdef1234567890"
        let pemKind = "PRIVATE KEY"
        let pem = """
        -----BEGIN \(pemKind)-----
        abcdefghijklmnopqrstuvwxyz1234567890
        -----END \(pemKind)-----
        """
        let generic = String(repeating: "a", count: 48)
        let text = "openai=\(openAIKey) hf=\(huggingFaceKey) bearer=\(bearerToken) jwt=\(jwt) \(cookie) \(pem) generic=\(generic)"
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
    }

    @Test
    func cloudProviderHeadersClassifySecretNames() {
        #expect(CloudProviderHeader.isSecretLikeName("Authorization"))
        #expect(CloudProviderHeader.isSecretLikeName("X-Api-Key"))
        #expect(CloudProviderHeader.isSecretLikeName("x-session-token"))
        #expect(CloudProviderHeader.isSecretLikeName("Cookie"))
        #expect(!CloudProviderHeader.isSecretLikeName("X-Trace-ID"))

        #expect(CloudProviderHeader(name: "Authorization", kind: .publicValue, value: "Bearer test").storesSecretInPlaintext)
        #expect(!CloudProviderHeader(name: "X-Trace-ID", kind: .publicValue, value: "trace").storesSecretInPlaintext)
        #expect(!CloudProviderHeader(name: "Authorization", kind: .secretReference, keychainService: "svc", keychainAccount: "acct").storesSecretInPlaintext)
    }

    @Test
    func securityConfigurationDefaultsToEncryptedE2EModel() {
        let configuration = SecurityConfiguration()

        #expect(!configuration.appLockEnabled)
        #expect(configuration.encryptedStoreVersion == SecurityConfiguration.currentEncryptedStoreVersion)
        #expect(configuration.cloudKitE2EEnabled)
        #expect(configuration.securityResetCompletedAt == nil)
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
        #expect((json["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
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
        #expect(CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.5") == [.none, .minimal, .low, .medium, .high, .xhigh])
        #expect(CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.4") == [.none, .minimal, .low, .medium, .high, .xhigh])
        #expect(CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5") == [.minimal, .low, .medium, .high])
        #expect(CloudProviderModelEligibility.openAIReasoningEffortOptions(for: "gpt-5.5-pro") == [.high])
        #expect(!CloudProviderModelEligibility.supportsOpenAITextVerbosity(modelID: "gpt-4o"))
    }

    @Test
    func openAIChatCompletionsParserPreservesMetadataAndUsage() {
        var parser = CloudProviderStreamParser()
        parser.recordRequestMetadata(providerKind: .openAI, serverRequestID: "req_header", clientRequestID: "client_1")
        let payloads = [
            #"{"id":"chatcmpl_1","object":"chat.completion.chunk","model":"gpt-4.1","system_fingerprint":"fp_123","choices":[{"index":0,"delta":{"content":"hi"},"finish_reason":null}]}"#,
            #"{"id":"chatcmpl_1","object":"chat.completion.chunk","model":"gpt-4.1","choices":[],"usage":{"prompt_tokens":7,"completion_tokens":2,"total_tokens":9}}"#,
            #"{"id":"chatcmpl_1","object":"chat.completion.chunk","model":"gpt-4.1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
        ]

        var events = [InferenceStreamEvent]()
        var finish: InferenceFinish?
        for payload in payloads {
            let output = parser.parse(data: Data(payload.utf8), format: .chatCompletions, providerKind: .openAI)
            events.append(contentsOf: output.events)
            finish = output.finish ?? finish
        }

        #expect(events.contains(.token(TokenDelta(kind: .token, text: "hi", tokenCount: 1))))
        #expect(events.contains(.metrics(InferenceMetrics(promptTokens: 7, completionTokens: 2))))
        #expect(finish?.reason == .stop)
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIRequestID] == "req_header")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIClientRequestID] == "client_1")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIChatCompletionID] == "chatcmpl_1")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIModel] == "gpt-4.1")
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAISystemFingerprint] == "fp_123")
    }

    @Test
    func cloudProviderModelControlsMatchAnthropicAndGeminiCapabilities() {
        #expect(CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: "claude-opus-4-7"))
        #expect(CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: "claude-opus-4-6"))
        #expect(CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: "claude-sonnet-4-6"))
        #expect(!CloudProviderModelEligibility.usesAnthropicAdaptiveThinking(modelID: "claude-opus-4-5"))
        #expect(CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-opus-4-7") == [.low, .medium, .high, .xhigh, .max])
        #expect(CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-opus-4-6") == [.low, .medium, .high, .max])
        #expect(CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-sonnet-4-6") == [.low, .medium, .high, .max])
        #expect(CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-opus-4-5") == [.low, .medium, .high])
        #expect(CloudProviderModelEligibility.anthropicEffortOptions(for: "claude-sonnet-4-5").isEmpty)
        #expect(CloudProviderModelEligibility.anthropicEffort(for: "claude-sonnet-4-6", requested: .xhigh) == .high)

        #expect(CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "models/gemini-3.1-pro-preview") == [.low, .medium, .high])
        #expect(CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "models/gemini-3.1-flash-lite") == [.minimal, .low, .medium, .high])
        #expect(CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "gemini-3-flash-preview") == [.minimal, .low, .medium, .high])
        #expect(CloudProviderModelEligibility.geminiThinkingLevelOptions(for: "gemini-2.5-pro").isEmpty)
        #expect(CloudProviderModelEligibility.geminiThinkingLevel(for: "gemini-3.1-pro-preview", requested: .minimal) == .low)
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
    func cloudModelEligibilityKeepsCurrentProviderModelsAndFutureFamilies() {
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.5", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.5-pro", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.5-2026-04-23", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.4-mini", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.4-nano-2026-03-17", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.6-mini", providerKind: .openAI))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "gpt-6", providerKind: .openAI))

        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5-mini", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.4", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "gpt-5.4-pro", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "gpt-4.1-mini", providerKind: .openAI))

        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o1", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o3", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "o4-mini", providerKind: .openAI))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "openai/o3-mini", providerKind: .openRouter))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "openai/gpt-4.1", providerKind: .openRouter))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "openai/gpt-6", providerKind: .openRouter))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "meta/llama-4-maverick", providerKind: .openRouter))

        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "claude-opus-4-7", providerKind: .anthropic))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "claude-sonnet-4-6", providerKind: .anthropic))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "claude-haiku-4-5-20251001", providerKind: .anthropic))
        #expect(CloudProviderModelEligibility.isTextOutputModel(id: "claude-opus-5", providerKind: .anthropic))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "claude-opus-4-6", providerKind: .anthropic))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "claude-sonnet-4-5", providerKind: .anthropic))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "claude-3-7-sonnet-20250219", providerKind: .anthropic))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "anthropic/claude-sonnet-4-5", providerKind: .openRouter))

        #expect(CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3.1-pro-preview",
            providerKind: .gemini,
            supportedGenerationMethods: ["createInteraction"]
        ))
        #expect(CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3-flash-preview",
            providerKind: .gemini,
            supportedGenerationMethods: ["createInteraction"]
        ))
        #expect(CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3.1-flash-lite",
            providerKind: .gemini,
            supportedGenerationMethods: ["generateContent"]
        ))
        #expect(CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-4-pro",
            providerKind: .gemini,
            supportedGenerationMethods: ["generateContent"]
        ))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-3-pro-preview",
            providerKind: .gemini,
            supportedGenerationMethods: ["generateContent"]
        ))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(
            id: "models/gemini-2.5-pro",
            providerKind: .gemini,
            supportedGenerationMethods: ["generateContent"]
        ))
        #expect(!CloudProviderModelEligibility.isTextOutputModel(id: "google/gemini-2.5-pro", providerKind: .openRouter))
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

        let output = parser.parse(data: Data(payload.utf8), format: .geminiGenerateContent, providerKind: .gemini)
        let metadata = output.finish?.providerMetadata ?? parser.state.geminiProviderMetadata

        #expect(metadata[CloudProviderMetadataKeys.geminiCacheUsageJSON]?.contains("cachedContentTokenCount") == true)
        #expect(metadata[CloudProviderMetadataKeys.geminiCodeExecutionJSON]?.contains("OUTCOME_OK") == true)
        #expect(metadata[CloudProviderMetadataKeys.geminiURLContextJSON]?.contains("example.com") == true)
        #expect(metadata[CloudProviderMetadataKeys.geminiFileReferencesJSON]?.contains("audio") == true)
        #expect(metadata[CloudProviderMetadataKeys.geminiArtifactsJSON]?.contains("image") == true)
    }

    @Test
    func geminiSSEDecoderInjectsEventTypeAndPreservesID() throws {
        var decoder = CloudProviderSSEStreamDecoder()
        #expect(decoder.ingest("id: evt_1") == nil)
        #expect(decoder.ingest("event: interaction.completed") == nil)
        #expect(decoder.ingest(#"data: {"interaction":{"id":"ia_1","usage":{"total_input_tokens":1,"total_output_tokens":1}}}"#) == nil)
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
        let payload = #"{"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[]}}"#
        let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.isEmpty)
        #expect(output.finish?.reason == .stop)
        #expect(output.finish?.message?.contains("without visible output text") == true)
        #expect(output.finish?.providerMetadata[CloudProviderMetadataKeys.openAIResponseID] == "resp_1")
    }

    @Test
    func openAIResponsesParserReportsEmptyCompletionsEvenWithUsage() {
        var parser = CloudProviderStreamParser()
        let payload = #"{"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[],"usage":{"input_tokens":4,"output_tokens":1}}}"#
        let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.contains(.metrics(InferenceMetrics(promptTokens: 4, completionTokens: 1))))
        #expect(output.finish?.reason == .stop)
        #expect(output.finish?.message?.contains("without visible output text") == true)
        #expect(output.finish?.message?.contains("output items: 0") == true)
    }

    @Test
    func openAIResponsesParserSurfacesStreamErrors() {
        var parser = CloudProviderStreamParser()
        parser.recordRequestMetadata(providerKind: .openAI, serverRequestID: "req_header", clientRequestID: "client_1")
        let payload = #"{"type":"error","error":{"message":"The requested model is unavailable.","code":"model_not_found"}}"#
        let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.isEmpty)
        #expect(output.finish?.reason == .error)
        #expect(output.finish?.message == "The requested model is unavailable.")
        #expect(output.finish?.providerMetadata[CloudProviderMetadataKeys.openAIRequestID] == "req_header")
        #expect(output.finish?.providerMetadata[CloudProviderMetadataKeys.openAIClientRequestID] == "client_1")
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
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIResponseID] == "resp_missing_blanks")
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
        let payload = #"{"type":"response.output_text.done","content":[{"type":"output_text","text":{"value":"late text"}}]}"#
        let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.contains(.token(TokenDelta(kind: .token, text: "late text", tokenCount: 1))))
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
        let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)

        #expect(output.events.contains(.token(TokenDelta(kind: .token, text: "object content", tokenCount: 1))))
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
        #expect(finish?.reason == .toolCall)
        #expect(finish?.message == nil)
        #expect(finish?.providerMetadata[CloudProviderMetadataKeys.openAIOutputItemsJSON]?.contains(#""function_call""#) == true)
    }

    @Test
    func openAIResponsesFallbackPreservesCompletedToolCall() {
        var parser = CloudProviderStreamParser()
        let payload = #"{"type":"response.function_call_arguments.done","output_index":0,"item":{"id":"fc_1","call_id":"call_1","type":"function_call","name":"lookup","arguments":"{\"query\":\"pines\"}"}}"#
        let output = parser.parse(data: Data(payload.utf8), format: .openAIResponses, providerKind: .openAI)
        let finish = parser.fallbackFinish(
            format: .openAIResponses,
            providerKind: .openAI,
            modelID: "gpt-5.5",
            usesOfficialOpenAIReasoningChat: false
        )

        #expect(output.events.contains(.toolCall(ToolCallDelta(id: "call_1", name: "lookup", argumentsFragment: #"{"query":"pines"}"#, isComplete: true))))
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
        let openAIOutput = openAIParser.parse(data: Data(openAIPayload.utf8), format: .openAIResponses, providerKind: .openAI)
        let openAIFinish = try #require(openAIOutput.finish)
        let openAICitations = try decodedCitations(openAIFinish.providerMetadata)
        let openAIQueries = try decodedQueries(openAIFinish.providerMetadata)
        #expect(openAICitations == [WebSearchCitation(title: "OpenAI source", url: "https://example.com/openai", source: "OpenAI")])
        #expect(openAIQueries == ["pines native search"])

        var anthropicParser = CloudProviderStreamParser()
        let anthropicPayload = #"""
        {"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","title":"Anthropic source","url":"https://example.com/anthropic"}]}}
        """#
        _ = anthropicParser.parse(data: Data(anthropicPayload.utf8), format: .anthropicMessages, providerKind: .anthropic)
        let anthropicFinish = anthropicParser.fallbackFinish(format: .anthropicMessages, providerKind: .anthropic, modelID: "claude-sonnet-4-6", usesOfficialOpenAIReasoningChat: false)
        let anthropicCitations = try decodedCitations(anthropicFinish.providerMetadata)
        #expect(anthropicCitations == [WebSearchCitation(title: "Anthropic source", url: "https://example.com/anthropic", source: "Anthropic")])

        var geminiParser = CloudProviderStreamParser()
        let geminiPayload = #"""
        {"candidates":[{"content":{"parts":[{"text":"Gemini grounded response."}],"role":"model"},"groundingMetadata":{"webSearchQueries":["pines gemini search"],"searchEntryPoint":{"renderedContent":"<div>Search suggestions</div>"},"groundingChunks":[{"web":{"uri":"https://example.com/gemini","title":"Gemini source"}}]},"finishReason":"STOP"}]}
        """#
        let geminiOutput = geminiParser.parse(data: Data(geminiPayload.utf8), format: .geminiGenerateContent, providerKind: .gemini)
        let geminiFinish = try #require(geminiOutput.finish)
        let geminiCitations = try decodedCitations(geminiFinish.providerMetadata)
        let geminiQueries = try decodedQueries(geminiFinish.providerMetadata)
        #expect(geminiCitations == [WebSearchCitation(title: "Gemini source", url: "https://example.com/gemini", source: "Gemini")])
        #expect(geminiQueries == ["pines gemini search"])
        #expect(geminiFinish.providerMetadata[CloudProviderMetadataKeys.webSearchSuggestionsHTML] == "<div>Search suggestions</div>")
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
        #expect(decoded.anthropicEffort == .medium)
        #expect(decoded.geminiThinkingLevel == .medium)
        #expect(decoded.cloudWebSearchMode == .off)

        let clamped = AppSettingsSnapshot(
            cloudMaxCompletionTokens: 1,
            localMaxCompletionTokens: 1_000_000,
            localMaxContextTokens: 1,
            openAIReasoningEffort: .high,
            openAITextVerbosity: .medium,
            anthropicEffort: .xhigh,
            geminiThinkingLevel: .high,
            cloudWebSearchMode: .automatic
        )
        #expect(clamped.cloudMaxCompletionTokens == AppSettingsSnapshot.minCompletionTokens)
        #expect(clamped.localMaxCompletionTokens == AppSettingsSnapshot.maxCompletionTokens)
        #expect(clamped.localMaxContextTokens == AppSettingsSnapshot.minLocalContextTokens)
        #expect(clamped.openAIReasoningEffort == .high)
        #expect(clamped.openAITextVerbosity == .medium)
        #expect(clamped.anthropicEffort == .xhigh)
        #expect(clamped.geminiThinkingLevel == .high)
        #expect(clamped.cloudWebSearchMode == .automatic)

        let legacySampling = try JSONDecoder().decode(ChatSampling.self, from: Data(#"{"maxTokens":256,"temperature":0.2}"#.utf8))
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
                userLocation: CloudWebSearchUserLocation(city: "Berlin", region: "Berlin", country: "DE", timezone: "Europe/Berlin"),
                allowedDomains: ["example.com"],
                blockedDomains: ["blocked.example"],
                externalWebAccess: true
            )
        )
        let decodedWebSearchRequest = try JSONDecoder().decode(ChatRequest.self, from: JSONEncoder().encode(webSearchRequest))
        #expect(decodedWebSearchRequest.webSearchOptions?.contextSize == .high)
        #expect(decodedWebSearchRequest.webSearchOptions?.userLocation?.city == "Berlin")
        #expect(decodedWebSearchRequest.webSearchOptions?.allowedDomains == ["example.com"])
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
        let decodedRequest = try JSONDecoder().decode(ChatRequest.self, from: JSONEncoder().encode(request))
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

        #expect(try JSONDecoder().decode(OpenAIVectorStore.self, from: JSONEncoder().encode(vectorStore)) == vectorStore)
        #expect(try JSONDecoder().decode(OpenAIBackgroundResponse.self, from: JSONEncoder().encode(background)) == background)
        #expect(try JSONDecoder().decode(OpenAIStructuredOutputResult.self, from: JSONEncoder().encode(structured)) == structured)
        #expect(try JSONDecoder().decode(ProviderContextCache.self, from: JSONEncoder().encode(cache)) == cache)
        #expect(providerFile.id == "file_1")
        #expect(providerDataStore.id == "vs_1")
        #expect(providerBackgroundRun.id == "resp_1")
        #expect(providerStructured.schemaName == "answer")
    }

    @Test
    func openAIParityMigrationAddsTablesAndRunProvenance() throws {
        #expect(PinesDatabaseSchema.currentVersion == 15)
        let openAIMigration = try #require(PinesDatabaseSchema.migrations.first { $0.version == 14 })
        let genericProviderMigration = try #require(PinesDatabaseSchema.migrations.first { $0.version == 15 })
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
                "vector_store_ids": .array(request.sourcePolicy.vectorStoreIDs.map { .string($0.rawValue) }),
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

        let decodedRequest = try JSONDecoder().decode(OpenAIDeepResearchRequest.self, from: JSONEncoder().encode(request))
        let decodedRun = try JSONDecoder().decode(OpenAIDeepResearchRun.self, from: JSONEncoder().encode(run))
        let decodedProviderRun = try JSONDecoder().decode(ProviderResearchRunRecord.self, from: JSONEncoder().encode(providerRun))

        #expect(decodedRequest == request)
        #expect(decodedRun == run)
        #expect(decodedProviderRun == providerRun)
        #expect(decodedRun.request.modelID == "gpt-5.5-pro")
        #expect(decodedRun.request.sourcePolicy.vectorStoreIDs == ["vs_123"])
        #expect(decodedProviderRun.responseID == "resp_123")
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
                                    .object(["type": .string("url_citation"), "url": .string("https://example.com")]),
                                ]),
                            ]),
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
                            ]),
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

    private func decodedCitations(_ metadata: [String: String]) throws -> [WebSearchCitation] {
        let raw = try #require(metadata[CloudProviderMetadataKeys.webSearchCitationsJSON])
        return try JSONDecoder().decode([WebSearchCitation].self, from: Data(raw.utf8))
    }

    private func decodedQueries(_ metadata: [String: String]) throws -> [String] {
        let raw = try #require(metadata[CloudProviderMetadataKeys.webSearchQueriesJSON])
        return try JSONDecoder().decode([String].self, from: Data(raw.utf8))
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
    func calculatorHonorsOperatorPrecedenceAndRejectsDivisionByZero() throws {
        let evaluator = SafeCalculatorEvaluator()

        #expect(try evaluator.evaluate("2 + 3 * 4") == 14)
        #expect(try evaluator.evaluate("(2 + 3) * 4") == 20)
        #expect(throws: CalculatorEvaluationError.divisionByZero) {
            try evaluator.evaluate("1 / 0")
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
        let roundTripped = try JSONDecoder().decode(ChatRequest.self, from: JSONEncoder().encode(request))
        #expect(roundTripped.executionContext == .agent)
    }

    @Test
    func agentEvidenceFormatterProducesReadableWebEvidence() throws {
        let resultsData = try JSONSerialization.data(withJSONObject: [
            ["title": "Pines Source", "url": "https://example.com/pines", "snippet": "Useful context."],
        ])
        let rawData = try JSONSerialization.data(withJSONObject: [
            "resultsJSON": String(decoding: resultsData, as: UTF8.self),
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
        let rawData = try JSONSerialization.data(withJSONObject: [
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
            ],
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
        let vaultSpec = try AnyToolSpec(VaultSearchTool.spec { query, _ in
            VaultSearchOutput(query: query, searchMode: "lexical", results: [])
        })
        let conversationSpec = try AnyToolSpec(ConversationSearchTool.spec(repository: EmptyConversationRepository()))

        #expect(attachmentSpec.permissions.contains(.cloudContext))
        #expect(vaultSpec.permissions.contains(.cloudContext))
        #expect(conversationSpec.permissions.contains(.cloudContext))
    }

    @Test
    func toolRegistryEnforcesDeclaredTimeouts() async throws {
        let registry = ToolRegistry()
        let spec = try ToolSpec<CalculatorInput, CalculatorOutput>(
            name: "calculator.slow",
            description: "Slow calculator used to verify timeout behavior.",
            inputSchema: ToolIOSchema(properties: ["expression": .init(type: .string)], required: ["expression"]),
            outputSchema: ToolIOSchema(properties: ["value": .init(type: .number), "formatted": .init(type: .string)]),
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

private struct EmptyConversationRepository: ConversationRepository {
    func listConversations() async throws -> [ConversationRecord] { [] }
    func listConversationPreviews() async throws -> [ConversationPreviewRecord] { [] }
    func observeConversations() -> AsyncStream<[ConversationRecord]> { AsyncStream { $0.finish() } }
    func observeConversationPreviews() -> AsyncStream<[ConversationPreviewRecord]> { AsyncStream { $0.finish() } }
    func createConversation(title: String, defaultModelID: ModelID?, defaultProviderID: ProviderID?) async throws -> ConversationRecord {
        ConversationRecord(title: title, defaultModelID: defaultModelID, defaultProviderID: defaultProviderID)
    }
    func updateConversationTitle(_ title: String, conversationID: UUID) async throws {}
    func updateConversationModel(modelID: ModelID?, providerID: ProviderID?, conversationID: UUID) async throws {}
    func setConversationArchived(_ archived: Bool, conversationID: UUID) async throws {}
    func setConversationPinned(_ pinned: Bool, conversationID: UUID) async throws {}
    func deleteConversation(id: UUID) async throws {}
    func messages(in conversationID: UUID) async throws -> [ChatMessage] { [] }
    func observeMessages(in conversationID: UUID) -> AsyncStream<[ChatMessage]> { AsyncStream { $0.finish() } }
    func appendMessage(_ message: ChatMessage, status: MessageStatus, conversationID: UUID, modelID: ModelID?, providerID: ProviderID?) async throws {}
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
