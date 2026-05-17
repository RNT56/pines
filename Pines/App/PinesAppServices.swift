import Foundation
import SwiftUI
import PinesCore

typealias PinesLiveStore = any ConversationRepository
    & ModelInstallRepository
    & VaultRepository
    & SettingsRepository
    & CloudProviderRepository
    & MCPServerRepository
    & ModelDownloadRepository
    & AuditEventRepository

final class PinesAppServices: Sendable {
    let secretStore: any SecretStore
    let modelCatalog: HuggingFaceModelCatalogService
    let preflightClassifier: ModelPreflightClassifier
    let executionRouter: ExecutionRouter
    let toolRegistry: ToolRegistry
    let toolPolicyGate: ToolPolicyGate
    let agentRuntimeFactory: any AgentRuntimeFactory
    let agentToolCatalog: any AgentToolCatalog
    let redactor: Redactor
    let mlxRuntime: MLXRuntimeBridge
    let runtimeMetrics: PinesRuntimeMetrics
    let liveStore: PinesLiveStore?
    let conversationRepository: (any ConversationRepository)?
    let modelInstallRepository: (any ModelInstallRepository)?
    let vaultRepository: (any VaultRepository)?
    let settingsRepository: (any SettingsRepository)?
    let cloudProviderRepository: (any CloudProviderRepository)?
    let mcpServerRepository: (any MCPServerRepository)?
    let modelDownloadRepository: (any ModelDownloadRepository)?
    let auditRepository: (any AuditEventRepository)?
    private let defaultStoreStartupError: String?
    private let bootstrapState = PinesAppServiceBootstrapState()

    init(
        secretStore: any SecretStore = KeychainSecretStore(),
        modelCatalog: HuggingFaceModelCatalogService = HuggingFaceModelCatalogService(),
        preflightClassifier: ModelPreflightClassifier = ModelPreflightClassifier(),
        executionRouter: ExecutionRouter = ExecutionRouter(),
        toolRegistry: ToolRegistry = ToolRegistry(),
        toolPolicyGate: ToolPolicyGate = ToolPolicyGate(),
        agentRuntimeFactory: (any AgentRuntimeFactory)? = nil,
        agentToolCatalog: (any AgentToolCatalog)? = nil,
        redactor: Redactor = Redactor(),
        mlxRuntime: MLXRuntimeBridge = MLXRuntimeBridge(),
        runtimeMetrics: PinesRuntimeMetrics = .shared,
        liveStore: PinesLiveStore? = nil,
        loadsDefaultStore: Bool = true
    ) {
        let resolvedStore: PinesLiveStore?
        let storeStartupError: String?
        if let liveStore {
            resolvedStore = liveStore
            storeStartupError = nil
        } else if loadsDefaultStore {
            let defaultStore = PinesAppServices.makeDefaultStore(runtimeMetrics: runtimeMetrics)
            resolvedStore = defaultStore.store
            storeStartupError = defaultStore.error
        } else {
            resolvedStore = nil
            storeStartupError = nil
        }
        self.secretStore = secretStore
        self.modelCatalog = modelCatalog
        self.preflightClassifier = preflightClassifier
        self.executionRouter = executionRouter
        self.toolRegistry = toolRegistry
        self.toolPolicyGate = toolPolicyGate
        self.agentRuntimeFactory = agentRuntimeFactory ?? DefaultAgentRuntimeFactory(
            toolRegistry: toolRegistry,
            policyGate: toolPolicyGate,
            auditRepository: resolvedStore
        )
        self.agentToolCatalog = agentToolCatalog ?? RegistryAgentToolCatalog(
            secretStore: secretStore,
            toolRegistry: toolRegistry
        )
        self.redactor = redactor
        self.mlxRuntime = mlxRuntime
        self.runtimeMetrics = runtimeMetrics
        self.liveStore = resolvedStore
        defaultStoreStartupError = storeStartupError
        conversationRepository = resolvedStore
        modelInstallRepository = resolvedStore
        vaultRepository = resolvedStore
        settingsRepository = resolvedStore
        cloudProviderRepository = resolvedStore
        mcpServerRepository = resolvedStore
        modelDownloadRepository = resolvedStore
        auditRepository = resolvedStore
    }

    func prepareForFirstFrame() async {
        runtimeMetrics.start()
    }

    func bootstrap() async {
        await prepareForFirstFrame()
        guard await bootstrapState.markToolBootstrapStarted() else { return }

        await registerBuiltInTool(CalculatorTool.name) {
            try CalculatorTool.spec()
        }
        await registerBuiltInTool("web.search") {
            try BraveSearchTool.spec(secretStore: secretStore)
        }
        #if canImport(WebKit) && canImport(UIKit)
        let browserRuntime = await MainActor.run { WKWebViewBrowserRuntime() }
        do {
            let observe: ToolSpec<BrowserObserveInput, BrowserObserveOutput> = try await MainActor.run {
                try browserRuntime.observeSpec()
            }
            await registerBuiltInTool(observe, name: "browser.observe")
        } catch {
            await recordBootstrapFailure(component: "browser.observe", error: error)
        }
        do {
            let action: ToolSpec<BrowserActionInput, BrowserActionOutput> = try await MainActor.run {
                try browserRuntime.actionSpec()
            }
            await registerBuiltInTool(action, name: "browser.action")
        } catch {
            await recordBootstrapFailure(component: "browser.action", error: error)
        }
        #else
        await registerBuiltInTool("browser.observe") {
            try BuiltInToolSpecs.browserObserveSpec()
        }
        await registerBuiltInTool("browser.action") {
            try BuiltInToolSpecs.browserActionSpec()
        }
        #endif
    }

    func handleMemoryPressure() async {
        runtimeMetrics.recordMemoryPressure(mlxRuntime.runtimeDiagnostics.memoryCounters)
        await mlxRuntime.handleMemoryPressure()
    }

    var serviceHealth: [ServiceHealth] {
        [
            ServiceHealth(
                name: "SQLite Store",
                readiness: liveStore == nil ? .unavailable : .ready,
                summary: liveStore == nil
                    ? (defaultStoreStartupError ?? "GRDB store is unavailable in this build.")
                    : "GRDB migrations and repositories are available."
            ),
            ServiceHealth(
                name: "MLX Runtime",
                readiness: mlxRuntime.isLinked ? .ready : .requiresUserAction,
                summary: mlxRuntime.isLinked ? "MLX packages are linked." : "Open with full Xcode to resolve iOS MLX packages."
            ),
            ServiceHealth(
                name: "Tool Registry",
                readiness: .ready,
                summary: "Built-in tools register after first frame; enabled MCP tools start when Tools or MCP context needs them."
            ),
            ServiceHealth(
                name: "MCP Servers",
                readiness: mcpServerRepository == nil ? .unavailable : .ready,
                summary: mcpServerRepository == nil ? "MCP persistence is unavailable in this build." : "Remote Streamable HTTP MCP servers can be connected from Settings."
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
            embeddingService: vaultEmbeddingService,
            auditRepository: auditRepository
        )
    }

    var vaultEmbeddingService: VaultEmbeddingService? {
        guard let vaultRepository else {
            return nil
        }
        return VaultEmbeddingService(
            vaultRepository: vaultRepository,
            modelInstallRepository: modelInstallRepository,
            cloudProviderRepository: cloudProviderRepository,
            secretStore: secretStore,
            mlxRuntime: mlxRuntime,
            auditRepository: auditRepository
        )
    }

    var vaultRetrievalService: VaultRetrievalService? {
        guard let vaultRepository else {
            return nil
        }
        return VaultRetrievalService(
            vaultRepository: vaultRepository,
            embeddingService: vaultEmbeddingService,
            runtimeMetrics: runtimeMetrics
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

    var mcpServerService: MCPServerService? {
        guard let mcpServerRepository else {
            return nil
        }
        return MCPServerService(
            repository: mcpServerRepository,
            toolRegistry: toolRegistry,
            secretStore: secretStore,
            auditRepository: auditRepository
        )
    }

    var cloudKitSyncService: CloudKitSyncService? {
        guard
            CloudKitSyncService.hasRequiredEntitlements(),
            let conversationRepository,
            let vaultRepository,
            let settingsRepository
        else {
            return nil
        }
        return CloudKitSyncService(
            conversationRepository: conversationRepository,
            vaultRepository: vaultRepository,
            settingsRepository: settingsRepository,
            auditRepository: auditRepository
        )
    }

    private static func makeDefaultStore(runtimeMetrics: PinesRuntimeMetrics) -> (store: PinesLiveStore?, error: String?) {
        #if canImport(GRDB)
        let startedAt = Date()
        do {
            let store = try GRDBPinesStore(runtimeMetrics: runtimeMetrics)
            runtimeMetrics.recordStartupPhase("store_init", elapsedSeconds: Date().timeIntervalSince(startedAt))
            return (store, nil)
        } catch {
            runtimeMetrics.recordStartupFailure("store_init", error: error)
            return (nil, "GRDB store failed to initialize: \(error.localizedDescription)")
        }
        #else
        return (nil, "GRDB store is unavailable in this build.")
        #endif
    }

    private func registerBuiltInTool<Input: ToolInput, Output: ToolOutput>(
        _ name: String,
        makeSpec: () throws -> ToolSpec<Input, Output>
    ) async {
        do {
            try await toolRegistry.register(makeSpec())
        } catch {
            await recordBootstrapFailure(component: name, error: error)
        }
    }

    private func registerBuiltInTool<Input: ToolInput, Output: ToolOutput>(
        _ spec: ToolSpec<Input, Output>,
        name: String
    ) async {
        do {
            try await toolRegistry.register(spec)
        } catch {
            await recordBootstrapFailure(component: name, error: error)
        }
    }

    private func recordBootstrapFailure(component: String, error: any Error) async {
        runtimeMetrics.recordStartupFailure("tool_bootstrap:\(component)", error: error)
        do {
            try await auditRepository?.append(
                AuditEvent(
                    category: .tool,
                    summary: "Tool bootstrap failed for \(component).",
                    redactedPayload: redactor.redact(error.localizedDescription),
                    toolName: component
                )
            )
        } catch {
            runtimeMetrics.recordStartupFailure("tool_bootstrap_audit:\(component)", error: error)
        }
    }
}

private actor PinesAppServiceBootstrapState {
    private var didBootstrapTools = false

    func markToolBootstrapStarted() -> Bool {
        guard !didBootstrapTools else { return false }
        didBootstrapTools = true
        return true
    }
}

private struct PinesAppServicesKey: EnvironmentKey {
    static let defaultValue = PinesAppServices(loadsDefaultStore: false)
}

extension EnvironmentValues {
    var pinesServices: PinesAppServices {
        get { self[PinesAppServicesKey.self] }
        set { self[PinesAppServicesKey.self] = newValue }
    }
}
