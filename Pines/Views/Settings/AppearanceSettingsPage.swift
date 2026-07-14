import SwiftUI

struct AppearanceSettingsPage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pinesServices) private var services
    @Environment(\.pinesTheme) private var theme
    @EnvironmentObject private var appModel: PinesAppModel
    @EnvironmentObject private var haptics: PinesHaptics
    @Binding var selectedThemeTemplate: PinesThemeTemplate
    @Binding var interfaceMode: PinesInterfaceMode

    var body: some View {
        PinesSettingsPage(introduction: "Choose how Pines looks and responds. These preferences affect the interface only; they do not change your models or data.") {
            PinesSettingsGroup("Color & appearance") {
                PinesSettingsControlRow(
                    "Interface appearance",
                    detail: "Follow the device setting or keep Pines light or dark.",
                    systemImage: "circle.lefthalf.filled"
                ) {
                    Picker("Interface appearance", selection: $interfaceMode) {
                        ForEach(PinesInterfaceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("pines.settings.interface-mode")
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: interfaceMode) { _, _ in
                        saveSettings()
                    }
                }

                PinesSettingsDivider()

                VStack(alignment: .leading, spacing: theme.spacing.medium) {
                    Text("Theme")
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)

                    LazyVGrid(columns: themePickerColumns, spacing: PinesThemePickerLayout.gridSpacing) {
                        ForEach(PinesThemeTemplate.allCases) { template in
                            Button {
                                selectedThemeTemplate = template
                                haptics.play(.navigationSelected)
                                saveSettings()
                            } label: {
                                PinesThemePreviewCard(
                                    template: template,
                                    isSelected: selectedThemeTemplate == template
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedThemeTemplate == template ? .isSelected : [])
                        }
                    }
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
                .padding(theme.spacing.medium)
            }

            PinesSettingsGroup("Feedback") {
                PinesSettingsControlRow(
                    "Haptic feedback",
                    detail: haptics.mode.subtitle,
                    systemImage: "hand.tap"
                ) {
                    Picker("Haptic feedback", selection: $haptics.mode) {
                        ForEach(PinesHapticMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: haptics.mode) { _, mode in
                        if mode != .off {
                            haptics.play(.primaryAction)
                        }
                    }
                }

                PinesSettingsDivider()

                PinesSettingsValueRow(
                    "Motion",
                    value: "System controlled",
                    detail: "Pines follows Reduce Motion and other accessibility preferences automatically.",
                    systemImage: "figure.walk.motion"
                )
            }
        }
    }

    private var themePickerColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return PinesThemePickerLayout.gridColumns
    }

    private func saveSettings() {
        Task { await appModel.saveSettings(services: services) }
    }
}
