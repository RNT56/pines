import SwiftUI

enum PinesThemeTemplate: String, CaseIterable, Identifiable {
    case evergreen
    case graphite
    case aurora
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .evergreen:
            "Evergreen"
        case .graphite:
            "Graphite"
        case .aurora:
            "Aurora"
        case .paper:
            "Paper"
        }
    }

    var subtitle: String {
        switch self {
        case .evergreen:
            "Calm local-first default with glass pine accents."
        case .graphite:
            "Dense pro workspace with neutral contrast."
        case .aurora:
            "High-energy research surface with cool highlights."
        case .paper:
            "Warm reading-focused layout for vault-heavy work."
        }
    }
}

enum PinesInterfaceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

struct PinesTheme {
    var template: PinesThemeTemplate
    var mode: PinesInterfaceMode
    var colorScheme: ColorScheme
    var colors: PinesThemeColors
    var typography: PinesTypography
    var spacing: PinesThemeSpacing
    var radius: PinesThemeRadius
    var stroke: PinesThemeStroke
    var shadow: PinesThemeShadow
    var motion: PinesThemeMotion

    static func resolve(
        template: PinesThemeTemplate,
        mode: PinesInterfaceMode,
        systemScheme: ColorScheme
    ) -> PinesTheme {
        let scheme = mode.colorScheme ?? systemScheme
        return PinesTheme(
            template: template,
            mode: mode,
            colorScheme: scheme,
            colors: PinesThemeColors(template: template, scheme: scheme),
            typography: PinesTypography(template: template),
            spacing: PinesThemeSpacing(template: template),
            radius: PinesThemeRadius(template: template),
            stroke: PinesThemeStroke(template: template, scheme: scheme),
            shadow: PinesThemeShadow(template: template, scheme: scheme),
            motion: PinesThemeMotion(template: template)
        )
    }

    static let fallback = resolve(template: .evergreen, mode: .system, systemScheme: .light)
}

struct PinesThemeColors {
    var appBackground: Color
    var secondaryBackground: Color
    var surface: Color
    var elevatedSurface: Color
    var glassSurface: AnyShapeStyle
    var primaryText: Color
    var secondaryText: Color
    var tertiaryText: Color
    var separator: Color
    var accent: Color
    var accentSoft: Color
    var link: Color
    var codeBackground: Color
    var codeHeaderBackground: Color
    var inlineCodeBackground: Color
    var quoteBackground: Color
    var tableHeaderBackground: Color
    var success: Color
    var warning: Color
    var danger: Color
    var info: Color
    var userBubble: Color
    var assistantBubble: Color
    var toolBubble: Color
    var sidebarSelection: Color
    var controlFill: Color
    var controlPressed: Color
    var focusRing: Color
    var chartA: Color
    var chartB: Color
    var chartC: Color

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        let dark = scheme == .dark
        switch template {
        case .evergreen:
            appBackground = dark ? Color(hex: 0x06130F) : Color(hex: 0xF4F7F2)
            secondaryBackground = dark ? Color(hex: 0x0B1D18) : Color(hex: 0xEAF1EA)
            surface = dark ? Color(hex: 0x10251F) : Color(hex: 0xFBFCFA)
            elevatedSurface = dark ? Color(hex: 0x17342C) : Color(hex: 0xFFFFFF)
            accent = dark ? Color(hex: 0x72E0C3) : Color(hex: 0x0C7A55)
            accentSoft = accent.opacity(dark ? 0.20 : 0.12)
            success = Color(hex: dark ? 0x66D19E : 0x167A4A)
            warning = Color(hex: dark ? 0xF1BE66 : 0xB86E12)
            danger = Color(hex: dark ? 0xFF8D85 : 0xC73A34)
            info = Color(hex: dark ? 0x8CB8FF : 0x2459C7)
            chartA = accent
            chartB = Color(hex: dark ? 0x83B7FF : 0x2D67D8)
            chartC = Color(hex: dark ? 0xF1BE66 : 0xD48A18)
        case .graphite:
            appBackground = dark ? Color(hex: 0x0B0C0D) : Color(hex: 0xF2F3F5)
            secondaryBackground = dark ? Color(hex: 0x121416) : Color(hex: 0xE6E8EC)
            surface = dark ? Color(hex: 0x191B1F) : Color(hex: 0xFFFFFF)
            elevatedSurface = dark ? Color(hex: 0x22252B) : Color(hex: 0xFAFAFB)
            accent = dark ? Color(hex: 0xE7EAEE) : Color(hex: 0x1F2937)
            accentSoft = accent.opacity(dark ? 0.18 : 0.10)
            success = Color(hex: dark ? 0x7BCF9D : 0x18794E)
            warning = Color(hex: dark ? 0xEBCB7A : 0xA86512)
            danger = Color(hex: dark ? 0xF28B82 : 0xB42318)
            info = Color(hex: dark ? 0x8AB4F8 : 0x1D4ED8)
            chartA = Color(hex: dark ? 0xD7DCE3 : 0x374151)
            chartB = Color(hex: dark ? 0x8AB4F8 : 0x2563EB)
            chartC = Color(hex: dark ? 0xA7F3D0 : 0x059669)
        case .aurora:
            appBackground = dark ? Color(hex: 0x070B1C) : Color(hex: 0xF5F8FF)
            secondaryBackground = dark ? Color(hex: 0x101633) : Color(hex: 0xE8F0FF)
            surface = dark ? Color(hex: 0x141C3A) : Color(hex: 0xFFFFFF)
            elevatedSurface = dark ? Color(hex: 0x1B2752) : Color(hex: 0xF9FBFF)
            accent = dark ? Color(hex: 0x8DEBFF) : Color(hex: 0x1C6DD0)
            accentSoft = accent.opacity(dark ? 0.20 : 0.12)
            success = Color(hex: dark ? 0x7BE1B4 : 0x0F766E)
            warning = Color(hex: dark ? 0xFFD166 : 0xB45309)
            danger = Color(hex: dark ? 0xFF8FA3 : 0xBE123C)
            info = Color(hex: dark ? 0xA78BFA : 0x6D28D9)
            chartA = accent
            chartB = Color(hex: dark ? 0xB6A2FF : 0x7C3AED)
            chartC = Color(hex: dark ? 0x7BE1B4 : 0x0D9488)
        case .paper:
            appBackground = dark ? Color(hex: 0x15120E) : Color(hex: 0xFAF7F0)
            secondaryBackground = dark ? Color(hex: 0x201B14) : Color(hex: 0xF1EADC)
            surface = dark ? Color(hex: 0x282116) : Color(hex: 0xFFFDF7)
            elevatedSurface = dark ? Color(hex: 0x33291B) : Color(hex: 0xFFFFFF)
            accent = dark ? Color(hex: 0xBFE2C5) : Color(hex: 0x376B4F)
            accentSoft = accent.opacity(dark ? 0.20 : 0.12)
            success = Color(hex: dark ? 0xA7D7A4 : 0x397A3E)
            warning = Color(hex: dark ? 0xEBC56D : 0x9A6415)
            danger = Color(hex: dark ? 0xE89A8D : 0xA33A2C)
            info = Color(hex: dark ? 0x9FBCEB : 0x315E9E)
            chartA = accent
            chartB = Color(hex: dark ? 0xD6B676 : 0xA16C19)
            chartC = Color(hex: dark ? 0xA7B8D8 : 0x476B9E)
        }

        glassSurface = AnyShapeStyle(.regularMaterial)
        primaryText = dark ? Color(hex: 0xF5F7F6) : Color(hex: 0x151A18)
        secondaryText = dark ? Color(hex: 0xBAC5C1) : Color(hex: 0x4B5652)
        tertiaryText = dark ? Color(hex: 0x87938F) : Color(hex: 0x75807C)
        separator = dark ? Color.white.opacity(0.13) : Color.black.opacity(0.11)
        link = info
        codeBackground = dark ? Color.black.opacity(0.30) : Color.black.opacity(0.045)
        codeHeaderBackground = dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)
        inlineCodeBackground = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
        quoteBackground = accent.opacity(dark ? 0.13 : 0.08)
        tableHeaderBackground = dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)
        userBubble = dark ? info.opacity(0.22) : info.opacity(0.10)
        assistantBubble = dark ? accent.opacity(0.18) : accent.opacity(0.09)
        toolBubble = dark ? warning.opacity(0.18) : warning.opacity(0.10)
        sidebarSelection = accent.opacity(dark ? 0.26 : 0.13)
        controlFill = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        controlPressed = dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
        focusRing = accent.opacity(0.72)
    }
}

struct PinesTypography {
    var hero: Font
    var title: Font
    var section: Font
    var headline: Font
    var body: Font
    var bodyEmphasis: Font
    var callout: Font
    var caption: Font
    var code: Font

    init(template: PinesThemeTemplate) {
        let titleWeight: Font.Weight = template == .paper ? .semibold : .bold
        hero = .largeTitle.weight(titleWeight)
        title = .title2.weight(titleWeight)
        section = .headline.weight(.semibold)
        headline = .subheadline.weight(.semibold)
        body = .body
        bodyEmphasis = .body.weight(.medium)
        callout = .callout
        caption = .caption
        code = .system(.caption, design: .monospaced).weight(.medium)
    }
}

struct PinesThemeSpacing: Equatable {
    var xxsmall: CGFloat
    var xsmall: CGFloat
    var small: CGFloat
    var medium: CGFloat
    var large: CGFloat
    var xlarge: CGFloat
    var xxlarge: CGFloat
    var contentMaxWidth: CGFloat

    init(template: PinesThemeTemplate) {
        switch template {
        case .graphite:
            xxsmall = 3; xsmall = 6; small = 9; medium = 12; large = 18; xlarge = 24; xxlarge = 32; contentMaxWidth = 820
        case .paper:
            xxsmall = 5; xsmall = 8; small = 12; medium = 16; large = 24; xlarge = 34; xxlarge = 44; contentMaxWidth = 720
        default:
            xxsmall = 4; xsmall = 6; small = 10; medium = 14; large = 20; xlarge = 28; xxlarge = 38; contentMaxWidth = 760
        }
    }
}

struct PinesThemeRadius: Equatable {
    var control: CGFloat
    var panel: CGFloat
    var sheet: CGFloat
    var capsule: CGFloat = 999

    init(template: PinesThemeTemplate) {
        switch template {
        case .graphite:
            control = 6; panel = 8; sheet = 12
        case .paper:
            control = 8; panel = 8; sheet = 14
        default:
            control = 8; panel = 8; sheet = 16
        }
    }
}

struct PinesThemeStroke: Equatable {
    var hairline: CGFloat
    var selected: CGFloat
    var separatorOpacity: Double

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        hairline = template == .graphite ? 0.7 : 1
        selected = 1.5
        separatorOpacity = scheme == .dark ? 0.75 : 1
    }
}

struct PinesThemeShadow: Equatable {
    var panelColor: Color
    var panelRadius: CGFloat
    var panelY: CGFloat

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        panelColor = scheme == .dark ? Color.black.opacity(0.28) : Color.black.opacity(template == .paper ? 0.07 : 0.09)
        panelRadius = template == .graphite ? 10 : 18
        panelY = template == .graphite ? 5 : 10
    }
}

struct PinesThemeMotion {
    var fast: Animation
    var standard: Animation
    var emphasized: Animation

    init(template: PinesThemeTemplate) {
        fast = .smooth(duration: 0.18)
        standard = .smooth(duration: template == .paper ? 0.28 : 0.24)
        emphasized = .spring(duration: 0.42, bounce: template == .aurora ? 0.28 : 0.18)
    }
}

private struct PinesThemeKey: EnvironmentKey {
    static let defaultValue = PinesTheme.fallback
}

extension EnvironmentValues {
    var pinesTheme: PinesTheme {
        get { self[PinesThemeKey.self] }
        set { self[PinesThemeKey.self] = newValue }
    }
}

extension View {
    func pinesTheme(_ theme: PinesTheme) -> some View {
        environment(\.pinesTheme, theme)
    }
}

enum PinesSpacing {
    static let xsmall: CGFloat = 6
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let xlarge: CGFloat = 28
}

enum PinesRadius {
    static let panel: CGFloat = 8
    static let capsule: CGFloat = 999
}

enum PinesPalette {
    static let appBackground = PinesTheme.fallback.colors.appBackground
    static let surface = PinesTheme.fallback.colors.surface
    static let elevatedSurface = PinesTheme.fallback.colors.elevatedSurface
    static let primaryText = PinesTheme.fallback.colors.primaryText
    static let secondaryText = PinesTheme.fallback.colors.secondaryText
    static let tertiaryText = PinesTheme.fallback.colors.tertiaryText
    static let separator = PinesTheme.fallback.colors.separator
    static let accent = PinesTheme.fallback.colors.accent
    static let blue = PinesTheme.fallback.colors.info
    static let amber = PinesTheme.fallback.colors.warning
}

struct PinesBootMarkView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: theme.spacing.large) {
            PinesMark(size: 92)
                .transition(.opacity.combined(with: reduceMotion ? .identity : .scale(scale: 0.94)))

            VStack(spacing: theme.spacing.xsmall) {
                Text("pines")
                    .font(theme.typography.hero)
                    .foregroundStyle(theme.colors.primaryText)

                Text("Local-first AI workbench")
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.glassSurface)
        .transition(.opacity.combined(with: reduceMotion ? .identity : .scale(scale: 0.98)))
    }
}

struct PinesMark: View {
    @Environment(\.pinesTheme) private var theme
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.colors.glassSurface)

            Circle()
                .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)

            Image("PinesMark")
                .resizable()
                .scaledToFit()
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .shadow(color: theme.shadow.panelColor, radius: theme.shadow.panelRadius, x: 0, y: theme.shadow.panelY)
        .accessibilityHidden(true)
    }
}

struct PinesSectionHeader: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            Text(title)
                .font(theme.typography.title)
                .foregroundStyle(theme.colors.primaryText)

            if let subtitle {
                Text(subtitle)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PinesMetricPill: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let systemImage: String
    var tint: Color?

    var body: some View {
        let resolvedTint = tint ?? theme.colors.accent
        Label(title, systemImage: systemImage)
            .font(theme.typography.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(resolvedTint)
            .lineLimit(1)
            .padding(.horizontal, theme.spacing.small)
            .padding(.vertical, theme.spacing.xsmall)
            .background(resolvedTint.opacity(0.12), in: Capsule())
    }
}

struct PinesEmptyState: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(spacing: theme.spacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 70, height: 70)
                .background(theme.colors.glassSurface, in: Circle())

            VStack(spacing: theme.spacing.xsmall) {
                Text(title)
                    .font(theme.typography.section)
                    .foregroundStyle(theme.colors.primaryText)

                Text(detail)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(theme.spacing.xlarge)
    }
}

struct PinesThemePreviewCard: View {
    @Environment(\.pinesTheme) private var currentTheme
    let template: PinesThemeTemplate
    let isSelected: Bool

    var body: some View {
        let preview = PinesTheme.resolve(template: template, mode: currentTheme.mode, systemScheme: currentTheme.colorScheme)
        VStack(alignment: .leading, spacing: preview.spacing.small) {
            HStack {
                Text(template.title)
                    .font(preview.typography.headline)
                    .foregroundStyle(preview.colors.primaryText)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(preview.colors.accent)
                }
            }

            HStack(spacing: 5) {
                ForEach([preview.colors.accent, preview.colors.info, preview.colors.warning, preview.colors.surface], id: \.description) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(preview.colors.separator, lineWidth: 1))
                }
            }

            Text(template.subtitle)
                .font(preview.typography.caption)
                .foregroundStyle(preview.colors.secondaryText)
                .lineLimit(2)
        }
        .padding(preview.spacing.medium)
        .background(preview.colors.surface, in: RoundedRectangle(cornerRadius: preview.radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: preview.radius.panel, style: .continuous)
                .strokeBorder(isSelected ? preview.colors.accent : preview.colors.separator, lineWidth: isSelected ? preview.stroke.selected : preview.stroke.hairline)
        }
    }
}

private struct PinesPanelModifier: ViewModifier {
    @Environment(\.pinesTheme) private var theme
    let padding: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(padding ?? theme.spacing.medium)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous)
                    .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
            }
            .shadow(color: theme.shadow.panelColor, radius: theme.shadow.panelRadius * 0.35, x: 0, y: theme.shadow.panelY * 0.35)
    }
}

private struct PinesAppBackgroundModifier: ViewModifier {
    @Environment(\.pinesTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.colors.appBackground)
    }
}

extension View {
    func pinesPanel(padding: CGFloat? = nil) -> some View {
        modifier(PinesPanelModifier(padding: padding))
    }

    func pinesAppBackground() -> some View {
        modifier(PinesAppBackgroundModifier())
    }

    @ViewBuilder
    func pinesInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
