import Foundation
import XCTest
import PinesCore
@testable import pines

final class OpenRouterRoutingTests: XCTestCase {
    func testModelCatalogParsesBoundedCapabilitiesPricingAndLifecycleMetadata() throws {
        let payload: [String: Any] = [
            "data": [
                [
                    "id": "example/vision-chat",
                    "canonical_slug": "example/vision-chat-2026-07-01",
                    "name": "Vision Chat",
                    "description": String(repeating: "A", count: 1_200),
                    "context_length": 131_072,
                    "architecture": [
                        "input_modalities": ["text", "image", "file", "IMAGE"],
                        "output_modalities": ["text"],
                        "tokenizer": "Example",
                        "instruct_type": "chatml",
                    ],
                    "pricing": [
                        "prompt": "0.00000015",
                        "completion": "0.0000006",
                        "request": "0",
                        "web_search": "0.004",
                    ],
                    "supported_parameters": ["tools", "response_format", "structured_outputs"],
                    "top_provider": [
                        "context_length": 131_072,
                        "max_completion_tokens": 16_384,
                        "is_moderated": true,
                    ],
                    "expiration_date": "2027-01-01",
                    "knowledge_cutoff": "2026-06",
                ],
                [
                    "id": "example/image-generator",
                    "name": "Image Generator",
                    "architecture": [
                        "input_modalities": ["text"],
                        "output_modalities": ["image"],
                    ],
                ],
            ],
        ]

        let models = BYOKCloudInferenceProvider.parseModels(payload, providerKind: .openRouter)
        let model = try XCTUnwrap(models.first)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(model.displayName, "Vision Chat")
        XCTAssertEqual(model.metadata?.canonicalSlug, "example/vision-chat-2026-07-01")
        XCTAssertEqual(model.metadata?.summary?.count, 1_024)
        XCTAssertEqual(model.metadata?.inputModalities, ["text", "image", "file"])
        XCTAssertEqual(model.metadata?.outputModalities, ["text"])
        XCTAssertEqual(model.metadata?.contextLength, 131_072)
        XCTAssertEqual(model.metadata?.maxCompletionTokens, 16_384)
        XCTAssertEqual(model.metadata?.isModerated, true)
        XCTAssertEqual(model.metadata?.expirationDate, "2027-01-01")
        XCTAssertEqual(model.metadata?.knowledgeCutoff, "2026-06")
        XCTAssertEqual(model.metadata?.pricing?.prompt, Decimal(string: "0.00000015"))
        XCTAssertEqual(model.metadata?.pricing?.completion, Decimal(string: "0.0000006"))
        XCTAssertEqual(model.metadata?.pricing?.webSearch, Decimal(string: "0.004"))
        XCTAssertEqual(model.capabilities?.maxContextTokens, 131_072)
        XCTAssertEqual(model.capabilities?.maxOutputTokens, 16_384)
        XCTAssertEqual(model.capabilities?.imageInputs, true)
        XCTAssertEqual(model.capabilities?.pdfInputs, true)
        XCTAssertEqual(model.capabilities?.toolCalling, true)
        XCTAssertEqual(model.capabilities?.structuredOutputs, true)
    }

    func testModelEligibilityRejectsUnsupportedInputsToolsAndSchema() {
        let model = CloudProviderModel(
            id: "example/text-only",
            displayName: "Text Only",
            capabilities: ProviderCapabilities(
                local: false,
                textGeneration: true,
                toolCalling: false,
                jsonMode: true,
                structuredOutputs: false
            )
        )

        let report = model.eligibility(
            requiredInputs: ProviderInputRequirements(requiresImages: true),
            requiresTools: true,
            structuredOutput: .jsonSchema(name: "answer", schema: .object([:]), strict: true)
        )

        XCTAssertFalse(report.isEligible)
        XCTAssertEqual(
            report.reasons,
            [
                "This model does not advertise image input.",
                "This model does not advertise tool calling.",
                "This model does not advertise strict structured outputs.",
            ]
        )
    }

    func testLegacyModelCatalogDecodingRemainsBackwardCompatible() throws {
        let data = Data(#"{"id":"example/model","displayName":"Example"}"#.utf8)

        let model = try JSONDecoder().decode(CloudProviderModel.self, from: data)

        XCTAssertNil(model.metadata)
        XCTAssertNil(model.capabilities)
        XCTAssertEqual(model.supportedParameters, [])
    }

    func testPreferencesNormalizeProviderSlugsAndResolveConflicts() {
        let preferences = OpenRouterProviderPreferences(
            order: [" Anthropic ", "OPENAI", "anthropic"],
            only: ["Azure", "azure"],
            ignore: ["AZURE", "DeepInfra"],
            sort: .throughput
        )

        XCTAssertEqual(preferences.order, ["anthropic", "openai"])
        XCTAssertEqual(preferences.only, ["azure"])
        XCTAssertEqual(preferences.ignore, ["deepinfra"])
        XCTAssertEqual(preferences.sort, .automatic, "Explicit provider order must win over sorting.")
    }

    func testProviderObjectSerializesPrivacyAndReliabilityControls() throws {
        let preferences = OpenRouterProviderPreferences(
            only: ["azure"],
            ignore: ["deepinfra"],
            allowFallbacks: false,
            requireParameters: false,
            dataCollection: .deny,
            zeroDataRetention: true,
            sort: .latency
        )

        let object = try XCTUnwrap(
            BYOKCloudInferenceProvider.openRouterProviderObject(
                preferences,
                requiresParameters: true
            )
        )

        XCTAssertEqual(object["sort"] as? String, "latency")
        XCTAssertEqual(object["only"] as? [String], ["azure"])
        XCTAssertEqual(object["ignore"] as? [String], ["deepinfra"])
        XCTAssertEqual(object["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(object["require_parameters"] as? Bool, true)
        XCTAssertEqual(object["data_collection"] as? String, "deny")
        XCTAssertEqual(object["zdr"] as? Bool, true)
    }

    func testPreferencesAndChatRequestRoundTrip() throws {
        let preferences = OpenRouterProviderPreferences(
            order: ["anthropic", "openai"],
            allowFallbacks: false,
            requireParameters: true,
            dataCollection: .deny,
            zeroDataRetention: true
        )
        let request = ChatRequest(
            modelID: ModelID(rawValue: "openai/gpt-5-mini"),
            messages: [ChatMessage(role: .user, content: "Hello")],
            openRouterOptions: preferences
        )

        let decoded = try JSONDecoder().decode(
            ChatRequest.self,
            from: JSONEncoder().encode(request)
        )

        XCTAssertEqual(decoded.openRouterOptions, preferences)
    }

    func testDecodedPreferencesRestoreNormalizationAndDefaults() throws {
        let data = Data(
            #"{"order":[" Anthropic ","OPENAI","anthropic"],"only":["Azure"],"ignore":["azure","DeepInfra"],"sort":"latency"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(OpenRouterProviderPreferences.self, from: data)

        XCTAssertEqual(decoded.order, ["anthropic", "openai"])
        XCTAssertEqual(decoded.only, ["azure"])
        XCTAssertEqual(decoded.ignore, ["deepinfra"])
        XCTAssertEqual(decoded.sort, .automatic)
        XCTAssertTrue(decoded.allowFallbacks)
        XCTAssertFalse(decoded.requireParameters)
        XCTAssertEqual(decoded.dataCollection, .allow)
        XCTAssertFalse(decoded.zeroDataRetention)
    }

    func testOpenRouterRequestCarriesTypedRoutingPolicyAndStructuredOutput() async throws {
        let provider = BYOKCloudInferenceProvider(
            configuration: CloudProviderConfiguration(
                id: "openrouter",
                kind: .openRouter,
                displayName: "OpenRouter",
                baseURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1")),
                keychainAccount: "openrouter"
            ),
            secretStore: InMemorySecretStore()
        )
        let request = ChatRequest(
            modelID: "openai/gpt-5-mini",
            messages: [ChatMessage(role: .user, content: "Return JSON")],
            structuredOutput: .jsonSchema(
                name: "answer",
                schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "answer": .object(["type": .string("string")]),
                    ]),
                ]),
                strict: true
            ),
            openRouterOptions: OpenRouterProviderPreferences(
                only: ["anthropic"],
                allowFallbacks: false,
                dataCollection: .deny,
                zeroDataRetention: true,
                sort: .latency
            )
        )

        let urlRequest = try await provider.openAICompatibleRequest(apiKey: "test-secret", chatRequest: request)
        let bodyData = try XCTUnwrap(urlRequest.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        let routing = try XCTUnwrap(body["provider"] as? [String: Any])
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])

        XCTAssertEqual(urlRequest.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-OpenRouter-Metadata"), "enabled")
        XCTAssertEqual(routing["only"] as? [String], ["anthropic"])
        XCTAssertEqual(routing["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(routing["require_parameters"] as? Bool, true)
        XCTAssertEqual(routing["data_collection"] as? String, "deny")
        XCTAssertEqual(routing["zdr"] as? Bool, true)
        XCTAssertEqual(routing["sort"] as? String, "latency")
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        XCTAssertEqual(jsonSchema["name"] as? String, "answer")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
    }
}
