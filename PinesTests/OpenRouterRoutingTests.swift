import Foundation
import XCTest
import PinesCore
@testable import pines

final class OpenRouterRoutingTests: XCTestCase {
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
