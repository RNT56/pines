import SwiftUI
import PinesCore

struct PrivacyDataSettingsPage: View {
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @State private var showsAdvancedSync = false
    @State private var showsStorageDetails = false
    @State private var showsEraseAllDataConfirmation = false

    private var iCloudSyncAvailable: Bool {
        services.cloudKitSyncService != nil
    }

    var body: some View {
        PinesSettingsPage(introduction: "Pines keeps your working data on this device by default. Private iCloud sync is optional and can be turned off at any time.") {
            PinesSettingsGroup("Security") {
                PinesSettingsControlRow(
                    "App lock",
                    detail: "Require device authentication when returning to Pines.",
                    systemImage: "lock"
                ) {
                    Toggle("App lock", isOn: Binding(
                        get: { settingsState.securityConfiguration.appLockEnabled },
                        set: { enabled in
                            settingsState.securityConfiguration.appLockEnabled = enabled
                            saveSettings()
                        }
                    ))
                    .labelsHidden()
                }
            }

            PinesSettingsGroup("Private iCloud sync", detail: "Sync uses Pines' private CloudKit zone and end-to-end encrypted records.") {
                if iCloudSyncAvailable {
                    PinesSettingsControlRow(
                        "Sync across devices",
                        detail: "Keep chats, vault metadata, provider settings, and preferences available on your devices. API keys never sync.",
                        systemImage: "icloud"
                    ) {
                        Toggle("Private iCloud sync", isOn: Binding(
                            get: { settingsState.storeConfiguration.iCloudSyncEnabled },
                            set: { enabled in
                                settingsState.storeConfiguration.iCloudSyncEnabled = enabled
                                saveSettings()
                            }
                        ))
                        .labelsHidden()
                    }

                    PinesSettingsDivider()

                    PinesSettingsControlRow(
                        "Sync status",
                        detail: cloudKitSyncSummary,
                        systemImage: "arrow.triangle.2.circlepath.icloud"
                    ) {
                        Button {
                            Task { await appModel.syncCloudKitNow(services: services, reason: "manual_settings") }
                        } label: {
                            if settingsState.cloudKitSyncStatus.phase == .syncing {
                                ProgressView()
                            } else {
                                Label("Sync now", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(
                            !settingsState.storeConfiguration.iCloudSyncEnabled
                                || settingsState.cloudKitSyncStatus.phase == .syncing
                        )
                        .pinesButtonStyle(.secondary)
                        .accessibilityIdentifier("pines.settings.icloud.sync-now")
                    }

                    if let syncError = settingsState.cloudKitSyncStatus.lastError,
                       settingsState.storeConfiguration.iCloudSyncEnabled {
                        PinesSettingsDivider()
                        PinesSettingsNotice(
                            title: "Sync needs attention",
                            detail: syncError,
                            systemImage: "exclamationmark.icloud",
                            tone: .warning
                        )
                        .padding(theme.spacing.medium)
                        .accessibilityIdentifier("pines.settings.icloud.error")
                    }

                    if !settingsState.cloudKitConflicts.isEmpty {
                        PinesSettingsDivider()
                        VStack(alignment: .leading, spacing: theme.spacing.medium) {
                            Text("Choose which copy to keep")
                                .font(theme.typography.callout.weight(.semibold))
                                .foregroundStyle(theme.colors.warning)

                            ForEach(settingsState.cloudKitConflicts) { conflict in
                                cloudKitConflictRow(conflict)
                            }
                        }
                        .padding(theme.spacing.medium)
                        .accessibilityIdentifier("pines.settings.icloud.conflicts")
                    }

                    PinesSettingsDivider()

                    DisclosureGroup(isExpanded: $showsAdvancedSync) {
                        VStack(alignment: .leading, spacing: theme.spacing.medium) {
                            Toggle("Sync imported source documents", isOn: Binding(
                                get: { settingsState.storeConfiguration.syncsSourceDocuments },
                                set: { enabled in
                                    settingsState.storeConfiguration.syncsSourceDocuments = enabled
                                    saveSettings()
                                }
                            ))
                            .disabled(!settingsState.storeConfiguration.iCloudSyncEnabled)

                            Toggle("Sync generated embeddings", isOn: Binding(
                                get: { settingsState.storeConfiguration.syncsEmbeddings },
                                set: { enabled in
                                    settingsState.storeConfiguration.syncsEmbeddings = enabled
                                    saveSettings()
                                }
                            ))
                            .disabled(!settingsState.storeConfiguration.iCloudSyncEnabled)

                            Text("Embeddings can be regenerated from source text. Leaving them off reduces sync storage and transfer size.")
                                .font(theme.typography.caption)
                                .foregroundStyle(theme.colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, theme.spacing.medium)
                    } label: {
                        Label("What gets synced", systemImage: "checklist")
                            .font(theme.typography.callout.weight(.semibold))
                    }
                    .padding(theme.spacing.medium)
                } else {
                    PinesSettingsValueRow(
                        "Unavailable in this build",
                        value: "Local only",
                        detail: "This build does not include the iCloud entitlement required for sync. Your data remains on this device.",
                        systemImage: "icloud.slash",
                        valueTone: .neutral
                    )
                }
            }

            PinesSettingsGroup("On-device storage") {
                PinesSettingsValueRow(
                    "Local data",
                    value: "Protected",
                    detail: "Chats, vault files, models, and credentials remain in Pines' protected app storage.",
                    systemImage: "internaldrive",
                    valueTone: .success
                )

                PinesSettingsDivider()

                DisclosureGroup(isExpanded: $showsStorageDetails) {
                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        LabeledContent("Database", value: settingsState.storeConfiguration.databaseFileName)
                        LabeledContent("File protection", value: settingsState.storeConfiguration.dataProtection.settingsTitle)
                        LabeledContent("Encrypted records", value: settingsState.securityConfiguration.cloudKitE2EEnabled ? "On" : "Off")
                    }
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.top, theme.spacing.medium)
                    .textSelection(.enabled)
                } label: {
                    Label("Storage details", systemImage: "info.circle")
                        .font(theme.typography.callout.weight(.semibold))
                }
                .padding(theme.spacing.medium)
            }

            PinesSettingsGroup("Delete data", detail: "This cannot be undone.") {
                PinesSettingsActionRow(
                    title: "Delete all Pines data",
                    detail: "Remove local models, chats, vault files, providers, credentials, MCP servers, artifacts, and the private iCloud zone when available.",
                    systemImage: "trash",
                    role: .destructive,
                    showsDisclosure: false,
                    action: { showsEraseAllDataConfirmation = true }
                )
            }
        }
        .confirmationDialog(
            "Delete all Pines data?",
            isPresented: $showsEraseAllDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete local and iCloud data", role: .destructive) {
                Task { await appModel.eraseAllUserData(services: services) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes Pines data from this device and its private iCloud sync zone when available.")
        }
    }

    private var cloudKitSyncSummary: String {
        guard iCloudSyncAvailable else {
            return "Unavailable in this build. Local data remains on this device."
        }
        guard settingsState.storeConfiguration.iCloudSyncEnabled else {
            return "Off. Local data remains on this device."
        }
        switch settingsState.cloudKitSyncStatus.phase {
        case .idle:
            return "Waiting for the first sync."
        case .syncing:
            return "Uploading and merging private records."
        case .succeeded:
            if let lastSuccessAt = settingsState.cloudKitSyncStatus.lastSuccessAt {
                return "Last completed \(lastSuccessAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return "Up to date."
        case .failed:
            if let lastSuccessAt = settingsState.cloudKitSyncStatus.lastSuccessAt {
                return "Last successful sync was \(lastSuccessAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return "Sync has not completed successfully."
        }
    }

    private func cloudKitConflictRow(_ conflict: CloudKitConflictRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            Text(conflict.title)
                .font(theme.typography.callout.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text("This device: \(conflict.deviceSummary)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)
            Text("iCloud: \(conflict.iCloudSummary)")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.secondaryText)

            PinesAdaptiveButtonRow {
                Button("Keep This Device") {
                    Task {
                        await appModel.resolveCloudKitConflict(
                            id: conflict.id,
                            resolution: .keepDevice,
                            services: services
                        )
                    }
                }
                .pinesButtonStyle(.secondary, fillWidth: true)

                Button("Use iCloud") {
                    Task {
                        await appModel.resolveCloudKitConflict(
                            id: conflict.id,
                            resolution: .useICloud,
                            services: services
                        )
                    }
                }
                .pinesButtonStyle(.secondary, fillWidth: true)
            }
        }
        .pinesSurface(.inset, padding: theme.spacing.medium)
    }

    private func saveSettings() {
        Task { await appModel.saveSettings(services: services) }
    }
}

private extension DataProtectionClass {
    var settingsTitle: String {
        switch self {
        case .complete: "When device is unlocked"
        case .completeUntilFirstUserAuthentication: "After first unlock"
        }
    }
}
