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

        let anthropic = cloudConfiguration(kind: .anthropic, baseURL: "https://api.anthropic.com")
        #expect(anthropic.capabilities.imageInputs)
        #expect(anthropic.capabilities.pdfInputs)
        #expect(anthropic.capabilities.textDocumentInputs)

        let gemini = cloudConfiguration(kind: .gemini, baseURL: "https://generativelanguage.googleapis.com")
        #expect(gemini.capabilities.imageInputs)
        #expect(gemini.capabilities.pdfInputs)
        #expect(gemini.capabilities.textDocumentInputs)

        let openRouter = cloudConfiguration(kind: .openRouter, baseURL: "https://openrouter.ai/api/v1")
        #expect(openRouter.capabilities.imageInputs)
        #expect(openRouter.capabilities.pdfInputs)
        #expect(!openRouter.capabilities.textDocumentInputs)

        let compatible = cloudConfiguration(kind: .openAICompatible, baseURL: "https://llm.example.test/v1")
        #expect(compatible.capabilities.imageInputs)
        #expect(!compatible.capabilities.pdfInputs)
        #expect(!compatible.capabilities.textDocumentInputs)

        let customOpenAIHost = cloudConfiguration(kind: .custom, baseURL: "https://api.openai.com/v1")
        #expect(customOpenAIHost.capabilities.imageInputs)
        #expect(customOpenAIHost.capabilities.pdfInputs)
        #expect(customOpenAIHost.capabilities.textDocumentInputs)
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
            sampling: ChatSampling(maxTokens: 256, temperature: 0.6, topP: 1)
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
        #expect(json["reasoning_effort"] as? String == "low")
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
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
    func appSettingsDecodesGenerationDefaultsAndClampsLimits() throws {
        let legacyJSON = #"{"executionMode":"cloudAllowed","themeTemplate":"graphite","interfaceMode":"dark"}"#
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: Data(legacyJSON.utf8))

        #expect(decoded.cloudMaxCompletionTokens == AppSettingsSnapshot.defaultCloudMaxCompletionTokens)
        #expect(decoded.localMaxCompletionTokens == AppSettingsSnapshot.defaultLocalMaxCompletionTokens)
        #expect(decoded.localMaxContextTokens == AppSettingsSnapshot.defaultLocalMaxContextTokens)

        let clamped = AppSettingsSnapshot(
            cloudMaxCompletionTokens: 1,
            localMaxCompletionTokens: 1_000_000,
            localMaxContextTokens: 1
        )
        #expect(clamped.cloudMaxCompletionTokens == AppSettingsSnapshot.minCompletionTokens)
        #expect(clamped.localMaxCompletionTokens == AppSettingsSnapshot.maxCompletionTokens)
        #expect(clamped.localMaxContextTokens == AppSettingsSnapshot.minLocalContextTokens)
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
