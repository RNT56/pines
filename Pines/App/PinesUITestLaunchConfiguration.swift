import Foundation
import PinesCore

extension String {
    var uiTestIdentifierComponent: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

enum PinesUITestLaunchConfiguration {
    enum InferenceScenario: String {
        case streaming
        case slowStreaming = "slow-streaming"
        case empty
        case error
        case syntheticWatchdogFinish = "synthetic-watchdog-finish"
    }

    static var isEnabled: Bool {
        #if DEBUG
        let process = ProcessInfo.processInfo
        return process.environment["PINES_UI_TESTING"] == "1"
            || process.arguments.contains("--pines-ui-testing")
        #else
        return false
        #endif
    }

    static var isSimulatorPerformanceTesting: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["PINES_RUN_UI_PERFORMANCE_TESTS"] == "1"
        #else
        false
        #endif
    }

    private static var isHarnessEnabled: Bool {
        isEnabled || isSimulatorPerformanceTesting
    }

    static var resetsStore: Bool {
        #if DEBUG || targetEnvironment(simulator)
        guard isHarnessEnabled else { return false }
        let process = ProcessInfo.processInfo
        return process.environment["PINES_UI_TEST_RESET_STORE"] == "1"
            || process.arguments.contains("--pines-reset-ui-test-store")
        #else
        return false
        #endif
    }

    static var databaseFileName: String {
        #if DEBUG || targetEnvironment(simulator)
        let configuredName = ProcessInfo.processInfo.environment["PINES_UI_TEST_DATABASE_FILE"]
        if let fileName = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fileName.isEmpty {
            return fileName
        }
        return "pines-ui-tests.sqlite"
        #else
        return "pines.sqlite"
        #endif
    }

    static var usesPlaintextDatabase: Bool {
        #if DEBUG || targetEnvironment(simulator)
        guard isHarnessEnabled else { return false }
        let process = ProcessInfo.processInfo
        return process.environment["PINES_UI_TEST_DATABASE_PLAINTEXT"] == "1"
            || process.arguments.contains("--pines-ui-test-plaintext-database")
        #else
        return false
        #endif
    }

    static var seedsArtifactLibrary: Bool {
        #if DEBUG || targetEnvironment(simulator)
        guard isHarnessEnabled else { return false }
        return ProcessInfo.processInfo.environment["PINES_UI_TEST_ARTIFACTS_FIXTURE"] == "1"
        #else
        return false
        #endif
    }

    static var usesAccessibilityTextSize: Bool {
        #if DEBUG
        guard isEnabled else { return false }
        return ProcessInfo.processInfo.environment["PINES_UI_TEST_ACCESSIBILITY_TEXT"] == "1"
        #else
        return false
        #endif
    }

    static var usesDarkAppearance: Bool {
        #if DEBUG
        guard isEnabled else { return false }
        return ProcessInfo.processInfo.environment["PINES_UI_TEST_DARK_APPEARANCE"] == "1"
        #else
        return false
        #endif
    }

    static var initialTabIdentifier: String? {
        #if DEBUG
        guard isEnabled else { return nil }
        let raw = ProcessInfo.processInfo.environment["PINES_UI_TEST_INITIAL_TAB"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw?.isEmpty == false ? raw : nil
        #else
        return nil
        #endif
    }

    static var storeConfiguration: LocalStoreConfiguration {
        guard isHarnessEnabled else { return .init() }
        return LocalStoreConfiguration(
            databaseFileName: databaseFileName,
            dataProtection: .completeUntilFirstUserAuthentication,
            iCloudSyncEnabled: false,
            syncsSourceDocuments: false,
            syncsEmbeddings: false
        )
    }

    static var inferenceScenario: InferenceScenario? {
        #if DEBUG
        guard isEnabled else { return nil }
        let raw = ProcessInfo.processInfo.environment["PINES_UI_TEST_INFERENCE_SCENARIO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return InferenceScenario(rawValue: raw)
        #else
        return nil
        #endif
    }

    static var localGenerationWatchdogConfiguration: InferenceStreamWatchdogConfiguration? {
        #if DEBUG
        guard isEnabled else { return nil }
        return InferenceStreamWatchdogConfiguration(
            firstEventTimeoutSeconds: 1,
            progressTimeoutSeconds: 1,
            pollIntervalSeconds: 0.1,
            code: "ui_test_local_generation_watchdog_timeout",
            firstEventMessage: "UI test local generation stalled before producing output.",
            progressMessage: "UI test local generation stopped making progress."
        )
        #else
        return nil
        #endif
    }

    static func inferenceProvider(localProviderID: ProviderID) -> (any InferenceProvider)? {
        #if DEBUG
        guard let scenario = inferenceScenario else { return nil }
        return PinesUITestInferenceProvider(
            scenario: scenario,
            localProviderID: localProviderID
        )
        #else
        _ = localProviderID
        return nil
        #endif
    }

    static var inferenceModelID: ModelID? {
        #if DEBUG
        guard let scenario = inferenceScenario else { return nil }
        return scenario == .syntheticWatchdogFinish
            ? ModelID(rawValue: "pines-ui-test-local-model")
            : ModelID(rawValue: "pines-ui-test-model")
        #else
        return nil
        #endif
    }

    @MainActor
    static func seedArtifactLibraryIfNeeded(services: PinesAppServices) async throws {
        #if DEBUG || targetEnvironment(simulator)
        guard seedsArtifactLibrary else { return }

        let providerID = ProviderID(rawValue: "pines-ui-test-openai")
        let provider = CloudProviderConfiguration(
            id: providerID,
            kind: .openAI,
            displayName: "OpenAI Studio",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            defaultModelID: ModelID(rawValue: "gpt-5.2"),
            validationStatus: .valid,
            keychainAccount: "pines-ui-test-openai"
        )
        try await services.cloudProviderRepository?.upsertProvider(provider)

        let now = Date()
        let tinyPNG = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAIKADAAQAAAABAAAAIAAAAACPTkDJAAAATUlEQVRYCWMUCTD6z8TAyEAO3thTxwAD4SVtZJnBwsAMM4JCmkxzRh0wGgKjITAaAqMhMBoCoyEwGgKjITAaAqMhMBoCoyEwGgKjIQAApMcGKi6phXwAAAAASUVORK5CYII="
        let artifacts = [
            ProviderArtifactRecord(
                id: "pines-ui-test-image",
                providerID: providerID,
                providerKind: .openAI,
                responseID: "resp_image_fixture",
                kind: "generated_image",
                fileName: "forest-study.png",
                contentType: "image/png",
                content: .object([
                    "b64_json": .string(tinyPNG),
                    "pines_prompt": .string("Architectural study of a glass cabin among tall pines"),
                    "status": .string("completed"),
                ]),
                createdAt: now.addingTimeInterval(-300)
            ),
            ProviderArtifactRecord(
                id: "pines-ui-test-video",
                providerID: providerID,
                providerKind: .openAI,
                responseID: "video_fixture",
                kind: "video_job",
                fileName: "forest-motion.mp4",
                contentType: "video/mp4",
                content: .object([
                    "pines_prompt": .string("Slow aerial motion through a misty pine forest"),
                    "status": .string("completed"),
                ]),
                remoteURL: URL(string: "https://example.com/forest-motion.mp4"),
                createdAt: now.addingTimeInterval(-240)
            ),
            ProviderArtifactRecord(
                id: "pines-ui-test-speech",
                providerID: providerID,
                providerKind: .openAI,
                responseID: "speech_fixture",
                kind: "speech",
                fileName: "field-notes.mp3",
                contentType: "audio/mpeg",
                content: .object([
                    "pines_prompt": .string("Read the field notes in a calm, natural voice"),
                    "status": .string("completed"),
                ]),
                createdAt: now.addingTimeInterval(-180)
            ),
            ProviderArtifactRecord(
                id: "pines-ui-test-report",
                providerID: providerID,
                providerKind: .openAI,
                responseID: "research_fixture",
                kind: "deep_research_report",
                fileName: "forest-architecture.md",
                contentType: "text/markdown",
                text: "# Forest architecture patterns\n\nA concise synthesis of material, light, and ecological constraints.",
                createdAt: now.addingTimeInterval(-120)
            ),
            ProviderArtifactRecord(
                id: "pines-ui-test-active-video",
                providerID: providerID,
                providerKind: .openAI,
                responseID: "video_active_fixture",
                kind: "video_job",
                contentType: "video/mp4",
                content: .object([
                    "pines_prompt": .string("Wind moving through pine branches at dusk"),
                    "status": .string("processing"),
                ]),
                createdAt: now.addingTimeInterval(-30)
            ),
        ]
        for artifact in artifacts {
            try await services.providerArtifactRepository?.upsertProviderArtifact(artifact)
        }

        let runs = [
            ProviderResearchRunRecord(
                id: "pines-ui-test-research-complete",
                providerID: providerID,
                providerKind: .openAI,
                modelID: ModelID(rawValue: "o4-deep-research"),
                title: "Forest architecture patterns",
                prompt: "Compare contemporary forest architecture patterns.",
                depth: "standard",
                sourcePolicy: .object(["mode": .string("web_only")]),
                reportFormat: "markdown",
                serviceTier: "auto",
                responseID: "research_fixture",
                status: "completed",
                finalReportArtifactID: "pines-ui-test-report",
                citationCount: 8,
                toolCallCount: 5,
                createdAt: now.addingTimeInterval(-360),
                updatedAt: now.addingTimeInterval(-120),
                completedAt: now.addingTimeInterval(-120)
            ),
            ProviderResearchRunRecord(
                id: "pines-ui-test-research-active",
                providerID: providerID,
                providerKind: .openAI,
                modelID: ModelID(rawValue: "o4-deep-research"),
                title: "Low-impact woodland materials",
                prompt: "Research durable low-impact materials for woodland construction.",
                depth: "standard",
                sourcePolicy: .object(["mode": .string("web_only")]),
                reportFormat: "markdown",
                serviceTier: "auto",
                responseID: "research_active_fixture",
                status: "in_progress",
                citationCount: 3,
                toolCallCount: 2,
                createdAt: now.addingTimeInterval(-90),
                updatedAt: now.addingTimeInterval(-15)
            ),
        ]
        for run in runs {
            try await services.providerResearchRunRepository?.upsertProviderResearchRun(run)
        }
        #else
        _ = services
        #endif
    }
}

enum PinesInferenceStreamGuard {
    static var localGenerationConfiguration: InferenceStreamWatchdogConfiguration {
        #if DEBUG
        if let configuration = PinesUITestLaunchConfiguration.localGenerationWatchdogConfiguration {
            return configuration
        }
        #endif
        return .localGeneration
    }

    static func guardedIfLocal(
        _ source: AsyncThrowingStream<InferenceStreamEvent, Error>,
        isLocal: Bool
    ) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        guard isLocal else { return source }
        return InferenceStreamWatchdog.guarded(
            source,
            configuration: localGenerationConfiguration
        )
    }
}
