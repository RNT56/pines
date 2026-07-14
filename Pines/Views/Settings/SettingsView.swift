import SwiftUI
import PinesCore

struct SettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var settingsState: PinesSettingsState
    @EnvironmentObject private var haptics: PinesHaptics
    @Binding var requestedSectionID: PinesSettingsSection.ID?
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

    private var primarySections: [PinesSettingsSection] {
        settingsState.settingsSections.filter { !$0.isSupportDestination }
    }

    private var supportSections: [PinesSettingsSection] {
        settingsState.settingsSections.filter(\.isSupportDestination)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSectionID) {
                Section("Settings") {
                    settingsSectionLinks(primarySections)
                }

                if !supportSections.isEmpty {
                    Section("Support") {
                        settingsSectionLinks(supportSections)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: selectDefaultSectionIfNeeded)
            .onChange(of: requestedSectionID) { _, _ in
                applyRequestedSectionIfNeeded()
            }
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

    @ViewBuilder
    private func settingsSectionLinks(_ sections: [PinesSettingsSection]) -> some View {
        ForEach(sections) { section in
            NavigationLink(value: section.id) {
                SettingsSectionRow(section: section, isSelected: selectedSectionID == section.id)
            }
            .accessibilityIdentifier("pines.settings.section.\(section.destination.rawValue)")
            .pinesSidebarListRow()
        }
    }

    private func selectDefaultSectionIfNeeded() {
        applyRequestedSectionIfNeeded()
        guard shouldAutoSelectSidebarItem else { return }
        selectedSectionID = selectedSectionID ?? settingsState.settingsSections.first?.id
    }

    private func applyRequestedSectionIfNeeded() {
        guard let requestedSectionID,
              settingsState.settingsSections.contains(where: { $0.id == requestedSectionID })
        else { return }
        selectedSectionID = requestedSectionID
        self.requestedSectionID = nil
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
