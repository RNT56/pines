import SwiftUI
import PinesCore

struct AIModelsSettingsPage: View {
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @State private var showsAdvancedLimits = false
    @State private var showsHuggingFaceEditor = false

    var body: some View {
        PinesSettingsPage(introduction: "Set sensible defaults for new chats. Provider-specific reasoning and search options remain available beside the chat composer when the selected model supports them.") {
            PinesSettingsGroup("Default routing", detail: "Pines still checks whether the selected model can handle each request.") {
                PinesSettingsControlRow(
                    "Where chats can run",
                    detail: settingsState.executionMode.settingsDetail,
                    systemImage: "point.3.connected.trianglepath.dotted"
                ) {
                    Picker("Where chats can run", selection: $settingsState.executionMode) {
                        ForEach(AgentExecutionMode.allCases, id: \.self) { mode in
                            Text(mode.settingsTitle).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: settingsState.executionMode) { _, _ in saveSettings() }
                }
            }

            PinesSettingsGroup("Response size & local performance", detail: "Balanced is a good default for most devices and conversations.") {
                PinesSettingsControlRow(
                    "Preset",
                    detail: generationPreset.detail,
                    systemImage: "slider.horizontal.3"
                ) {
                    Picker("Generation preset", selection: generationPresetBinding) {
                        ForEach(GenerationPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                PinesSettingsDivider()

                DisclosureGroup(isExpanded: $showsAdvancedLimits) {
                    VStack(alignment: .leading, spacing: theme.spacing.medium) {
                        Stepper(
                            "Cloud response: \(settingsState.cloudMaxCompletionTokens.formatted()) tokens",
                            value: $settingsState.cloudMaxCompletionTokens,
                            in: AppSettingsSnapshot.minCompletionTokens...AppSettingsSnapshot.maxCompletionTokens,
                            step: 1_024
                        )
                        .onChange(of: settingsState.cloudMaxCompletionTokens) { _, _ in saveSettings() }

                        Stepper(
                            "Local response: \(settingsState.localMaxCompletionTokens.formatted()) tokens",
                            value: $settingsState.localMaxCompletionTokens,
                            in: AppSettingsSnapshot.minCompletionTokens...AppSettingsSnapshot.maxCompletionTokens,
                            step: 256
                        )
                        .onChange(of: settingsState.localMaxCompletionTokens) { _, _ in saveSettings() }

                        Stepper(
                            "Local context: \(settingsState.localMaxContextTokens.formatted()) tokens",
                            value: $settingsState.localMaxContextTokens,
                            in: AppSettingsSnapshot.minLocalContextTokens...AppSettingsSnapshot.maxLocalContextTokens,
                            step: 1_024
                        )
                        .onChange(of: settingsState.localMaxContextTokens) { _, _ in saveSettings() }

                        Picker("Local performance", selection: $settingsState.localTurboQuantMode) {
                            ForEach(TurboQuantUserMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .onChange(of: settingsState.localTurboQuantMode) { _, _ in saveSettings() }
                    }
                    .padding(.top, theme.spacing.medium)
                } label: {
                    Label("Custom limits", systemImage: "dial.medium")
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                }
                .padding(theme.spacing.medium)
            }

            PinesSettingsGroup("Model downloads") {
                PinesSettingsValueRow(
                    "Hugging Face access",
                    value: settingsState.huggingFaceCredentialStatus,
                    detail: "A token is only needed for gated or private model downloads.",
                    systemImage: "key",
                    valueTone: settingsState.huggingFaceCredentialStatus.hasPrefix("Configured") ? .success : .neutral
                )

                PinesSettingsDivider()

                PinesSettingsActionRow(
                    title: "Manage download access",
                    detail: "Add, replace, validate, or remove the token stored on this device.",
                    systemImage: "person.badge.key",
                    action: { showsHuggingFaceEditor = true }
                )
            }
        }
        .sheet(isPresented: $showsHuggingFaceEditor) {
            HuggingFaceCredentialSheet()
                .environmentObject(appModel)
                .environmentObject(settingsState)
        }
    }

    private var generationPreset: GenerationPreset {
        GenerationPreset.resolve(
            cloudTokens: settingsState.cloudMaxCompletionTokens,
            localTokens: settingsState.localMaxCompletionTokens,
            contextTokens: settingsState.localMaxContextTokens,
            mode: settingsState.localTurboQuantMode
        )
    }

    private var generationPresetBinding: Binding<GenerationPreset> {
        Binding(
            get: { generationPreset },
            set: { preset in
                guard preset != .custom else {
                    showsAdvancedLimits = true
                    return
                }
                preset.apply(to: settingsState)
                saveSettings()
            }
        )
    }

    private func saveSettings() {
        Task { await appModel.saveSettings(services: services) }
    }
}

private enum GenerationPreset: String, CaseIterable, Identifiable {
    case efficient
    case balanced
    case largeContext
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .efficient: "Efficient"
        case .balanced: "Balanced"
        case .largeContext: "Large context"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .efficient: "Shorter answers and lower local memory use."
        case .balanced: "Good response length and local performance for most chats."
        case .largeContext: "Keeps more local conversation context and can use more memory."
        case .custom: "Uses the exact limits shown below."
        }
    }

    static func resolve(
        cloudTokens: Int,
        localTokens: Int,
        contextTokens: Int,
        mode: TurboQuantUserMode
    ) -> GenerationPreset {
        if cloudTokens == 4_096, localTokens == 512, contextTokens == 32_768, mode == .batterySaver {
            return .efficient
        }
        if cloudTokens == 16_384, localTokens == 1_024, contextTokens == 65_536, mode == .balanced {
            return .balanced
        }
        if cloudTokens == 32_768, localTokens == 2_048, contextTokens == 131_072, mode == .maxContext {
            return .largeContext
        }
        return .custom
    }

    @MainActor
    func apply(to settings: PinesSettingsState) {
        switch self {
        case .efficient:
            settings.cloudMaxCompletionTokens = 4_096
            settings.localMaxCompletionTokens = 512
            settings.localMaxContextTokens = 32_768
            settings.localTurboQuantMode = .batterySaver
        case .balanced:
            settings.cloudMaxCompletionTokens = 16_384
            settings.localMaxCompletionTokens = 1_024
            settings.localMaxContextTokens = 65_536
            settings.localTurboQuantMode = .balanced
        case .largeContext:
            settings.cloudMaxCompletionTokens = 32_768
            settings.localMaxCompletionTokens = 2_048
            settings.localMaxContextTokens = 131_072
            settings.localTurboQuantMode = .maxContext
        case .custom:
            break
        }
    }
}

private struct HuggingFaceCredentialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @State private var token = ""
    @State private var showsDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            PinesSettingsPage(introduction: "Pines stores this token in the device keychain. It is used only when Hugging Face requires authentication for a model download.") {
                PinesSettingsGroup("Access token") {
                    PinesSettingsValueRow(
                        "Status",
                        value: settingsState.huggingFaceCredentialStatus,
                        systemImage: "checkmark.seal",
                        valueTone: settingsState.huggingFaceCredentialStatus.hasPrefix("Configured") ? .success : .neutral
                    )

                    PinesSettingsDivider()

                    SecureField("Paste a new token", text: $token)
                        .textContentType(.password)
                        .accessibilityIdentifier("pines.settings.huggingface.token")
                        .pinesFieldChrome()
                        .padding(theme.spacing.medium)

                    PinesSettingsDivider()

                    PinesAdaptiveButtonRow {
                        Button {
                            Task {
                                await appModel.saveHuggingFaceToken(token, services: services)
                                token = ""
                            }
                        } label: {
                            Label("Save token", systemImage: "key.fill")
                        }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .pinesButtonStyle(.primary, fillWidth: true)

                        Button {
                            Task { await appModel.validateHuggingFaceToken(services: services) }
                        } label: {
                            Label("Validate", systemImage: "checkmark.seal")
                        }
                        .pinesButtonStyle(.secondary, fillWidth: true)
                    }
                    .padding(theme.spacing.medium)
                }

                PinesSettingsGroup("Remove access") {
                    PinesSettingsActionRow(
                        title: "Delete token",
                        detail: "Gated model downloads will stop until another token is saved.",
                        systemImage: "trash",
                        role: .destructive,
                        showsDisclosure: false,
                        action: { showsDeleteConfirmation = true }
                    )
                }
            }
            .navigationTitle("Model Download Access")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete Hugging Face token?", isPresented: $showsDeleteConfirmation) {
                Button("Delete token", role: .destructive) {
                    Task {
                        await appModel.deleteHuggingFaceToken(services: services)
                        token = ""
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private extension AgentExecutionMode {
    var settingsTitle: String {
        switch self {
        case .localOnly: "Local only"
        case .preferLocal: "Prefer local"
        case .cloudAllowed: "Allow cloud"
        case .cloudRequired: "Cloud only"
        }
    }

    var settingsDetail: String {
        switch self {
        case .localOnly:
            "Never sends chat content to a cloud model. Requests fail when no local model can handle them."
        case .preferLocal:
            "Uses a capable local model first and falls back to an allowed cloud provider when needed."
        case .cloudAllowed:
            "Lets Pines choose the most suitable configured local or cloud model."
        case .cloudRequired:
            "Routes chats to an allowed cloud provider and does not use local inference."
        }
    }
}
