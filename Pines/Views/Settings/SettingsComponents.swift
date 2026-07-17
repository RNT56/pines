import SwiftUI

struct PinesSettingsPage<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    let introduction: String?
    @ViewBuilder let content: () -> Content

    init(
        introduction: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.introduction = introduction
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.large) {
                if let introduction {
                    Text(introduction)
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, theme.spacing.xsmall)
                }

                content()
            }
            .padding(.horizontal, theme.spacing.medium)
            .padding(.top, theme.spacing.medium)
            .padding(.bottom, theme.spacing.xxlarge)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .pinesAppBackground()
    }
}
struct PinesSettingsGroup<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let detail: String?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(title)
                    .font(theme.typography.headline)
                    .foregroundStyle(theme.colors.primaryText)

                if let detail {
                    Text(detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, theme.spacing.xsmall)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pinesSurface(.panel, padding: 0)
        }
    }
}

struct PinesSettingsDivider: View {
    @Environment(\.pinesTheme) private var theme

    var body: some View {
        Divider()
            .overlay(theme.colors.separator)
            .padding(.leading, theme.spacing.medium)
    }
}

struct PinesSettingsControlRow<Control: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pinesTheme) private var theme
    let title: String
    let detail: String?
    let systemImage: String?
    @ViewBuilder let control: () -> Control

    init(
        _ title: String,
        detail: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.control = control
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.spacing.small) {
                    label
                    control()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: theme.spacing.medium) {
                    label
                    Spacer(minLength: theme.spacing.medium)
                    control()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(theme.spacing.medium)
        .frame(maxWidth: .infinity, minHeight: theme.row.minHeight, alignment: .leading)
    }

    private var label: some View {
        HStack(alignment: .top, spacing: theme.spacing.small) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(title)
                    .font(theme.typography.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PinesSettingsValueRow: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let value: String
    let detail: String?
    let systemImage: String?
    let valueTone: PinesCloudStatusTone

    init(
        _ title: String,
        value: String,
        detail: String? = nil,
        systemImage: String? = nil,
        valueTone: PinesCloudStatusTone = .neutral
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        self.valueTone = valueTone
    }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.small) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(title)
                    .font(theme.typography.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)

                if let detail {
                    Text(detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: theme.spacing.small)

            Text(value)
                .font(theme.typography.callout)
                .foregroundStyle(valueTone.color(in: theme))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(theme.spacing.medium)
        .frame(maxWidth: .infinity, minHeight: theme.row.minHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PinesSettingsActionRow: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let detail: String?
    let systemImage: String
    var role: ButtonRole?
    var showsDisclosure = true
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(alignment: .center, spacing: theme.spacing.small) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(role == .destructive ? theme.colors.danger : theme.colors.accent)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(title)
                        .font(theme.typography.callout.weight(.semibold))
                        .foregroundStyle(role == .destructive ? theme.colors.danger : theme.colors.primaryText)

                    if let detail {
                        Text(detail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: theme.spacing.small)

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.colors.tertiaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(theme.spacing.medium)
        .frame(maxWidth: .infinity, minHeight: theme.row.minHeight, alignment: .leading)
    }
}

struct PinesSettingsNotice: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let detail: String
    let systemImage: String
    var tone: PinesCloudStatusTone = .info

    var body: some View {
        let tint = tone.color(in: theme)
        HStack(alignment: .top, spacing: theme.spacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                Text(title)
                    .font(theme.typography.callout.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Text(detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(theme.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(theme.colorScheme == .dark ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous)
                .strokeBorder(tint.opacity(0.20), lineWidth: theme.stroke.hairline)
        }
    }
}
