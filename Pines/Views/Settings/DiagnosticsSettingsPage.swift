import SwiftUI
import PinesCore

#if canImport(UIKit)
import UIKit
#endif

struct DiagnosticsSettingsPage: View {
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var settingsState: PinesSettingsState
    @State private var showsAllServices = false
    @State private var showsRuntimeDetails = false
    @State private var showsPrivacyLog = false
    @State private var copiedDiagnostics = false

    private var servicesNeedingAttention: [ServiceHealth] {
        services.serviceHealth.filter {
            $0.readiness == .degraded || $0.readiness == .requiresUserAction
        }
    }

    var body: some View {
        PinesSettingsPage(introduction: "Most people never need these details. Use them when Pines asks for attention or when sharing a support report.") {
            PinesSettingsGroup("Health") {
                PinesSettingsValueRow(
                    servicesNeedingAttention.isEmpty ? "Pines is ready" : "Some services need attention",
                    value: servicesNeedingAttention.isEmpty ? "Healthy" : "\(servicesNeedingAttention.count)",
                    detail: servicesNeedingAttention.isEmpty
                        ? "Local storage and core services are available."
                        : servicesNeedingAttention.map(\.name).joined(separator: ", "),
                    systemImage: servicesNeedingAttention.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                    valueTone: servicesNeedingAttention.isEmpty ? .success : .warning
                )

                PinesSettingsDivider()

                DisclosureGroup(isExpanded: $showsAllServices) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(services.serviceHealth) { service in
                            HStack(alignment: .top, spacing: theme.spacing.small) {
                                Circle()
                                    .fill(service.readiness.settingsTone.color(in: theme))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 6)

                                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                                    Text(service.name)
                                        .font(theme.typography.callout.weight(.semibold))
                                        .foregroundStyle(theme.colors.primaryText)
                                    Text(service.summary)
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: theme.spacing.small)

                                Text(service.readiness.settingsTitle)
                                    .font(theme.typography.caption.weight(.semibold))
                                    .foregroundStyle(service.readiness.settingsTone.color(in: theme))
                            }
                            .padding(.vertical, theme.spacing.small)

                            if service.id != services.serviceHealth.last?.id {
                                PinesSettingsDivider()
                            }
                        }
                    }
                    .padding(.top, theme.spacing.small)
                } label: {
                    Label("Service details", systemImage: "stethoscope")
                        .font(theme.typography.callout.weight(.semibold))
                }
                .padding(theme.spacing.medium)
            }

            PinesSettingsGroup("Local inference") {
                PinesSettingsValueRow(
                    "Runtime",
                    value: runtimeSummary,
                    detail: runtimePressureSummary,
                    systemImage: "cpu",
                    valueTone: runtimeTone
                )

                PinesSettingsDivider()

                DisclosureGroup(isExpanded: $showsRuntimeDetails) {
                    VStack(alignment: .leading, spacing: theme.spacing.small) {
                        ForEach(Array(runtimeDetailItems.enumerated()), id: \.offset) { _, item in
                            LabeledContent {
                                Text(item.value)
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                            } label: {
                                Text(item.title)
                            }
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                        }
                    }
                    .padding(.top, theme.spacing.medium)
                } label: {
                    Label("Runtime details", systemImage: "memorychip")
                        .font(theme.typography.callout.weight(.semibold))
                }
                .padding(theme.spacing.medium)

                PinesSettingsDivider()

                PinesSettingsActionRow(
                    title: copiedDiagnostics ? "Diagnostics copied" : "Copy diagnostics",
                    detail: "Copies non-secret service and runtime details for troubleshooting.",
                    systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc",
                    showsDisclosure: false,
                    action: copyDiagnostics
                )
            }

            PinesSettingsGroup("Privacy log", detail: "Recent redacted events recorded on this device.") {
                if settingsState.auditEvents.isEmpty {
                    PinesSettingsValueRow(
                        "No recent events",
                        value: "Clear",
                        detail: "Notable privacy and system actions will appear here.",
                        systemImage: "checkmark.shield",
                        valueTone: .success
                    )
                } else {
                    PinesSettingsActionRow(
                        title: "View recent activity",
                        detail: "\(settingsState.auditEvents.count) event\(settingsState.auditEvents.count == 1 ? "" : "s") available.",
                        systemImage: "clock.arrow.circlepath",
                        action: { showsPrivacyLog = true }
                    )
                }
            }
        }
        .sheet(isPresented: $showsPrivacyLog) {
            NavigationStack {
                List(Array(settingsState.auditEvents.prefix(50))) { event in
                    VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                        Text(event.category.rawValue)
                            .font(theme.typography.callout.weight(.semibold))
                        Text(event.summary)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                        if let payload = event.redactedPayload, !payload.isEmpty {
                            Text(payload)
                                .font(theme.typography.caption.monospaced())
                                .foregroundStyle(theme.colors.tertiaryText)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, theme.spacing.xsmall)
                }
                .navigationTitle("Privacy Log")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsPrivacyLog = false }
                    }
                }
            }
        }
    }

    private var runtimeSummary: String {
        let diagnostics = services.mlxRuntime.runtimeDiagnostics
        if diagnostics.thermalDownshiftActive == true {
            return "Reduced for heat"
        }
        if diagnostics.activeFallbackReason != nil {
            return "Fallback active"
        }
        return diagnostics.activeAlgorithm.settingsTitle
    }

    private var runtimePressureSummary: String {
        let diagnostics = services.mlxRuntime.runtimeDiagnostics
        if let reason = diagnostics.runtimePressureReason, reason != .none {
            return reason.displayName
        }
        return "Local inference is using the best available path for this device."
    }

    private var runtimeTone: PinesCloudStatusTone {
        let diagnostics = services.mlxRuntime.runtimeDiagnostics
        return diagnostics.activeFallbackReason == nil && diagnostics.thermalDownshiftActive != true ? .success : .warning
    }

    private var runtimeDetailItems: [(title: String, value: String)] {
        let diagnostics = services.mlxRuntime.runtimeDiagnostics
        let memory = diagnostics.memoryCounters
        var items: [(String, String)] = [
            ("KV cache", diagnostics.activeAlgorithm.settingsTitle),
            ("Metal codec", diagnostics.metalCodecAvailable ? "Available" : "Unavailable"),
            ("Metal attention", diagnostics.metalAttentionAvailable ? "Available" : "Unavailable"),
        ]
        if let preset = diagnostics.preset { items.append(("Preset", preset.displayName)) }
        if let profileID = diagnostics.turboQuantProfileID { items.append(("Profile", profileID)) }
        if let requestedBackend = diagnostics.requestedBackend { items.append(("Requested backend", requestedBackend.displayName)) }
        if let activeBackend = diagnostics.activeBackend { items.append(("Active backend", activeBackend.displayName)) }
        if let attention = diagnostics.activeAttentionPath { items.append(("Attention path", attention.displayName)) }
        if let hardware = memory.hardwareModelIdentifier { items.append(("Device", hardware)) }
        if let architecture = memory.metalArchitectureName { items.append(("Metal architecture", architecture)) }
        if let workingSet = memory.metalRecommendedWorkingSetBytes {
            items.append(("Recommended working set", ByteCountFormatter.string(fromByteCount: workingSet, countStyle: .memory)))
        }
        if let available = memory.availableMemoryBytes {
            items.append(("Available memory", ByteCountFormatter.string(fromByteCount: available, countStyle: .memory)))
        }
        if let thermal = memory.thermalState { items.append(("Thermal state", thermal.capitalized)) }
        if let fallback = diagnostics.activeFallbackReason { items.append(("Fallback", fallback)) }
        return items
    }

    private func copyDiagnostics() {
        let serviceLines = services.serviceHealth.map {
            "\($0.name): \($0.readiness.settingsTitle) - \($0.summary)"
        }
        let runtimeLines = runtimeDetailItems.map { "\($0.title): \($0.value)" }
        let report = (["Pines diagnostics"] + serviceLines + runtimeLines).joined(separator: "\n")
        #if canImport(UIKit)
        UIPasteboard.general.string = report
        #endif
        copiedDiagnostics = true
    }
}

private extension ServiceReadiness {
    var settingsTitle: String {
        switch self {
        case .unavailable: "Unavailable"
        case .booting: "Starting"
        case .ready: "Ready"
        case .degraded: "Degraded"
        case .requiresUserAction: "Action needed"
        }
    }

    var settingsTone: PinesCloudStatusTone {
        switch self {
        case .ready: .success
        case .booting: .info
        case .degraded, .requiresUserAction: .warning
        case .unavailable: .danger
        }
    }
}

private extension QuantizationAlgorithm {
    var settingsTitle: String {
        switch self {
        case .none: "Standard"
        case .mlxAffine: "MLX affine"
        case .turboQuant: "TurboQuant"
        }
    }
}
