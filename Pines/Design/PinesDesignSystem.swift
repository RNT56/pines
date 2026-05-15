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
    var row: PinesThemeRow
    var card: PinesThemeCard
    var dashboard: PinesThemeDashboard
    var ambient: PinesThemeAmbient
    var chart: PinesThemeChart

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
            motion: PinesThemeMotion(template: template),
            row: PinesThemeRow(template: template),
            card: PinesThemeCard(template: template),
            dashboard: PinesThemeDashboard(template: template),
            ambient: PinesThemeAmbient(template: template, scheme: scheme),
            chart: PinesThemeChart(template: template, scheme: scheme)
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
    var backgroundWash: AnyShapeStyle
    var surfaceHighlight: Color
    var surfaceShadow: Color
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
    var controlBorder: Color
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

        switch template {
        case .evergreen:
            glassSurface = AnyShapeStyle(dark ? .regularMaterial : .thinMaterial)
        case .graphite:
            glassSurface = AnyShapeStyle(dark ? .thinMaterial : .regularMaterial)
        case .aurora:
            glassSurface = AnyShapeStyle(.ultraThinMaterial)
        case .paper:
            glassSurface = AnyShapeStyle(dark ? .regularMaterial : .thickMaterial)
        }
        backgroundWash = AnyShapeStyle(
            LinearGradient(
                colors: [
                    appBackground,
                    secondaryBackground.opacity(dark ? 0.72 : 0.82),
                    appBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        surfaceHighlight = dark ? Color.white.opacity(template == .graphite ? 0.05 : 0.08) : Color.white.opacity(template == .paper ? 0.90 : 0.72)
        surfaceShadow = dark ? Color.black.opacity(template == .aurora ? 0.46 : 0.34) : Color.black.opacity(template == .graphite ? 0.08 : 0.10)
        primaryText = dark ? Color(hex: 0xF5F7F6) : Color(hex: 0x151A18)
        secondaryText = dark ? Color(hex: 0xBAC5C1) : Color(hex: 0x4B5652)
        tertiaryText = dark ? Color(hex: 0x87938F) : Color(hex: 0x75807C)
        separator = dark ? Color.white.opacity(template == .graphite ? 0.16 : 0.13) : Color.black.opacity(template == .paper ? 0.10 : 0.11)
        link = info
        codeBackground = dark ? Color.black.opacity(template == .aurora ? 0.36 : 0.30) : Color.black.opacity(template == .paper ? 0.035 : 0.045)
        codeHeaderBackground = dark ? Color.white.opacity(0.06) : Color.black.opacity(template == .paper ? 0.025 : 0.035)
        inlineCodeBackground = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
        quoteBackground = accent.opacity(dark ? 0.13 : 0.08)
        tableHeaderBackground = dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)
        userBubble = dark ? info.opacity(template == .aurora ? 0.28 : 0.22) : info.opacity(template == .graphite ? 0.08 : 0.10)
        assistantBubble = dark ? accent.opacity(template == .paper ? 0.15 : 0.18) : accent.opacity(template == .paper ? 0.075 : 0.09)
        toolBubble = dark ? warning.opacity(0.18) : warning.opacity(0.10)
        sidebarSelection = accent.opacity(dark ? 0.26 : 0.13)
        controlFill = dark ? Color.white.opacity(template == .graphite ? 0.06 : 0.08) : Color.black.opacity(template == .paper ? 0.035 : 0.05)
        controlPressed = dark ? Color.white.opacity(template == .graphite ? 0.12 : 0.14) : Color.black.opacity(0.10)
        controlBorder = dark ? Color.white.opacity(template == .graphite ? 0.18 : 0.14) : Color.black.opacity(template == .paper ? 0.08 : 0.10)
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
        let bodyDesign: Font.Design = template == .graphite ? .default : .rounded
        hero = .system(.largeTitle, design: bodyDesign).weight(titleWeight)
        title = .system(.title2, design: bodyDesign).weight(titleWeight)
        section = .headline.weight(.semibold)
        headline = .subheadline.weight(.semibold)
        body = .system(.body, design: bodyDesign)
        bodyEmphasis = .system(.body, design: bodyDesign).weight(.medium)
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
            control = 7; panel = 9; sheet = 14
        case .paper:
            control = 10; panel = 10; sheet = 16
        case .aurora:
            control = 10; panel = 12; sheet = 20
        default:
            control = 9; panel = 10; sheet = 18
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
        panelColor = scheme == .dark ? Color.black.opacity(template == .aurora ? 0.42 : 0.30) : Color.black.opacity(template == .paper ? 0.06 : 0.10)
        panelRadius = template == .graphite ? 8 : template == .aurora ? 22 : 16
        panelY = template == .graphite ? 3 : template == .paper ? 7 : 9
    }
}

struct PinesThemeMotion {
    var fast: Animation
    var standard: Animation
    var emphasized: Animation
    var selection: Animation
    var cardInsertion: Animation
    var copySuccess: Animation
    var progressUpdate: Animation

    init(template: PinesThemeTemplate) {
        fast = .smooth(duration: 0.18)
        standard = .smooth(duration: template == .paper ? 0.28 : 0.24)
        emphasized = .spring(duration: 0.42, bounce: template == .aurora ? 0.28 : 0.18)
        selection = .smooth(duration: template == .graphite ? 0.14 : 0.18)
        cardInsertion = .spring(duration: template == .aurora ? 0.48 : 0.40, bounce: template == .aurora ? 0.22 : 0.14)
        copySuccess = .spring(duration: 0.34, bounce: 0.20)
        progressUpdate = .smooth(duration: template == .graphite ? 0.16 : 0.24)
    }
}

struct PinesThemeRow: Equatable {
    var minHeight: CGFloat
    var iconTile: CGFloat
    var trailingWidth: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat

    init(template: PinesThemeTemplate) {
        switch template {
        case .graphite:
            minHeight = 66; iconTile = 36; trailingWidth = 74; horizontalPadding = 10; verticalPadding = 8
        case .paper:
            minHeight = 78; iconTile = 40; trailingWidth = 82; horizontalPadding = 12; verticalPadding = 10
        case .aurora:
            minHeight = 74; iconTile = 40; trailingWidth = 82; horizontalPadding = 12; verticalPadding = 10
        case .evergreen:
            minHeight = 72; iconTile = 38; trailingWidth = 78; horizontalPadding = 11; verticalPadding = 9
        }
    }
}

struct PinesThemeCard: Equatable {
    var minHeight: CGFloat
    var headerIconSize: CGFloat
    var sectionSpacing: CGFloat
    var gridMinWidth: CGFloat

    init(template: PinesThemeTemplate) {
        switch template {
        case .graphite:
            minHeight = 96; headerIconSize = 34; sectionSpacing = 12; gridMinWidth = 154
        case .paper:
            minHeight = 116; headerIconSize = 40; sectionSpacing = 18; gridMinWidth = 174
        case .aurora:
            minHeight = 110; headerIconSize = 40; sectionSpacing = 16; gridMinWidth = 168
        case .evergreen:
            minHeight = 104; headerIconSize = 38; sectionSpacing = 14; gridMinWidth = 164
        }
    }
}

struct PinesThemeDashboard: Equatable {
    var tileMinHeight: CGFloat
    var tileMinWidth: CGFloat
    var compactGridMinWidth: CGFloat
    var wideGridMinWidth: CGFloat
    var actionMinHeight: CGFloat
    var chipHeight: CGFloat

    init(template: PinesThemeTemplate) {
        switch template {
        case .graphite:
            tileMinHeight = 86; tileMinWidth = 138; compactGridMinWidth = 132; wideGridMinWidth = 196; actionMinHeight = 38; chipHeight = 28
        case .paper:
            tileMinHeight = 108; tileMinWidth = 156; compactGridMinWidth = 150; wideGridMinWidth = 220; actionMinHeight = 42; chipHeight = 30
        case .aurora:
            tileMinHeight = 104; tileMinWidth = 150; compactGridMinWidth = 144; wideGridMinWidth = 212; actionMinHeight = 42; chipHeight = 30
        case .evergreen:
            tileMinHeight = 98; tileMinWidth = 146; compactGridMinWidth = 140; wideGridMinWidth = 204; actionMinHeight = 40; chipHeight = 29
        }
    }
}

struct PinesThemeAmbient: Equatable {
    var lineOpacity: Double
    var glowOpacity: Double
    var markOpacity: Double
    var drift: CGFloat

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        let dark = scheme == .dark
        switch template {
        case .evergreen:
            lineOpacity = dark ? 0.16 : 0.10; glowOpacity = dark ? 0.18 : 0.10; markOpacity = dark ? 0.10 : 0.07; drift = 10
        case .graphite:
            lineOpacity = dark ? 0.20 : 0.11; glowOpacity = dark ? 0.08 : 0.05; markOpacity = dark ? 0.06 : 0.04; drift = 4
        case .aurora:
            lineOpacity = dark ? 0.18 : 0.09; glowOpacity = dark ? 0.24 : 0.12; markOpacity = dark ? 0.08 : 0.05; drift = 14
        case .paper:
            lineOpacity = dark ? 0.12 : 0.08; glowOpacity = dark ? 0.10 : 0.06; markOpacity = dark ? 0.07 : 0.05; drift = 6
        }
    }
}

struct PinesThemeChart: Equatable {
    var ringLineWidth: CGFloat
    var timelineDot: CGFloat
    var timelineLine: CGFloat

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        ringLineWidth = template == .graphite ? 8 : 9
        timelineDot = template == .paper ? 10 : 9
        timelineLine = template == .graphite ? 1 : 1.3
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
        .background {
            PinesAmbientBackground(animates: true)
            Rectangle()
                .fill(theme.colors.glassSurface)
        }
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
            .minimumScaleFactor(0.78)
            .padding(.horizontal, theme.spacing.small)
            .padding(.vertical, theme.spacing.xsmall)
            .frame(minHeight: 28)
            .background(resolvedTint.opacity(theme.colorScheme == .dark ? 0.18 : 0.12), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(resolvedTint.opacity(0.18), lineWidth: theme.stroke.hairline)
            }
    }
}

struct PinesEmptyState: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(spacing: theme.spacing.medium) {
            PinesEmptyIllustration(systemImage: systemImage)

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let template: PinesThemeTemplate
    let isSelected: Bool

    var body: some View {
        let preview = PinesTheme.resolve(template: template, mode: currentTheme.mode, systemScheme: currentTheme.colorScheme)
        VStack(alignment: .leading, spacing: preview.spacing.small) {
            HStack {
                Text(template.title)
                    .font(preview.typography.headline)
                    .foregroundStyle(preview.colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(preview.colors.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: preview.radius.control, style: .continuous)
                    .fill(preview.colors.secondaryBackground)
                    .frame(height: 16)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: preview.radius.control, style: .continuous)
                            .fill(preview.colors.sidebarSelection)
                            .frame(width: 72, height: 10)
                            .padding(.leading, 8)
                    }

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: preview.radius.control, style: .continuous)
                        .fill(preview.colors.assistantBubble)

                    RoundedRectangle(cornerRadius: preview.radius.control, style: .continuous)
                        .fill(preview.colors.userBubble)

                    RoundedRectangle(cornerRadius: preview.radius.control, style: .continuous)
                        .fill(preview.colors.toolBubble)
                }
                .frame(height: 28)
            }
            .padding(8)
            .background(preview.colors.elevatedSurface, in: RoundedRectangle(cornerRadius: preview.radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: preview.radius.panel, style: .continuous)
                    .strokeBorder(preview.colors.separator, lineWidth: preview.stroke.hairline)
            }

            HStack(spacing: 5) {
                ForEach([preview.colors.accent, preview.colors.info, preview.colors.warning, preview.colors.chartC], id: \.description) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(preview.colors.separator, lineWidth: preview.stroke.hairline))
                }
            }
            .frame(height: 18)

            Text(template.subtitle)
                .font(preview.typography.caption)
                .foregroundStyle(preview.colors.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(preview.spacing.medium)
        .background(preview.colors.surface, in: RoundedRectangle(cornerRadius: preview.radius.sheet, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: preview.radius.sheet, style: .continuous)
                .strokeBorder(isSelected ? preview.colors.accent : preview.colors.separator, lineWidth: isSelected ? preview.stroke.selected : preview.stroke.hairline)
        }
        .shadow(color: preview.shadow.panelColor.opacity(isSelected ? 1 : 0.45), radius: isSelected ? preview.shadow.panelRadius * 0.45 : preview.shadow.panelRadius * 0.22, x: 0, y: isSelected ? preview.shadow.panelY * 0.45 : preview.shadow.panelY * 0.20)
        .scaleEffect(isSelected && !reduceMotion ? 1.015 : 1)
        .animation(reduceMotion ? nil : preview.motion.standard, value: isSelected)
    }
}

enum PinesSurfaceKind {
    case panel
    case elevated
    case glass
    case inset
    case selected
    case chrome
    case code
}

private struct PinesSurfaceModifier: ViewModifier {
    @Environment(\.pinesTheme) private var theme
    let kind: PinesSurfaceKind
    let padding: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding ?? theme.spacing.medium)
            .background(backgroundStyle, in: shape)
            .overlay {
                shape
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .overlay {
                if kind != .inset {
                    shape
                        .strokeBorder(theme.colors.surfaceHighlight.opacity(highlightOpacity), lineWidth: theme.stroke.hairline)
                        .blendMode(.plusLighter)
                }
            }
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var cornerRadius: CGFloat {
        switch kind {
        case .chrome, .glass:
            theme.radius.sheet
        case .code:
            theme.radius.control
        default:
            theme.radius.panel
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch kind {
        case .glass, .chrome:
            theme.colors.glassSurface
        case .elevated, .selected:
            AnyShapeStyle(theme.colors.elevatedSurface)
        case .inset:
            AnyShapeStyle(theme.colors.controlFill)
        case .code:
            AnyShapeStyle(theme.colors.codeBackground)
        case .panel:
            AnyShapeStyle(theme.colors.surface)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .selected:
            theme.colors.accent.opacity(0.72)
        case .glass, .chrome:
            theme.colors.controlBorder
        case .code:
            theme.colors.separator
        case .inset:
            theme.colors.separator.opacity(0.7)
        case .panel, .elevated:
            theme.colors.separator
        }
    }

    private var borderWidth: CGFloat {
        kind == .selected ? theme.stroke.selected : theme.stroke.hairline
    }

    private var highlightOpacity: Double {
        switch kind {
        case .elevated, .selected:
            0.85
        case .glass, .chrome:
            0.70
        case .code:
            0.32
        default:
            0.42
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .inset, .code:
            Color.clear
        case .selected:
            theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.18 : 0.14)
        default:
            theme.shadow.panelColor
        }
    }

    private var shadowRadius: CGFloat {
        switch kind {
        case .elevated, .selected:
            theme.shadow.panelRadius * 0.55
        case .glass, .chrome:
            theme.shadow.panelRadius * 0.40
        case .panel, .code:
            theme.shadow.panelRadius * 0.30
        case .inset:
            0
        }
    }

    private var shadowY: CGFloat {
        switch kind {
        case .elevated, .selected:
            theme.shadow.panelY * 0.55
        case .glass, .chrome:
            theme.shadow.panelY * 0.35
        case .panel, .code:
            theme.shadow.panelY * 0.25
        case .inset:
            0
        }
    }
}

enum PinesButtonKind {
    case primary
    case secondary
    case ghost
    case destructive
    case icon
}

struct PinesButtonStyle: ButtonStyle {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var kind: PinesButtonKind = .secondary
    var fillWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, maxWidth: fillWidth ? .infinity : nil, minHeight: minHeight)
            .background(backgroundStyle(configuration: configuration), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor(configuration: configuration), lineWidth: borderWidth)
            }
            .shadow(color: shadowColor(configuration: configuration), radius: shadowRadius, x: 0, y: shadowY)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .animation(reduceMotion ? nil : theme.motion.fast, value: configuration.isPressed)
    }

    private var font: Font {
        kind == .icon ? theme.typography.caption.weight(.semibold) : theme.typography.callout.weight(.semibold)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            theme.colorScheme == .dark ? Color.black.opacity(0.88) : Color.white
        case .destructive:
            theme.colors.danger
        case .secondary, .ghost, .icon:
            theme.colors.primaryText
        }
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .icon:
            0
        case .ghost:
            theme.spacing.small
        default:
            theme.spacing.medium
        }
    }

    private var minWidth: CGFloat? {
        kind == .icon ? minHeight : nil
    }

    private var minHeight: CGFloat {
        kind == .icon ? 36 : theme.dashboard.actionMinHeight
    }

    private var cornerRadius: CGFloat {
        kind == .icon ? theme.radius.control : theme.radius.control + 2
    }

    private var borderWidth: CGFloat {
        kind == .primary ? 0 : theme.stroke.hairline
    }

    private func backgroundStyle(configuration: Configuration) -> AnyShapeStyle {
        if configuration.isPressed {
            return AnyShapeStyle(kind == .primary ? theme.colors.accent.opacity(0.82) : theme.colors.controlPressed)
        }

        switch kind {
        case .primary:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [theme.colors.accent, theme.colors.chartB.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .secondary, .icon:
            return AnyShapeStyle(theme.colors.controlFill)
        case .ghost:
            return AnyShapeStyle(Color.clear)
        case .destructive:
            return AnyShapeStyle(theme.colors.danger.opacity(theme.colorScheme == .dark ? 0.14 : 0.08))
        }
    }

    private func borderColor(configuration: Configuration) -> Color {
        if configuration.isPressed {
            return theme.colors.focusRing.opacity(0.48)
        }

        switch kind {
        case .primary:
            return Color.clear
        case .destructive:
            return theme.colors.danger.opacity(0.24)
        case .secondary, .icon:
            return theme.colors.controlBorder
        case .ghost:
            return Color.clear
        }
    }

    private func shadowColor(configuration: Configuration) -> Color {
        guard kind == .primary, !configuration.isPressed else {
            return Color.clear
        }
        return theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.20 : 0.16)
    }

    private var shadowRadius: CGFloat {
        kind == .primary ? theme.shadow.panelRadius * 0.35 : 0
    }

    private var shadowY: CGFloat {
        kind == .primary ? theme.shadow.panelY * 0.25 : 0
    }
}

struct PinesStatusIndicator: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var isActive = false
    var size: CGFloat = 9
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if isActive && !reduceMotion {
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: 1)
                        .scaleEffect(pulse ? 2.4 : 1)
                        .opacity(pulse ? 0 : 0.72)
                }
            }
            .shadow(color: color.opacity(theme.colorScheme == .dark ? 0.44 : 0.24), radius: isActive ? 5 : 2, x: 0, y: 0)
            .onAppear {
                guard isActive, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.35).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

struct PinesProgressBar: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double
    var tint: Color?

    private var clampedValue: Double {
        min(1, max(0, value))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.colors.controlFill)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint ?? theme.colors.accent, theme.colors.chartB],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(7, proxy.size.width * clampedValue))
                    .shadow(color: (tint ?? theme.colors.accent).opacity(theme.colorScheme == .dark ? 0.24 : 0.16), radius: 5, x: 0, y: 0)
            }
        }
        .frame(height: 7)
        .animation(reduceMotion ? nil : theme.motion.standard, value: clampedValue)
    }
}

struct PinesAmbientBackground: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animates = false
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(theme.colors.backgroundWash)

                ambientLines(size: proxy.size)
                    .stroke(theme.colors.accent.opacity(theme.ambient.lineOpacity), lineWidth: theme.stroke.hairline)
                    .offset(x: lineOffset)

                Image("PinesMark")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(theme.colors.accent)
                    .opacity(theme.ambient.markOpacity)
                    .frame(width: min(proxy.size.width, proxy.size.height) * 0.46)
                    .rotationEffect(.degrees(theme.template == .aurora ? -8 : 0))
                    .offset(x: proxy.size.width * 0.24, y: -proxy.size.height * 0.20)
                    .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
                    .fill(theme.colors.accent.opacity(theme.ambient.glowOpacity))
                    .blur(radius: 34)
                    .frame(width: proxy.size.width * 0.48, height: 20)
                    .rotationEffect(.degrees(theme.template == .graphite ? 0 : -18))
                    .offset(x: proxy.size.width * 0.16, y: proxy.size.height * 0.38)
            }
            .clipped()
            .onAppear {
                guard animates, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    drift = true
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var lineOffset: CGFloat {
        guard animates, !reduceMotion else { return 0 }
        return drift ? theme.ambient.drift : -theme.ambient.drift * 0.4
    }

    private func ambientLines(size: CGSize) -> Path {
        var path = Path()
        switch theme.template {
        case .graphite:
            for index in 0..<6 {
                let y = CGFloat(index) * max(1, size.height / 5)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y + 10))
            }
        case .paper:
            for index in 0..<5 {
                let y = CGFloat(index) * max(1, size.height / 4)
                path.move(to: CGPoint(x: -20, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width + 20, y: y + 14),
                    control1: CGPoint(x: size.width * 0.32, y: y - 8),
                    control2: CGPoint(x: size.width * 0.68, y: y + 22)
                )
            }
        case .aurora:
            path.move(to: CGPoint(x: -20, y: size.height * 0.28))
            path.addCurve(
                to: CGPoint(x: size.width + 20, y: size.height * 0.22),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.08),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.46)
            )
            path.move(to: CGPoint(x: -20, y: size.height * 0.68))
            path.addCurve(
                to: CGPoint(x: size.width + 20, y: size.height * 0.58),
                control1: CGPoint(x: size.width * 0.30, y: size.height * 0.48),
                control2: CGPoint(x: size.width * 0.72, y: size.height * 0.78)
            )
        case .evergreen:
            path.move(to: CGPoint(x: size.width * 0.10, y: size.height))
            path.addCurve(
                to: CGPoint(x: size.width * 0.84, y: 0),
                control1: CGPoint(x: size.width * 0.12, y: size.height * 0.55),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.34)
            )
        }
        return path
    }
}

struct PinesEmptyIllustration: View {
    @Environment(\.pinesTheme) private var theme
    let systemImage: String

    var body: some View {
        ZStack {
            PinesAmbientBackground()
                .clipShape(Circle())

            Circle()
                .fill(theme.colors.glassSurface)
                .overlay(Circle().strokeBorder(theme.colors.controlBorder, lineWidth: theme.stroke.hairline))

            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 84, height: 84)
        .shadow(color: theme.shadow.panelColor, radius: theme.shadow.panelRadius * 0.45, x: 0, y: theme.shadow.panelY * 0.3)
    }
}

struct PinesSidebarRow<Accessory: View>: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let subtitle: String
    let systemImage: String
    var detail: String?
    var tint: Color?
    var isSelected = false
    var isActive = false
    @ViewBuilder var accessory: () -> Accessory

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        detail: String? = nil,
        tint: Color? = nil,
        isSelected: Bool = false,
        isActive: Bool = false,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.detail = detail
        self.tint = tint
        self.isSelected = isSelected
        self.isActive = isActive
        self.accessory = accessory
    }

    var body: some View {
        let resolvedTint = tint ?? theme.colors.accent
        HStack(spacing: theme.spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                    .fill(isSelected ? resolvedTint.opacity(0.18) : theme.colors.accentSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                            .strokeBorder(resolvedTint.opacity(isSelected ? 0.28 : 0.12), lineWidth: theme.stroke.hairline)
                    }

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(resolvedTint)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.pulse, options: .nonRepeating, value: isActive)
            }
            .frame(width: theme.row.iconTile, height: theme.row.iconTile)

            VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.small) {
                    Text(title)
                        .font(theme.typography.headline)
                        .foregroundStyle(theme.colors.primaryText)
                        .pinesFittingText()

                    Spacer(minLength: theme.spacing.xsmall)

                    if let detail {
                        Text(detail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.tertiaryText)
                            .frame(maxWidth: theme.row.trailingWidth, alignment: .trailing)
                            .pinesFittingText()
                    }
                }

                Text(subtitle)
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }

            accessory()
        }
        .padding(.horizontal, theme.row.horizontalPadding)
        .padding(.vertical, theme.row.verticalPadding)
        .frame(minHeight: theme.row.minHeight)
        .background(isSelected ? theme.colors.sidebarSelection : Color.clear, in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(resolvedTint)
                    .frame(width: 3)
                    .padding(.vertical, theme.spacing.small)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
        .animation(reduceMotion ? nil : theme.motion.selection, value: isSelected)
    }
}

extension PinesSidebarRow where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        detail: String? = nil,
        tint: Color? = nil,
        isSelected: Bool = false,
        isActive: Bool = false
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            detail: detail,
            tint: tint,
            isSelected: isSelected,
            isActive: isActive
        ) {
            EmptyView()
        }
    }
}

struct PinesCardSection<Content: View, Footer: View>: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    var subtitle: String?
    var systemImage: String?
    var kind: PinesSurfaceKind = .panel
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        kind: PinesSurfaceKind = .panel,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.kind = kind
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.card.sectionSpacing) {
            HStack(alignment: .top, spacing: theme.spacing.medium) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: theme.card.headerIconSize, height: theme.card.headerIconSize)
                        .background(theme.colors.accentSoft, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                }

                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    Text(title)
                        .font(theme.typography.section)
                        .foregroundStyle(theme.colors.primaryText)
                        .pinesFittingText()

                    if let subtitle {
                        Text(subtitle)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }
                }
            }

            content()

            footer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: theme.card.minHeight, alignment: .topLeading)
        .pinesSurface(kind, padding: theme.spacing.medium)
    }
}

extension PinesCardSection where Footer == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        kind: PinesSurfaceKind = .panel,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title,
            subtitle: subtitle,
            systemImage: systemImage,
            kind: kind,
            content: content
        ) {
            EmptyView()
        }
    }
}

struct PinesInfoTile: View {
    @Environment(\.pinesTheme) private var theme
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color?
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            HStack(spacing: theme.spacing.small) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint ?? theme.colors.accent)
                        .frame(width: 28, height: 28)
                        .background((tint ?? theme.colors.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
                }

                Text(title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .textCase(.uppercase)
                    .pinesFittingText()
            }

            Text(value)
                .font(theme.typography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            if let detail {
                Text(detail)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
        }
        .frame(maxWidth: .infinity, minHeight: theme.dashboard.tileMinHeight, alignment: .topLeading)
        .pinesSurface(.inset, padding: theme.spacing.medium)
    }
}

struct PinesAdaptiveButtonRow<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: theme.spacing.small)], spacing: theme.spacing.small) {
            content()
        }
    }
}

struct PinesActionBar<Content: View>: View {
    @Environment(\.pinesTheme) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        PinesAdaptiveButtonRow {
            content()
        }
        .padding(theme.spacing.xsmall)
        .background(theme.colors.controlFill, in: RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.sheet, style: .continuous)
                .strokeBorder(theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
        }
    }
}

struct PinesReadinessRing: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double
    let title: String
    let subtitle: String
    var tint: Color?

    private var clampedValue: Double {
        min(1, max(0, value))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.colors.controlFill, lineWidth: theme.chart.ringLineWidth)

            Circle()
                .trim(from: 0, to: clampedValue)
                .stroke(
                    LinearGradient(colors: [tint ?? theme.colors.accent, theme.colors.chartB], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: theme.chart.ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: (tint ?? theme.colors.accent).opacity(0.18), radius: 6, x: 0, y: 0)

            VStack(spacing: theme.spacing.xxsmall) {
                Text("\(Int((clampedValue * 100).rounded()))%")
                    .font(theme.typography.title)
                    .foregroundStyle(theme.colors.primaryText)
                    .contentTransition(.numericText())

                Text(title)
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .pinesFittingText()

                Text(subtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.tertiaryText)
                    .pinesFittingText()
            }
            .padding(theme.spacing.small)
        }
        .frame(width: 152, height: 152)
        .animation(reduceMotion ? nil : theme.motion.progressUpdate, value: clampedValue)
    }
}

struct PinesTimelineItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let isCurrent: Bool

    init(title: String, detail: String, systemImage: String, tint: Color, isCurrent: Bool = false) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.isCurrent = isCurrent
    }

    init(
        title: String,
        subtitle: String,
        detail: String? = nil,
        date: Date? = nil,
        systemImage: String = "circle.fill",
        tint: Color,
        isCurrent: Bool = false
    ) {
        self.title = title
        self.detail = [subtitle, detail, date?.formatted(date: .abbreviated, time: .shortened)]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
        self.systemImage = systemImage
        self.tint = tint
        self.isCurrent = isCurrent
    }
}

struct PinesTimeline: View {
    @Environment(\.pinesTheme) private var theme
    let items: [PinesTimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: theme.spacing.small) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(item.tint.opacity(item.isCurrent ? 0.18 : 0.12))
                                .frame(width: 28, height: 28)

                            Image(systemName: item.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(item.tint)
                        }

                        if index < items.count - 1 {
                            Rectangle()
                                .fill(theme.colors.separator)
                                .frame(width: theme.chart.timelineLine, height: 28)
                        }
                    }

                    VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                        Text(item.title)
                            .font(theme.typography.callout.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .pinesFittingText()

                        Text(item.detail)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                    }
                    .padding(.top, 4)
                    Spacer(minLength: theme.spacing.small)
                }
                .padding(.vertical, theme.spacing.xxsmall)
            }
        }
    }
}

struct PinesKeyValueGrid: View {
    @Environment(\.pinesTheme) private var theme

    struct Item: Hashable {
        var title: String
        var value: String
        var systemImage: String?
        var copyable: Bool

        init(_ title: String, _ value: String, systemImage: String? = nil, copyable: Bool = false) {
            self.title = title
            self.value = value
            self.systemImage = systemImage
            self.copyable = copyable
        }
    }

    let items: [Item]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.dashboard.wideGridMinWidth), spacing: theme.spacing.small)], alignment: .leading, spacing: theme.spacing.small) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: theme.spacing.xxsmall) {
                    HStack(spacing: theme.spacing.xsmall) {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.colors.accent)
                                .frame(width: 16, height: 16)
                        }

                        Text(item.title)
                            .font(theme.typography.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.tertiaryText)
                            .textCase(.uppercase)
                            .pinesFittingText()
                    }

                    Text(item.value)
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contextMenu {
                            if item.copyable {
                                Button {
                                    copyToPasteboard(item.value)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pinesSurface(.inset, padding: theme.spacing.small)
            }
        }
    }
}

private struct PinesAppBackgroundModifier: ViewModifier {
    @Environment(\.pinesTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(theme.colors.backgroundWash)
    }
}

private struct PinesFieldChromeModifier: ViewModifier {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.primaryText)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .minimumScaleFactor(0.86)
            .padding(.horizontal, theme.spacing.medium)
            .frame(minHeight: max(46, theme.dashboard.actionMinHeight + 8), alignment: .center)
            .background(theme.colors.controlFill.opacity(isEnabled ? 1 : 0.58), in: RoundedRectangle(cornerRadius: theme.radius.control + 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.control + 2, style: .continuous)
                    .strokeBorder(theme.colors.controlBorder.opacity(isEnabled ? 1 : 0.6), lineWidth: theme.stroke.hairline)
            }
    }
}

extension View {
    func pinesPanel(padding: CGFloat? = nil) -> some View {
        modifier(PinesSurfaceModifier(kind: .panel, padding: padding))
    }

    func pinesSurface(_ kind: PinesSurfaceKind = .panel, padding: CGFloat? = nil) -> some View {
        modifier(PinesSurfaceModifier(kind: kind, padding: padding))
    }

    func pinesAppBackground() -> some View {
        modifier(PinesAppBackgroundModifier())
    }

    func pinesFieldChrome() -> some View {
        modifier(PinesFieldChromeModifier())
    }

    func pinesButtonStyle(_ kind: PinesButtonKind = .secondary, fillWidth: Bool = false) -> some View {
        buttonStyle(PinesButtonStyle(kind: kind, fillWidth: fillWidth))
    }

    func pinesFittingText(lines: Int = 1, minimumScale: CGFloat = 0.78) -> some View {
        lineLimit(lines)
            .minimumScaleFactor(minimumScale)
            .allowsTightening(true)
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
