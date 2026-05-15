import Foundation
import SwiftUI
import PinesCore

typealias PinesLiveStore = any ConversationRepository
    & ModelInstallRepository
    & VaultRepository
    & SettingsRepository
    & CloudProviderRepository
    & ModelDownloadRepository
    & AuditEventRepository

final class PinesAppServices: @unchecked Sendable {
    let secretStore: any SecretStore
    let modelCatalog: HuggingFaceModelCatalogService
    let preflightClassifier: ModelPreflightClassifier
    let executionRouter: ExecutionRouter
    let toolRegistry: ToolRegistry
    let toolPolicyGate: ToolPolicyGate
    let redactor: Redactor
    let mlxRuntime: MLXRuntimeBridge
    let liveStore: PinesLiveStore?
    let conversationRepository: (any ConversationRepository)?
    let modelInstallRepository: (any ModelInstallRepository)?
    let vaultRepository: (any VaultRepository)?
    let settingsRepository: (any SettingsRepository)?
    let cloudProviderRepository: (any CloudProviderRepository)?
    let modelDownloadRepository: (any ModelDownloadRepository)?
    let auditRepository: (any AuditEventRepository)?

    init(
        secretStore: any SecretStore = KeychainSecretStore(),
        modelCatalog: HuggingFaceModelCatalogService = HuggingFaceModelCatalogService(),
        preflightClassifier: ModelPreflightClassifier = ModelPreflightClassifier(),
        executionRouter: ExecutionRouter = ExecutionRouter(),
        toolRegistry: ToolRegistry = ToolRegistry(),
        toolPolicyGate: ToolPolicyGate = ToolPolicyGate(),
        redactor: Redactor = Redactor(),
        mlxRuntime: MLXRuntimeBridge = MLXRuntimeBridge(),
        liveStore: PinesLiveStore? = PinesAppServices.makeDefaultStore()
    ) {
        self.secretStore = secretStore
        self.modelCatalog = modelCatalog
        self.preflightClassifier = preflightClassifier
        self.executionRouter = executionRouter
        self.toolRegistry = toolRegistry
        self.toolPolicyGate = toolPolicyGate
        self.redactor = redactor
        self.mlxRuntime = mlxRuntime
        self.liveStore = liveStore
        conversationRepository = liveStore
        modelInstallRepository = liveStore
        vaultRepository = liveStore
        settingsRepository = liveStore
        cloudProviderRepository = liveStore
        modelDownloadRepository = liveStore
        auditRepository = liveStore
    }

    func bootstrap() async {
        try? await toolRegistry.register(CalculatorTool.spec())
        try? await toolRegistry.register(BraveSearchTool.spec(secretStore: secretStore))
        #if canImport(WebKit) && canImport(UIKit)
        let browserRuntime = await MainActor.run { WKWebViewBrowserRuntime() }
        if let observe: ToolSpec<BrowserObserveInput, BrowserObserveOutput> = try? await MainActor.run(body: { try browserRuntime.observeSpec() }) {
            try? await toolRegistry.register(observe)
        }
        if let action: ToolSpec<BrowserActionInput, BrowserActionOutput> = try? await MainActor.run(body: { try browserRuntime.actionSpec() }) {
            try? await toolRegistry.register(action)
        }
        #else
        try? await toolRegistry.register(BuiltInToolSpecs.browserObserveSpec())
        try? await toolRegistry.register(BuiltInToolSpecs.browserActionSpec())
        #endif
    }

    var serviceHealth: [ServiceHealth] {
        [
            ServiceHealth(
                name: "SQLite Store",
                readiness: liveStore == nil ? .unavailable : .ready,
                summary: liveStore == nil ? "GRDB store is unavailable in this build." : "GRDB migrations and repositories are available."
            ),
            ServiceHealth(
                name: "MLX Runtime",
                readiness: mlxRuntime.isLinked ? .ready : .requiresUserAction,
                summary: mlxRuntime.isLinked ? "MLX packages are linked." : "Open with full Xcode to resolve iOS MLX packages."
            ),
            ServiceHealth(
                name: "Tool Registry",
                readiness: .ready,
                summary: "Calculator, web-search, and browser tool specs are registered at boot."
            ),
            ServiceHealth(
                name: "Privacy Boundary",
                readiness: .ready,
                summary: "Cloud execution remains opt-in through agent policy."
            ),
        ]
    }

    var modelLifecycleService: ModelLifecycleService? {
        guard let modelInstallRepository, let modelDownloadRepository else {
            return nil
        }
        return ModelLifecycleService(
            catalog: modelCatalog,
            classifier: preflightClassifier,
            installRepository: modelInstallRepository,
            downloadRepository: modelDownloadRepository,
            auditRepository: auditRepository,
            secretStore: secretStore
        )
    }

    var huggingFaceCredentialService: HuggingFaceCredentialService {
        HuggingFaceCredentialService(secretStore: secretStore, auditRepository: auditRepository)
    }

    var vaultIngestionService: VaultIngestionService? {
        guard let vaultRepository else {
            return nil
        }
        return VaultIngestionService(
            vaultRepository: vaultRepository,
            settingsRepository: settingsRepository,
            inferenceProvider: mlxRuntime,
            auditRepository: auditRepository
        )
    }

    var cloudProviderService: CloudProviderService? {
        guard let cloudProviderRepository else {
            return nil
        }
        return CloudProviderService(
            repository: cloudProviderRepository,
            secretStore: secretStore,
            auditRepository: auditRepository
        )
    }

    var cloudKitSyncService: CloudKitSyncService? {
        guard let conversationRepository, let vaultRepository, let settingsRepository else {
            return nil
        }
        return CloudKitSyncService(
            conversationRepository: conversationRepository,
            vaultRepository: vaultRepository,
            settingsRepository: settingsRepository,
            auditRepository: auditRepository
        )
    }

    private static func makeDefaultStore() -> PinesLiveStore? {
        #if canImport(GRDB)
        return try? GRDBPinesStore()
        #else
        return nil
        #endif
    }
}

private struct PinesAppServicesKey: EnvironmentKey {
    static let defaultValue = PinesAppServices()
}

extension EnvironmentValues {
    var pinesServices: PinesAppServices {
        get { self[PinesAppServicesKey.self] }
        set { self[PinesAppServicesKey.self] = newValue }
    }
}
