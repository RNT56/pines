import SwiftUI
import PinesCore

struct SettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedSectionID: PinesSettingsSection.ID?

    private var selectedSection: PinesSettingsSection? {
        guard let selectedSectionID = selectedSectionID ?? defaultSectionID else {
            return nil
        }

        return settingsState.settingsSections.first { $0.id == selectedSectionID }
    }

    private var defaultSectionID: PinesSettingsSection.ID? {
        shouldAutoSelectSidebarItem ? settingsState.settingsSections.first?.id : nil
    }

    private var shouldAutoSelectSidebarItem: Bool {
        horizontalSizeClass != .compact
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSectionID) {
                Section("Settings") {
                    ForEach(settingsState.settingsSections) { section in
                        NavigationLink(value: section.id) {
                            SettingsSectionRow(section: section, isSelected: selectedSectionID == section.id)
                        }
                        .accessibilityIdentifier("pines.settings.section.\(section.title.uiTestIdentifierComponent)")
                        .pinesSidebarListRow()
                    }
                }
            }
            .navigationTitle("Settings")
            .pinesExpressiveScrollHaptics()
            .onAppear(perform: selectDefaultSectionIfNeeded)
            .onChange(of: horizontalSizeClass) { _, _ in
                selectDefaultSectionIfNeeded()
            }
            .onChange(of: settingsState.settingsSections) { _, sections in
                if let selectedSectionID, !sections.contains(where: { $0.id == selectedSectionID }) {
                    self.selectedSectionID = nil
                }
                selectDefaultSectionIfNeeded()
            }
            .onChange(of: selectedSectionID) { _, _ in
                haptics.play(.navigationSelected)
            }
            .pinesSidebarListChrome()
        } detail: {
            if let selectedSection {
                SettingsDetailView(
                    section: selectedSection,
                    executionMode: settingsState.executionMode,
                    storeConfiguration: settingsState.storeConfiguration,
                    selectedThemeTemplate: $settingsState.selectedThemeTemplate,
                    interfaceMode: $settingsState.interfaceMode
                )
            } else {
                PinesEmptyState(
                    title: "No settings",
                    detail: "Runtime preferences appear when the app model is loaded.",
                    systemImage: "gearshape"
                )
            }
        }
        .accessibilityIdentifier("pines.screen.settings")
    }

    private func selectDefaultSectionIfNeeded() {
        guard shouldAutoSelectSidebarItem else { return }
        selectedSectionID = selectedSectionID ?? settingsState.settingsSections.first?.id
    }
}

private struct SettingsSectionRow: View {
    @Environment(\.pinesTheme) private var theme
    let section: PinesSettingsSection
    let isSelected: Bool

    var body: some View {
        PinesSidebarRow(
            title: section.title,
            subtitle: section.subtitle,
            systemImage: section.systemImage,
            tint: theme.colors.accent,
            isSelected: isSelected
        )
    }
}
