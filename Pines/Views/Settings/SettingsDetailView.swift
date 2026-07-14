import SwiftUI
import PinesCore

struct SettingsDetailView: View {
    let section: PinesSettingsSection
    @Binding var selectedThemeTemplate: PinesThemeTemplate
    @Binding var interfaceMode: PinesInterfaceMode

    var body: some View {
        Group {
            switch section.destination {
            case .appearance:
                AppearanceSettingsPage(
                    selectedThemeTemplate: $selectedThemeTemplate,
                    interfaceMode: $interfaceMode
                )
            case .aiModels:
                AIModelsSettingsPage()
            case .cloudProviders:
                CloudProvidersSettingsPage()
            case .privacyData:
                PrivacyDataSettingsPage()
            case .toolsIntegrations:
                ToolsIntegrationsSettingsPage()
            case .diagnostics:
                DiagnosticsSettingsPage()
            }
        }
        .navigationTitle(section.title)
        .accessibilityIdentifier("pines.settings.detail.\(section.destination.rawValue)")
        .pinesInlineNavigationTitle()
    }
}
