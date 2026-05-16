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
            requiresVision: false,
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
                ProviderCapabilities(local: true, textGeneration: true, vision: true, toolCalling: true)
            ),
            cloud: (
                ProviderID(rawValue: "cloud"),
                ProviderCapabilities(local: false, textGeneration: true, vision: true, toolCalling: true)
            ),
            requiresVision: true,
            requiresTools: true
        )

        #expect(decision.destination == .local(localID))
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

        #expect(json["max_completion_tokens"] as? Int == 16_384)
        #expect(json["max_tokens"] == nil)
        #expect(json["reasoning_effort"] as? String == "low")
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
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
}
