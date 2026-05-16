import SwiftUI
import PinesCore

struct SettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @State private var selectedSectionID: PinesSettingsSection.ID?

    private var selectedSection: PinesSettingsSection? {
        guard let selectedSectionID = selectedSectionID ?? defaultSectionID else {
            return nil
        }

        return appModel.settingsSections.first { $0.id == selectedSectionID }
    }

    private var defaultSectionID: PinesSettingsSection.ID? {
        shouldAutoSelectSidebarItem ? appModel.settingsSections.first?.id : nil
    }

    private var shouldAutoSelectSidebarItem: Bool {
        horizontalSizeClass != .compact
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSectionID) {
                Section("Settings") {
                    ForEach(appModel.settingsSections) { section in
                        NavigationLink(value: section.id) {
                            SettingsSectionRow(section: section, isSelected: selectedSectionID == section.id)
                        }
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
            .onChange(of: appModel.settingsSections) { _, sections in
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
                    executionMode: appModel.executionMode,
                    storeConfiguration: appModel.storeConfiguration,
                    selectedThemeTemplate: $appModel.selectedThemeTemplate,
                    interfaceMode: $appModel.interfaceMode
                )
            } else {
                PinesEmptyState(
                    title: "No settings",
                    detail: "Runtime preferences appear when the app model is loaded.",
                    systemImage: "gearshape"
                )
            }
        }
    }

    private func selectDefaultSectionIfNeeded() {
        guard shouldAutoSelectSidebarItem else { return }
        selectedSectionID = selectedSectionID ?? appModel.settingsSections.first?.id
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
