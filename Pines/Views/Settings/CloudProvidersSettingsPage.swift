import SwiftUI
import PinesCore

struct CloudProvidersSettingsPage: View {
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @State private var editorContext: CloudProviderEditorContext?
    @State private var providerPendingDeletion: CloudProviderConfiguration?
    @State private var showsOpenRouterSettings = false

    var body: some View {
        PinesSettingsPage(introduction: "Cloud use is always explicit. Choose Pro Cloud or add providers whose API keys stay in this device's keychain.") {
            managedCloudGroup
            providersGroup
        }
        .sheet(item: $editorContext) { context in
            CloudProviderEditorSheet(provider: context.provider)
                .environmentObject(appModel)
                .environmentObject(settingsState)
        }
        .sheet(isPresented: $showsOpenRouterSettings) {
            OpenRouterSettingsSheet()
                .environmentObject(appModel)
                .environmentObject(settingsState)
        }
        .confirmationDialog(
            "Delete cloud provider?",
            isPresented: Binding(
                get: { providerPendingDeletion != nil },
                set: { if !$0 { providerPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete provider", role: .destructive) {
                guard let provider = providerPendingDeletion else { return }
                providerPendingDeletion = nil
                Task { await appModel.deleteCloudProvider(provider, services: services) }
            }
            Button("Cancel", role: .cancel) { providerPendingDeletion = nil }
        } message: {
            Text("This removes the provider configuration and its key. Existing chats and local files remain on this device.")
        }
    }

    private var managedCloudGroup: some View {
        let managedCloudReady = settingsState.proEntitlementStatus.enablesManagedCloud
            && services.managedCloudService.isConfigured
        return PinesSettingsGroup("Pro Cloud") {
            PinesSettingsValueRow(
                "Availability",
                value: proCloudStatus,
                detail: cloudIntelligenceSummary,
                systemImage: "sparkles",
                valueTone: managedCloudReady ? .success : .neutral
            )

            if managedCloudReady {
                PinesSettingsDivider()

                PinesSettingsControlRow(
                    "Use Pro Cloud",
                    detail: "Allow selected chats and supported features to use Pines' managed cloud service.",
                    systemImage: "cloud.fill"
                ) {
                    Toggle("Use Pro Cloud", isOn: Binding(
                        get: {
                            settingsState.proEntitlementStatus.enablesManagedCloud
                                && settingsState.managedCloudConsent == .optedIn
                                && settingsState.cloudAccessMode.usesManagedCloud
                        },
                        set: { enabled in
                            if enabled {
                                settingsState.managedCloudConsent = .optedIn
                                settingsState.cloudAccessMode = .managedPro
                            } else {
                                settingsState.managedCloudConsent = .optedOut
                                if settingsState.cloudAccessMode.usesManagedCloud {
                                    settingsState.cloudAccessMode = .byok
                                }
                            }
                            saveSettings()
                        }
                    ))
                    .labelsHidden()
                }

                PinesSettingsDivider()

                PinesSettingsControlRow(
                    "Use my providers as fallback",
                    detail: "When Pro Cloud cannot handle a request, allow an enabled provider below to try it.",
                    systemImage: "arrow.triangle.branch"
                ) {
                    Toggle("Use my providers as fallback", isOn: Binding(
                        get: { settingsState.cloudAccessMode == .managedProWithBYOKOverride },
                        set: { enabled in
                            settingsState.cloudAccessMode = enabled ? .managedProWithBYOKOverride : .managedPro
                            saveSettings()
                        }
                    ))
                    .labelsHidden()
                    .disabled(!settingsState.cloudAccessMode.usesManagedCloud || settingsState.cloudProviders.isEmpty)
                }
            }
        }
    }

    private var providersGroup: some View {
        PinesSettingsGroup("My providers", detail: "Keys are stored in the keychain and are never shown again after saving.") {
            if settingsState.cloudProviders.isEmpty {
                PinesSettingsValueRow(
                    "No providers added",
                    value: "Local only",
                    detail: "Add a provider when you want to use your own API account.",
                    systemImage: "cloud.slash"
                )
            } else {
                ForEach(Array(settingsState.cloudProviders.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { PinesSettingsDivider() }
                    providerRow(provider)
                }
            }

            PinesSettingsDivider()

            PinesSettingsActionRow(
                title: "Add provider",
                detail: "OpenAI, Anthropic, Gemini, OpenRouter, Voyage AI, or a compatible endpoint.",
                systemImage: "plus.circle",
                action: { editorContext = CloudProviderEditorContext(provider: nil) }
            )

            if settingsState.cloudProviders.contains(where: { $0.kind == .openRouter }) {
                PinesSettingsDivider()
                PinesSettingsActionRow(
                    title: "OpenRouter routing & usage",
                    detail: "Set privacy constraints, provider preferences, web search routing, and review reported spend.",
                    systemImage: "arrow.triangle.branch",
                    action: { showsOpenRouterSettings = true }
                )
                .accessibilityIdentifier("pines.settings.openrouter.routing")
            }
        }
    }

    private func providerRow(_ provider: CloudProviderConfiguration) -> some View {
        let validating = settingsState.validatingCloudProviderIDs.contains(provider.id)
        return VStack(alignment: .leading, spacing: theme.spacing.medium) {
            HStack(alignment: .top, spacing: theme.spacing.small) {
                Image(systemName: provider.kind.settingsSystemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 34, height: 34)
                    .background(theme.colors.accentSoft, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(provider.displayName)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    Text(providerSummary(provider))
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: theme.spacing.small)
                PinesStatusChip(status: validating ? .running : provider.validationStatus.settingsCloudStatus, compact: true)
            }

            if let error = provider.lastValidationError, !error.isEmpty {
                Text(error)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: theme.spacing.small) {
                Toggle("Use for agents", isOn: Binding(
                    get: { provider.enabledForAgents },
                    set: { enabled in
                        Task {
                            await appModel.setCloudProviderEnabled(
                                provider,
                                enabled: enabled,
                                services: services
                            )
                        }
                    }
                ))
                .disabled(provider.kind == .voyageAI)

                Spacer(minLength: theme.spacing.small)

                Menu {
                    Button("Edit", systemImage: "pencil") {
                        editorContext = CloudProviderEditorContext(provider: provider)
                    }
                    Button("Validate", systemImage: "checkmark.seal") {
                        Task { await appModel.validateCloudProvider(provider, services: services) }
                    }
                    .disabled(validating)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        providerPendingDeletion = provider
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Manage \(provider.displayName)")
                .pinesButtonStyle(.icon)
            }
        }
        .padding(theme.spacing.medium)
    }

    private func providerSummary(_ provider: CloudProviderConfiguration) -> String {
        let host = provider.baseURL.host ?? provider.baseURL.absoluteString
        if let model = provider.defaultModelID {
            return "\(provider.kind.settingsTitle) · \(host) · \(compactModelName(model.rawValue))"
        }
        return "\(provider.kind.settingsTitle) · \(host)"
    }

    private func compactModelName(_ rawValue: String) -> String {
        (rawValue.split(separator: "/").last.map(String.init) ?? rawValue)
            .replacingOccurrences(of: "_", with: " ")
    }

    private var proCloudStatus: String {
        guard services.managedCloudService.isConfigured else { return "Unavailable" }
        switch settingsState.proEntitlementStatus {
        case .inactive: return "Pro inactive"
        case .active: return settingsState.cloudAccessMode.usesManagedCloud ? "On" : "Available"
        case .expired: return "Expired"
        case .billingRetry: return "Billing retry"
        case .revoked: return "Revoked"
        }
    }

    private var cloudIntelligenceSummary: String {
        if !services.managedCloudService.isConfigured {
            return "Managed cloud is not included in this build. Local models and providers below still work."
        }
        if !settingsState.proEntitlementStatus.enablesManagedCloud {
            return "A current Pro entitlement is required before managed cloud can be enabled."
        }
        return settingsState.cloudAccessMode.usesManagedCloud
            ? "Managed cloud may be used for routes you explicitly allow."
            : "Managed cloud is off. No managed cloud call will be made."
    }

    private func saveSettings() {
        Task { await appModel.saveSettings(services: services) }
    }
}

private struct CloudProviderEditorContext: Identifiable {
    let id = UUID()
    let provider: CloudProviderConfiguration?
}

private struct CloudProviderEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    let provider: CloudProviderConfiguration?
    @State private var kind: CloudProviderKind
    @State private var displayName: String
    @State private var baseURL: String
    @State private var apiKey = ""
    @State private var enabledForAgents: Bool
    @State private var showsEndpoint = false
    @State private var saveError: String?

    init(provider: CloudProviderConfiguration?) {
        self.provider = provider
        let initialKind = provider?.kind ?? .openAI
        _kind = State(initialValue: initialKind)
        _displayName = State(initialValue: provider?.displayName ?? initialKind.settingsTitle)
        _baseURL = State(initialValue: provider?.baseURL.absoluteString ?? initialKind.settingsDefaultBaseURL)
        _enabledForAgents = State(initialValue: provider?.enabledForAgents ?? true)
    }

    var body: some View {
        NavigationStack {
            PinesSettingsPage(introduction: provider == nil
                ? "Add an API provider. Pines stores its key in the device keychain and validates the connection after saving."
                : "Update the provider without revealing its saved key. Paste a new key only when you want to replace it."
            ) {
                PinesSettingsGroup("Provider") {
                    PinesSettingsControlRow("Service", systemImage: "cloud") {
                        Picker("Service", selection: $kind) {
                            ForEach(CloudProviderKind.allCases, id: \.self) { kind in
                                Text(kind.settingsTitle).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(provider != nil)
                        .onChange(of: kind) { oldKind, newKind in
                            guard provider == nil else { return }
                            if displayName == oldKind.settingsTitle {
                                displayName = newKind.settingsTitle
                            }
                            baseURL = newKind.settingsDefaultBaseURL
                        }
                    }

                    PinesSettingsDivider()

                    TextField("Display name", text: $displayName)
                        .pinesFieldChrome()
                        .padding(theme.spacing.medium)

                    PinesSettingsDivider()

                    SecureField(provider == nil ? "API key" : "New API key (optional)", text: $apiKey)
                        .textContentType(.password)
                        .pinesFieldChrome()
                        .padding(theme.spacing.medium)

                    PinesSettingsDivider()

                    PinesSettingsControlRow(
                        "Use for agents",
                        detail: kind == .voyageAI ? "Voyage AI is used for embeddings and reranking instead of agent chats." : "Make this provider available when cloud routing is allowed.",
                        systemImage: "bolt"
                    ) {
                        Toggle("Use for agents", isOn: $enabledForAgents)
                            .labelsHidden()
                            .disabled(kind == .voyageAI)
                    }

                    PinesSettingsDivider()

                    DisclosureGroup(isExpanded: $showsEndpoint) {
                        TextField("Base URL", text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .pinesFieldChrome()
                            .padding(.top, theme.spacing.medium)
                    } label: {
                        Label("Endpoint", systemImage: "network")
                            .font(theme.typography.callout.weight(.semibold))
                    }
                    .padding(theme.spacing.medium)
                }

                if let saveError {
                    PinesSettingsNotice(
                        title: "Provider was not saved",
                        detail: saveError,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
            }
            .navigationTitle(provider == nil ? "Add Provider" : "Edit Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(settingsState.isSavingCloudProvider ? "Saving…" : "Save") {
                        saveProvider()
                    }
                    .disabled(
                        settingsState.isSavingCloudProvider
                            || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }

    private func saveProvider() {
        Task {
            saveError = nil
            let saved = await appModel.saveCloudProvider(
                providerID: provider?.id,
                kind: kind,
                displayName: displayName,
                baseURLString: baseURL,
                apiKey: apiKey,
                enabledForAgents: enabledForAgents,
                services: services
            )
            if saved {
                dismiss()
            } else {
                saveError = appModel.serviceError ?? "Check the provider details and try again."
            }
        }
    }
}

private struct OpenRouterSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @State private var orderText: String
    @State private var onlyText: String
    @State private var ignoreText: String
    @State private var allowFallbacks: Bool
    @State private var requireParameters: Bool
    @State private var deniesDataCollection: Bool
    @State private var zeroDataRetention: Bool
    @State private var sort: OpenRouterProviderSort
    @State private var webSearchEngine: OpenRouterWebSearchEngine
    @State private var spendWindow: OpenRouterSpendWindow
    @State private var showsAdvancedRouting = false

    init() {
        _orderText = State(initialValue: "")
        _onlyText = State(initialValue: "")
        _ignoreText = State(initialValue: "")
        _allowFallbacks = State(initialValue: true)
        _requireParameters = State(initialValue: false)
        _deniesDataCollection = State(initialValue: false)
        _zeroDataRetention = State(initialValue: false)
        _sort = State(initialValue: .automatic)
        _webSearchEngine = State(initialValue: .automatic)
        _spendWindow = State(initialValue: .month)
    }

    var body: some View {
        NavigationStack {
            PinesSettingsPage(introduction: "These rules apply to OpenRouter chats. Changes stay in this draft until you tap Save.") {
                PinesSettingsGroup("Routing defaults") {
                    PinesSettingsControlRow(
                        "Optimize for",
                        detail: orderSlugs.isEmpty ? "Choose how OpenRouter selects among eligible providers." : "Custom provider order takes priority.",
                        systemImage: "arrow.up.arrow.down"
                    ) {
                        Picker("Optimize for", selection: $sort) {
                            ForEach(OpenRouterProviderSort.allCases, id: \.self) { value in
                                Text(value.settingsTitle).tag(value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(!orderSlugs.isEmpty)
                    }

                    PinesSettingsDivider()

                    PinesSettingsControlRow(
                        "Web search engine",
                        detail: "Auto prefers provider-native search and uses OpenRouter's fallback when needed.",
                        systemImage: "globe"
                    ) {
                        Picker("Web search engine", selection: $webSearchEngine) {
                            ForEach(OpenRouterWebSearchEngine.allCases, id: \.self) { engine in
                                Text(engine.settingsTitle).tag(engine)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    PinesSettingsDivider()

                    PinesSettingsControlRow(
                        "Allow fallback providers",
                        detail: "Let OpenRouter try another eligible provider when the first choice cannot serve the request.",
                        systemImage: "arrow.triangle.branch"
                    ) {
                        Toggle("Allow fallback providers", isOn: $allowFallbacks).labelsHidden()
                    }

                    PinesSettingsDivider()

                    PinesSettingsControlRow(
                        "Deny data collection",
                        detail: "Only use providers that report a compatible data-collection policy.",
                        systemImage: "hand.raised"
                    ) {
                        Toggle("Deny data collection", isOn: $deniesDataCollection).labelsHidden()
                    }

                    PinesSettingsDivider()

                    PinesSettingsControlRow(
                        "Require zero data retention",
                        detail: "Restrict routing to providers that support zero-data-retention requests.",
                        systemImage: "lock.shield"
                    ) {
                        Toggle("Require zero data retention", isOn: $zeroDataRetention).labelsHidden()
                    }

                    PinesSettingsDivider()

                    DisclosureGroup(isExpanded: $showsAdvancedRouting) {
                        VStack(alignment: .leading, spacing: theme.spacing.medium) {
                            TextField("Preferred order, comma separated", text: $orderText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .pinesFieldChrome()
                            TextField("Only allow these providers", text: $onlyText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .pinesFieldChrome()
                            TextField("Ignore these providers", text: $ignoreText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .pinesFieldChrome()
                            Toggle("Require every request parameter", isOn: $requireParameters)
                            Text("Provider slugs are normalized when saved. Requiring parameters can reduce availability, but Pines already enforces it when tools or structured output require support.")
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, theme.spacing.medium)
                    } label: {
                        Label("Provider allowlists & ordering", systemImage: "list.bullet")
                            .font(theme.typography.callout.weight(.semibold))
                    }
                    .padding(theme.spacing.medium)
                }

                spendGroup
            }
            .navigationTitle("OpenRouter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePolicy() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset Draft", systemImage: "arrow.counterclockwise") {
                        applyPreferences(.init())
                    }
                }
            }
            .onAppear {
                applyPreferences(settingsState.openRouterProviderPreferences)
                spendWindow = settingsState.openRouterSpendReport.window
            }
            .task {
                await appModel.refreshOpenRouterSpend(window: spendWindow, services: services)
            }
        }
    }

    private var spendGroup: some View {
        let report = settingsState.openRouterSpendReport
        return PinesSettingsGroup("Reported usage", detail: "Pines shows provider-returned cost and never estimates a missing price.") {
            PinesSettingsControlRow("Period", systemImage: "calendar") {
                Picker("Usage period", selection: $spendWindow) {
                    ForEach(OpenRouterSpendWindow.allCases, id: \.self) { window in
                        Text(window.settingsTitle).tag(window)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: spendWindow) { _, window in
                    Task { await appModel.refreshOpenRouterSpend(window: window, services: services) }
                }
            }

            PinesSettingsDivider()
            PinesSettingsValueRow("Reported cost", value: formattedCredits(report.reportedCostCredits), systemImage: "creditcard")
            PinesSettingsDivider()
            PinesSettingsValueRow("Runs", value: "\(report.runCount)", detail: "Cost reported for \(report.reportedCostRunCount) run\(report.reportedCostRunCount == 1 ? "" : "s").", systemImage: "bolt")
            PinesSettingsDivider()
            PinesSettingsValueRow("Tokens", value: "\((report.promptTokens + report.completionTokens).formatted())", systemImage: "text.word.spacing")

            if report.missingCostRunCount > 0 {
                PinesSettingsDivider()
                PinesSettingsNotice(
                    title: "Some runs did not report cost",
                    detail: "\(report.missingCostRunCount) run\(report.missingCostRunCount == 1 ? " is" : "s are") excluded from the total.",
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
                .padding(theme.spacing.medium)
            }

            if !report.byUpstreamProvider.isEmpty {
                PinesSettingsDivider()
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    ForEach(report.byUpstreamProvider) { provider in
                        LabeledContent(
                            provider.providerName,
                            value: "\(provider.runCount) · \(formattedCredits(provider.reportedCostCredits))"
                        )
                        .font(theme.typography.caption)
                    }
                }
                .padding(theme.spacing.medium)
            }
        }
    }

    private var orderSlugs: [String] { parsedSlugs(orderText) }

    private func parsedSlugs(_ value: String) -> [String] {
        value.split(separator: ",").map(String.init)
    }

    private func applyPreferences(_ preferences: OpenRouterProviderPreferences) {
        orderText = preferences.order.joined(separator: ", ")
        onlyText = preferences.only.joined(separator: ", ")
        ignoreText = preferences.ignore.joined(separator: ", ")
        allowFallbacks = preferences.allowFallbacks
        requireParameters = preferences.requireParameters
        deniesDataCollection = preferences.dataCollection == .deny
        zeroDataRetention = preferences.zeroDataRetention
        sort = preferences.sort
        webSearchEngine = preferences.webSearchEngine
    }

    private func savePolicy() {
        settingsState.openRouterProviderPreferences = OpenRouterProviderPreferences(
            order: parsedSlugs(orderText),
            only: parsedSlugs(onlyText),
            ignore: parsedSlugs(ignoreText),
            allowFallbacks: allowFallbacks,
            requireParameters: requireParameters,
            dataCollection: deniesDataCollection ? .deny : .allow,
            zeroDataRetention: zeroDataRetention,
            sort: sort,
            webSearchEngine: webSearchEngine
        )
        Task {
            await appModel.saveSettings(services: services)
            dismiss()
        }
    }

    private func formattedCredits(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...6)))) credits"
    }
}

extension CloudProviderKind {
    var settingsTitle: String {
        switch self {
        case .openAI: "OpenAI"
        case .openAICompatible: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        case .openRouter: "OpenRouter"
        case .voyageAI: "Voyage AI"
        case .custom: "Custom"
        }
    }

    var settingsDefaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .openAICompatible: "https://"
        case .anthropic: "https://api.anthropic.com"
        case .gemini: "https://generativelanguage.googleapis.com"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .voyageAI: "https://api.voyageai.com/v1"
        case .custom: "https://"
        }
    }

    var settingsSystemImage: String {
        switch self {
        case .openAI, .openAICompatible, .openRouter, .custom: "cloud"
        case .anthropic: "text.bubble"
        case .gemini: "sparkles"
        case .voyageAI: "square.stack.3d.up"
        }
    }
}

private extension ProviderValidationStatus {
    var settingsCloudStatus: PinesCloudStatus {
        switch self {
        case .valid: .enabled
        case .unvalidated: .needsValidation
        case .invalid: .failed
        case .rateLimited: .warning("Rate limited")
        }
    }
}

private extension OpenRouterProviderSort {
    var settingsTitle: String {
        switch self {
        case .automatic: "Automatic"
        case .price: "Lowest price"
        case .throughput: "Highest throughput"
        case .latency: "Lowest latency"
        }
    }
}

private extension OpenRouterWebSearchEngine {
    var settingsTitle: String {
        switch self {
        case .automatic: "Auto"
        case .native: "Provider-native"
        case .exa: "Exa"
        case .firecrawl: "Firecrawl (BYOK)"
        case .parallel: "Parallel"
        case .perplexity: "Perplexity"
        }
    }
}

private extension OpenRouterSpendWindow {
    var settingsTitle: String {
        switch self {
        case .day: "Last 24 hours"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .all: "All time"
        }
    }
}
