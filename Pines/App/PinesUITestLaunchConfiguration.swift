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

    static var resetsStore: Bool {
        #if DEBUG
        guard isEnabled else { return false }
        let process = ProcessInfo.processInfo
        return process.environment["PINES_UI_TEST_RESET_STORE"] == "1"
            || process.arguments.contains("--pines-reset-ui-test-store")
        #else
        return false
        #endif
    }

    static var databaseFileName: String {
        #if DEBUG
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
        #if DEBUG
        guard isEnabled else { return false }
        let process = ProcessInfo.processInfo
        return process.environment["PINES_UI_TEST_DATABASE_PLAINTEXT"] == "1"
            || process.arguments.contains("--pines-ui-test-plaintext-database")
        #else
        return false
        #endif
    }

    static var storeConfiguration: LocalStoreConfiguration {
        guard isEnabled else { return .init() }
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
