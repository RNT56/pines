import Foundation
import SwiftUI
import PinesCore
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(MapKit)
import MapKit
#endif

typealias PinesLiveStore = any ConversationRepository
    & ProjectRepository
    & ModelInstallRepository
    & VaultRepository
    & SettingsRepository
    & CloudProviderRepository
    & ProviderFileRepository
    & ProviderArtifactRepository
    & ProviderCacheRepository
    & ProviderBatchRepository
    & ProviderLiveSessionRepository
    & ProviderStructuredOutputRepository
    & ProviderModelCapabilityRepository
    & ProviderResearchRunRepository
    & MCPServerRepository
    & ModelDownloadRepository
    & AuditEventRepository
    & TurboQuantEvidenceRepository
    & AppDataResetRepository

final class PinesAppServices: @unchecked Sendable {
    let secretStore: any SecretStore
    let secureKeyStore: SecureKeyStore
    let modelCatalog: HuggingFaceModelCatalogService
    let preflightClassifier: ModelPreflightClassifier
    let executionRouter: ExecutionRouter
    let toolRegistry: ToolRegistry
    let toolPolicyGate: ToolPolicyGate
    let agentToolCatalog: any AgentToolCatalog
    let webSearchLocationProvider: DeviceWebSearchLocationProvider
    let redactor: Redactor
    let proEntitlementService: PinesProEntitlementService
    let managedCloudService: PinesManagedCloudService
    let mlxRuntime: MLXRuntimeBridge
    let runtimeMetrics: PinesRuntimeMetrics
    private let explicitAgentRuntimeFactory: (any AgentRuntimeFactory)?
    private let repositoryStateLock = NSLock()
    private var repositoryState: RepositoryState
    private let bootstrapState = PinesAppServiceBootstrapState()

    private struct RepositoryState {
        var liveStore: PinesLiveStore?
        var defaultStoreStartupError: String?
    }

    init(
        secretStore: any SecretStore = KeychainSecretStore(),
        secureKeyStore: SecureKeyStore = SecureKeyStore(),
        modelCatalog: HuggingFaceModelCatalogService = HuggingFaceModelCatalogService(),
        preflightClassifier: ModelPreflightClassifier = ModelPreflightClassifier(),
        executionRouter: ExecutionRouter = ExecutionRouter(),
        toolRegistry: ToolRegistry = ToolRegistry(),
        toolPolicyGate: ToolPolicyGate = ToolPolicyGate(),
        agentRuntimeFactory: (any AgentRuntimeFactory)? = nil,
        agentToolCatalog: (any AgentToolCatalog)? = nil,
        webSearchLocationProvider: DeviceWebSearchLocationProvider = DeviceWebSearchLocationProvider(),
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
        self.secureKeyStore = secureKeyStore
        self.modelCatalog = modelCatalog
        self.preflightClassifier = preflightClassifier
        self.executionRouter = executionRouter
        self.toolRegistry = toolRegistry
        self.toolPolicyGate = toolPolicyGate
        self.explicitAgentRuntimeFactory = agentRuntimeFactory
        self.agentToolCatalog = agentToolCatalog ?? RegistryAgentToolCatalog(
            secretStore: secretStore,
            toolRegistry: toolRegistry
        )
        self.webSearchLocationProvider = webSearchLocationProvider
        self.redactor = redactor
        self.proEntitlementService = PinesProEntitlementService()
        self.managedCloudService = PinesManagedCloudService(secretStore: secretStore)
        self.mlxRuntime = mlxRuntime
        self.runtimeMetrics = runtimeMetrics
        repositoryState = RepositoryState(
            liveStore: resolvedStore,
            defaultStoreStartupError: storeStartupError
        )
    }

    var liveStore: PinesLiveStore? {
        withRepositoryState { $0.liveStore }
    }

    var conversationRepository: (any ConversationRepository)? { liveStore }
    var projectRepository: (any ProjectRepository)? { liveStore }
    var modelInstallRepository: (any ModelInstallRepository)? { liveStore }
    var vaultRepository: (any VaultRepository)? { liveStore }
    var settingsRepository: (any SettingsRepository)? { liveStore }
    var cloudProviderRepository: (any CloudProviderRepository)? { liveStore }
    var providerFileRepository: (any ProviderFileRepository)? { liveStore }
    var providerArtifactRepository: (any ProviderArtifactRepository)? { liveStore }
    var providerCacheRepository: (any ProviderCacheRepository)? { liveStore }
    var providerBatchRepository: (any ProviderBatchRepository)? { liveStore }
    var providerLiveSessionRepository: (any ProviderLiveSessionRepository)? { liveStore }
    var providerStructuredOutputRepository: (any ProviderStructuredOutputRepository)? { liveStore }
    var providerModelCapabilityRepository: (any ProviderModelCapabilityRepository)? { liveStore }
    var providerResearchRunRepository: (any ProviderResearchRunRepository)? { liveStore }
    var mcpServerRepository: (any MCPServerRepository)? { liveStore }
    var modelDownloadRepository: (any ModelDownloadRepository)? { liveStore }
    var auditRepository: (any AuditEventRepository)? { liveStore }
    var turboQuantEvidenceRepository: (any TurboQuantEvidenceRepository)? { liveStore }

    var agentRuntimeFactory: any AgentRuntimeFactory {
        explicitAgentRuntimeFactory ?? DefaultAgentRuntimeFactory(
            toolRegistry: toolRegistry,
            policyGate: toolPolicyGate,
            auditRepository: auditRepository
        )
    }

    var defaultStoreStartupError: String? {
        withRepositoryState { $0.defaultStoreStartupError }
    }

    private func withRepositoryState<Value>(_ body: (RepositoryState) -> Value) -> Value {
        repositoryStateLock.lock()
        defer { repositoryStateLock.unlock() }
        return body(repositoryState)
    }

    private func updateRepositoryState(_ update: (inout RepositoryState) -> Void) {
        repositoryStateLock.lock()
        defer { repositoryStateLock.unlock() }
        update(&repositoryState)
    }

    func prepareForFirstFrame() async {
        runtimeMetrics.start()
    }

    @discardableResult
    func loadDefaultStoreIfNeeded() async -> Bool {
        if liveStore != nil {
            return true
        }
        guard await bootstrapState.markDefaultStoreLoadStarted() else {
            while liveStore == nil && defaultStoreStartupError == nil {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return liveStore != nil
        }

        let runtimeMetrics = runtimeMetrics
        let result = await Task.detached(priority: .userInitiated) {
            Self.makeDefaultStore(runtimeMetrics: runtimeMetrics)
        }.value
        updateRepositoryState { state in
            guard state.liveStore == nil else { return }
            state.liveStore = result.store
            state.defaultStoreStartupError = result.error
        }
        return liveStore != nil
    }

    func bootstrap() async {
        await prepareForFirstFrame()
        guard await bootstrapState.markToolBootstrapStarted() else { return }

        await registerBuiltInTool(CalculatorTool.name) {
            try CalculatorTool.spec()
        }
        await registerBuiltInTool(TimeNowTool.name) {
            try TimeNowTool.spec()
        }
        await registerBuiltInTool(DateCalculateTool.name) {
            try DateCalculateTool.spec()
        }
        await registerBuiltInTool("web.search") {
            try BraveSearchTool.spec(secretStore: secretStore)
        }
        await registerBuiltInTool(WebFetchTool.name) {
            try WebFetchTool.spec()
        }
        await registerBuiltInTool(AttachmentReadTool.name) {
            try AttachmentReadTool.spec { attachmentID in
                AgentToolExecutionContext.current.attachmentsByID[attachmentID]
            }
        }
        if let vaultRepository {
            let embeddingService = vaultEmbeddingService
            await registerBuiltInTool(VaultSearchTool.name) {
                try VaultSearchTool.spec(allowedDocumentIDs: {
                    AgentToolExecutionContext.current.allowedVaultDocumentIDs
                }) { query, limit in
                    var profile: VaultEmbeddingProfile?
                    var queryEmbedding: [Float]?
                    if let activeProfile = try? await vaultRepository.activeEmbeddingProfile(),
                       activeProfile.kind == .localMLX,
                       activeProfile.canUseWithoutPrompt {
                        profile = activeProfile
                        queryEmbedding = try? await embeddingService?.embedQuery(query, profile: activeProfile)
                    }
                    let results = try await vaultRepository.search(
                        query: query,
                        embedding: queryEmbedding,
                        embeddingModelID: profile?.modelID,
                        profileID: queryEmbedding == nil ? nil : profile?.id,
                        limit: limit
                    )
                    return VaultSearchTool.output(
                        query: query,
                        searchMode: queryEmbedding == nil ? "lexical" : "semantic",
                        results: results
                    )
                }
            }
            await registerBuiltInTool(VaultReadTool.name) {
                try VaultReadTool.spec(repository: vaultRepository) {
                    AgentToolExecutionContext.current.allowedVaultDocumentIDs
                }
            }
        }
        if let conversationRepository {
            await registerBuiltInTool(ConversationSearchTool.name) {
                try ConversationSearchTool.spec(repository: conversationRepository) {
                    AgentToolExecutionContext.current.allowsConversationSearch
                }
            }
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

    func handleThermalPressure() async {
        runtimeMetrics.recordThermalPressure(mlxRuntime.runtimeDiagnostics.memoryCounters)
        await mlxRuntime.handleThermalPressure()
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
                name: "Managed Pro Cloud",
                readiness: managedCloudService.isConfigured ? .ready : .unavailable,
                summary: managedCloudService.isConfigured
                    ? "Gateway routing, quotas, and managed provider adapters are available after Pro opt-in."
                    : "No managed cloud gateway URL is configured; local and BYOK paths remain available."
            ),
            ServiceHealth(
                name: "StoreKit Pro",
                readiness: proEntitlementService.isConfigured ? .ready : .unavailable,
                summary: proEntitlementService.isConfigured
                    ? "Configured product IDs can be observed and validated with the managed gateway."
                    : "No Pro product IDs are configured in this build."
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
            secretStore: secretStore,
            resourcePolicy: mlxRuntime.modelDiscoveryResourcePolicy
        )
    }

    var huggingFaceCredentialService: HuggingFaceCredentialService {
        HuggingFaceCredentialService(secretStore: secretStore, auditRepository: auditRepository)
    }

    var encryptedBlobStore: EncryptedBlobStore {
        EncryptedBlobStore(secureKeyStore: secureKeyStore)
    }

    var securityResetCoordinator: SecurityResetCoordinator {
        SecurityResetCoordinator(
            settingsRepository: settingsRepository,
            cloudProviderRepository: cloudProviderRepository,
            mcpServerRepository: mcpServerRepository,
            secretStore: secretStore,
            auditRepository: auditRepository,
            redactor: redactor
        )
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
            encryptedBlobStore: encryptedBlobStore,
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

    var openAIProviderLifecycleRepositories: OpenAIProviderLifecycleRepositories {
        OpenAIProviderLifecycleRepositories(
            files: providerFileRepository,
            artifacts: providerArtifactRepository,
            caches: providerCacheRepository,
            batches: providerBatchRepository,
            liveSessions: providerLiveSessionRepository,
            structuredOutputs: providerStructuredOutputRepository,
            modelCapabilities: providerModelCapabilityRepository,
            researchRuns: providerResearchRunRepository,
            audit: auditRepository
        )
    }

    var geminiProviderLifecycleRepositories: GeminiProviderLifecycleRepositories {
        GeminiProviderLifecycleRepositories(
            files: providerFileRepository,
            artifacts: providerArtifactRepository,
            caches: providerCacheRepository,
            batches: providerBatchRepository,
            liveSessions: providerLiveSessionRepository,
            structuredOutputs: providerStructuredOutputRepository,
            modelCapabilities: providerModelCapabilityRepository,
            researchRuns: providerResearchRunRepository,
            audit: auditRepository
        )
    }

    var anthropicProviderLifecycleRepositories: AnthropicProviderLifecycleRepositories {
        AnthropicProviderLifecycleRepositories(
            files: providerFileRepository,
            artifacts: providerArtifactRepository,
            caches: providerCacheRepository,
            batches: providerBatchRepository,
            liveSessions: providerLiveSessionRepository,
            structuredOutputs: providerStructuredOutputRepository,
            modelCapabilities: providerModelCapabilityRepository,
            researchRuns: providerResearchRunRepository,
            audit: auditRepository
        )
    }

    func geminiLifecycleCoordinator(for provider: CloudProviderConfiguration) throws -> GeminiProviderLifecycleCoordinator {
        guard let cloudProviderService else {
            throw InferenceError.providerUnavailable(provider.id)
        }
        return GeminiProviderLifecycleCoordinator(
            service: cloudProviderService.geminiProviderService(for: provider),
            repositories: geminiProviderLifecycleRepositories
        )
    }

    func anthropicLifecycleCoordinator(for provider: CloudProviderConfiguration) throws -> AnthropicProviderLifecycleCoordinator {
        guard let cloudProviderService else {
            throw InferenceError.providerUnavailable(provider.id)
        }
        return cloudProviderService.anthropicLifecycleCoordinator(
            for: provider,
            repositories: anthropicProviderLifecycleRepositories
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
            secureKeyStore: secureKeyStore,
            auditRepository: auditRepository
        )
    }

    private static func makeDefaultStore(runtimeMetrics: PinesRuntimeMetrics) -> (store: PinesLiveStore?, error: String?) {
        #if canImport(GRDB)
        let startedAt = Date()
        do {
            if PinesUITestLaunchConfiguration.resetsStore {
                try resetUITestStore(fileName: PinesUITestLaunchConfiguration.databaseFileName)
            }
            let store = try GRDBPinesStore(
                configuration: PinesUITestLaunchConfiguration.storeConfiguration,
                runtimeMetrics: runtimeMetrics
            )
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

    private static func resetUITestStore(fileName: String) throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "Pines", directoryHint: .isDirectory)
        let databaseURL = directory.appending(path: fileName)
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.removeItem(at: url)
        }
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

struct DeviceWebSearchLocationProvider: Sendable {
    func options() async -> CloudWebSearchOptions {
        CloudWebSearchOptions(userLocation: await approximateUserLocation())
    }

    private func approximateUserLocation() async -> CloudWebSearchUserLocation? {
        var fallback = localeTimeZoneLocation()
        #if canImport(CoreLocation)
        let locationServicesEnabled = await MainActor.run { CLLocationManager.locationServicesEnabled() }
        guard locationServicesEnabled else {
            return fallback.isEmpty ? nil : fallback
        }
        guard let location = await requestLocation() else {
            return fallback.isEmpty ? nil : fallback
        }
        guard let resolvedLocation = await resolvedUserLocation(for: location) else {
            return fallback.isEmpty ? nil : fallback
        }
        fallback.city = resolvedLocation.city ?? fallback.city
        fallback.region = resolvedLocation.region ?? fallback.region
        fallback.country = resolvedLocation.country ?? fallback.country
        return fallback.isEmpty ? nil : fallback
        #else
        return fallback.isEmpty ? nil : fallback
        #endif
    }

    private func localeTimeZoneLocation() -> CloudWebSearchUserLocation {
        CloudWebSearchUserLocation(
            country: Locale.current.region?.identifier,
            timezone: TimeZone.current.identifier
        )
    }

    #if canImport(CoreLocation)
    @MainActor
    private func requestLocation() async -> CLLocation? {
        let manager = CLLocationManager()
        let delegate = OneShotLocationDelegate()
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers

        let status = manager.authorizationStatus
        let authorizedStatus: CLAuthorizationStatus
        if status == .notDetermined {
            authorizedStatus = await delegate.requestAuthorization(with: manager)
        } else {
            authorizedStatus = status
        }
        guard authorizedStatus == .authorizedWhenInUse || authorizedStatus == .authorizedAlways else {
            return nil
        }
        return await delegate.requestLocation(with: manager)
    }

    private func resolvedUserLocation(for location: CLLocation) async -> CloudWebSearchUserLocation? {
        #if canImport(MapKit)
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
            return await mapKitUserLocation(for: location)
        }
        #endif
        return await coreLocationUserLocation(for: location)
    }

    #if canImport(MapKit)
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    private func mapKitUserLocation(for location: CLLocation) async -> CloudWebSearchUserLocation? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let mapItem = try? await request.mapItems.first,
              let address = mapItem.addressRepresentations else {
            return nil
        }
        return CloudWebSearchUserLocation(
            city: address.cityName,
            country: address.region?.identifier
        )
    }
    #endif

    private func coreLocationUserLocation(for location: CLLocation) async -> CloudWebSearchUserLocation? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        return CloudWebSearchUserLocation(
            city: placemark.locality ?? placemark.subLocality,
            region: placemark.administrativeArea,
            country: placemark.isoCountryCode
        )
    }

    @MainActor
    private final class OneShotLocationDelegate: NSObject, CLLocationManagerDelegate {
        private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
        private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

        func requestAuthorization(with manager: CLLocationManager) async -> CLAuthorizationStatus {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        func requestLocation(with manager: CLLocationManager) async -> CLLocation? {
            await withCheckedContinuation { continuation in
                locationContinuation = continuation
                manager.requestLocation()
            }
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            Task { @MainActor in
                authorizationContinuation?.resume(returning: status)
                authorizationContinuation = nil
            }
        }

        nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            let location = locations.first
            Task { @MainActor in
                locationContinuation?.resume(returning: location)
                locationContinuation = nil
            }
        }

        nonisolated func locationManager(_: CLLocationManager, didFailWithError _: any Error) {
            Task { @MainActor in
                locationContinuation?.resume(returning: nil)
                locationContinuation = nil
            }
        }
    }
    #endif
}

private actor PinesAppServiceBootstrapState {
    private var didBootstrapTools = false
    private var didStartDefaultStoreLoad = false

    func markToolBootstrapStarted() -> Bool {
        guard !didBootstrapTools else { return false }
        didBootstrapTools = true
        return true
    }

    func markDefaultStoreLoadStarted() -> Bool {
        guard !didStartDefaultStoreLoad else { return false }
        didStartDefaultStoreLoad = true
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
