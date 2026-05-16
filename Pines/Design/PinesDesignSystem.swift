import SwiftUI

enum PinesThemeTemplate: String, CaseIterable, Identifiable {
    case evergreen
    case graphite
    case aurora
    case paper
    case slate
    case porcelain
    case sunset
    case obsidian

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
        case .slate:
            "Slate"
        case .porcelain:
            "Porcelain"
        case .sunset:
            "Sunset"
        case .obsidian:
            "Obsidian"
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
        case .slate:
            "Technical blue-gray workspace with quiet precision."
        case .porcelain:
            "Warm ceramic minimalism with fine editorial contrast."
        case .sunset:
            "Bitcoin-orange workspace with warm copper glass."
        case .obsidian:
            "Dark-first pro console with restrained luminous accents."
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
    var contentBackground: Color
    var sidebarBackground: Color
    var sheetBackground: Color
    var secondaryBackground: Color
    var surface: Color
    var elevatedSurface: Color
    var cardBackground: Color
    var cardBorder: Color
    var glassSurface: AnyShapeStyle
    var backgroundWash: AnyShapeStyle
    var surfaceHighlight: Color
    var primaryText: Color
    var secondaryText: Color
    var tertiaryText: Color
    var placeholderText: Color
    var disabledText: Color
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
    var successSoft: Color
    var warning: Color
    var warningSoft: Color
    var danger: Color
    var dangerSoft: Color
    var info: Color
    var infoSoft: Color
    var userBubble: Color
    var assistantBubble: Color
    var toolBubble: Color
    var sidebarSelection: Color
    var listRowHover: Color
    var listRowPressed: Color
    var controlFill: Color
    var disabledFill: Color
    var controlPressed: Color
    var controlBorder: Color
    var focusRing: Color
    var modalScrim: Color
    var chartA: Color
    var chartB: Color
    var chartC: Color

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        let dark = scheme == .dark
        switch template {
        case .evergreen:
            appBackground = dark ? Color(hex: 0x06130F) : Color(hex: 0xF4F8F3)
            secondaryBackground = dark ? Color(hex: 0x0A1B16) : Color(hex: 0xE8F0E9)
            surface = dark ? Color(hex: 0x0F241E) : Color(hex: 0xFBFCFA)
            elevatedSurface = dark ? Color(hex: 0x163129) : Color(hex: 0xFFFFFF)
            accent = dark ? Color(hex: 0x6FE3C2) : Color(hex: 0x087A55)
            accentSoft = accent.opacity(dark ? 0.20 : 0.12)
            success = Color(hex: dark ? 0x66D19E : 0x167A4A)
            warning = Color(hex: dark ? 0xF1BE66 : 0xB86E12)
            danger = Color(hex: dark ? 0xFF8D85 : 0xC73A34)
            info = Color(hex: dark ? 0x86B7FF : 0x2459C7)
            chartA = accent
            chartB = Color(hex: dark ? 0x7FB3FF : 0x2D67D8)
            chartC = Color(hex: dark ? 0xF1BE66 : 0xD48A18)
        case .graphite:
            appBackground = dark ? Color(hex: 0x0A0B0D) : Color(hex: 0xF3F5F7)
            secondaryBackground = dark ? Color(hex: 0x111316) : Color(hex: 0xE6E9EE)
            surface = dark ? Color(hex: 0x181B20) : Color(hex: 0xFCFCFD)
            elevatedSurface = dark ? Color(hex: 0x22262D) : Color(hex: 0xFFFFFF)
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
            appBackground = dark ? Color(hex: 0x080D20) : Color(hex: 0xF5F8FF)
            secondaryBackground = dark ? Color(hex: 0x0D1430) : Color(hex: 0xE8F0FF)
            surface = dark ? Color(hex: 0x121A35) : Color(hex: 0xFFFFFF)
            elevatedSurface = dark ? Color(hex: 0x182142) : Color(hex: 0xFAFCFF)
            accent = dark ? Color(hex: 0x72D8F4) : Color(hex: 0x1B69C8)
            accentSoft = accent.opacity(dark ? 0.16 : 0.11)
            success = Color(hex: dark ? 0x7BE1B4 : 0x0F766E)
            warning = Color(hex: dark ? 0xE8C66A : 0xB45309)
            danger = Color(hex: dark ? 0xF58CA5 : 0xBE123C)
            info = Color(hex: dark ? 0xA99BFF : 0x6D28D9)
            chartA = accent
            chartB = Color(hex: dark ? 0xA99BFF : 0x7C3AED)
            chartC = Color(hex: dark ? 0x7BE1B4 : 0x0D9488)
        case .paper:
            appBackground = dark ? Color(hex: 0x111412) : Color(hex: 0xFAF6EC)
            secondaryBackground = dark ? Color(hex: 0x181D19) : Color(hex: 0xEFE6D6)
            surface = dark ? Color(hex: 0x20251F) : Color(hex: 0xFFF9EE)
            elevatedSurface = dark ? Color(hex: 0x292F28) : Color(hex: 0xFFFDF7)
            accent = dark ? Color(hex: 0xBBD8C1) : Color(hex: 0x376B4F)
            accentSoft = accent.opacity(dark ? 0.20 : 0.12)
            success = Color(hex: dark ? 0xA7D7A4 : 0x397A3E)
            warning = Color(hex: dark ? 0xDDC17A : 0x9A6415)
            danger = Color(hex: dark ? 0xDF9B90 : 0xA33A2C)
            info = Color(hex: dark ? 0x9FBCEB : 0x315E9E)
            chartA = accent
            chartB = Color(hex: dark ? 0xC9B073 : 0xA16C19)
            chartC = Color(hex: dark ? 0xA7B8D8 : 0x476B9E)
        case .slate:
            appBackground = dark ? Color(hex: 0x071216) : Color(hex: 0xEEF4F7)
            secondaryBackground = dark ? Color(hex: 0x0C1C23) : Color(hex: 0xD8E6EC)
            surface = dark ? Color(hex: 0x132A34) : Color(hex: 0xF7FBFD)
            elevatedSurface = dark ? Color(hex: 0x1B3844) : Color(hex: 0xFFFFFF)
            accent = dark ? Color(hex: 0x7DD6E8) : Color(hex: 0x205F74)
            accentSoft = accent.opacity(dark ? 0.20 : 0.12)
            success = Color(hex: dark ? 0x83D7A6 : 0x207A52)
            warning = Color(hex: dark ? 0xEAC36A : 0x996016)
            danger = Color(hex: dark ? 0xF09389 : 0xB43A31)
            info = Color(hex: dark ? 0x91B8FF : 0x315E9C)
            chartA = accent
            chartB = Color(hex: dark ? 0x91B8FF : 0x315E9C)
            chartC = Color(hex: dark ? 0x83D7A6 : 0x1E7F6D)
        case .porcelain:
            appBackground = dark ? Color(hex: 0x121111) : Color(hex: 0xFAF9F5)
            secondaryBackground = dark ? Color(hex: 0x1B191A) : Color(hex: 0xF0ECE3)
            surface = dark ? Color(hex: 0x242223) : Color(hex: 0xFFFDF8)
            elevatedSurface = dark ? Color(hex: 0x302D2F) : Color(hex: 0xFFFFFF)
            accent = dark ? Color(hex: 0xD9B9CC) : Color(hex: 0x7B5B70)
            accentSoft = accent.opacity(dark ? 0.18 : 0.095)
            success = Color(hex: dark ? 0x9ED9B6 : 0x33775B)
            warning = Color(hex: dark ? 0xE8C678 : 0xA16622)
            danger = Color(hex: dark ? 0xEFA092 : 0xA84239)
            info = Color(hex: dark ? 0xAFC2EA : 0x486795)
            chartA = accent
            chartB = Color(hex: dark ? 0xAFC2EA : 0x486795)
            chartC = Color(hex: dark ? 0x9ED9B6 : 0x33775B)
        case .sunset:
            appBackground = dark ? Color(hex: 0x130B05) : Color(hex: 0xFFF5EA)
            secondaryBackground = dark ? Color(hex: 0x211208) : Color(hex: 0xF4E0C8)
            surface = dark ? Color(hex: 0x2A180C) : Color(hex: 0xFFF9F2)
            elevatedSurface = dark ? Color(hex: 0x382111) : Color(hex: 0xFFFFFF)
            accent = dark ? Color(hex: 0xFFB15B) : Color(hex: 0xD66B00)
            accentSoft = accent.opacity(dark ? 0.20 : 0.11)
            success = Color(hex: dark ? 0xA4D98F : 0x3F7C31)
            warning = Color(hex: dark ? 0xFFD071 : 0xB86A00)
            danger = Color(hex: dark ? 0xFF987D : 0xB83B25)
            info = Color(hex: dark ? 0x8DB7FF : 0x315E9E)
            chartA = accent
            chartB = Color(hex: dark ? 0xFFD071 : 0xF7931A)
            chartC = Color(hex: dark ? 0x8DB7FF : 0x315E9E)
        case .obsidian:
            appBackground = dark ? Color(hex: 0x050607) : Color(hex: 0xF2F4F4)
            secondaryBackground = dark ? Color(hex: 0x0A0D0E) : Color(hex: 0xE3E7E7)
            surface = dark ? Color(hex: 0x111719) : Color(hex: 0xFBFCFC)
            elevatedSurface = dark ? Color(hex: 0x182124) : Color(hex: 0xFFFFFF)
            accent = dark ? Color(hex: 0x5EE0C4) : Color(hex: 0x0D7668)
            accentSoft = accent.opacity(dark ? 0.18 : 0.10)
            success = Color(hex: dark ? 0x72D49F : 0x17784B)
            warning = Color(hex: dark ? 0xE8C067 : 0x9E6416)
            danger = Color(hex: dark ? 0xF08F87 : 0xB73A31)
            info = Color(hex: dark ? 0x86A8FF : 0x255CC7)
            chartA = accent
            chartB = Color(hex: dark ? 0x86A8FF : 0x255CC7)
            chartC = Color(hex: dark ? 0xE8C067 : 0xA87718)
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
        case .slate:
            glassSurface = AnyShapeStyle(dark ? .regularMaterial : .thinMaterial)
        case .porcelain:
            glassSurface = AnyShapeStyle(dark ? .regularMaterial : .thickMaterial)
        case .sunset:
            glassSurface = AnyShapeStyle(dark ? .regularMaterial : .thinMaterial)
        case .obsidian:
            glassSurface = AnyShapeStyle(dark ? .thinMaterial : .regularMaterial)
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
        surfaceHighlight = dark ? Color.white.opacity(template == .graphite || template == .obsidian ? 0.05 : 0.08) : Color.white.opacity(template == .paper || template == .porcelain || template == .sunset ? 0.90 : 0.72)
        primaryText = dark ? Color(hex: 0xF5F7F6) : Color(hex: 0x151A18)
        secondaryText = dark ? Color(hex: 0xBAC5C1) : Color(hex: 0x4B5652)
        tertiaryText = dark ? Color(hex: 0x87938F) : Color(hex: 0x75807C)
        placeholderText = tertiaryText.opacity(dark ? 0.88 : 0.92)
        disabledText = tertiaryText.opacity(dark ? 0.58 : 0.64)
        separator = dark ? Color.white.opacity(template == .graphite || template == .obsidian ? 0.16 : 0.13) : Color.black.opacity(template == .paper || template == .porcelain || template == .sunset ? 0.10 : 0.11)
        link = info
        codeBackground = dark ? Color.black.opacity(template == .aurora ? 0.34 : 0.30) : Color.black.opacity(template == .paper || template == .porcelain || template == .sunset ? 0.035 : 0.045)
        codeHeaderBackground = dark ? Color.white.opacity(0.06) : Color.black.opacity(template == .paper || template == .porcelain || template == .sunset ? 0.025 : 0.035)
        inlineCodeBackground = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
        quoteBackground = accent.opacity(dark ? 0.13 : 0.08)
        tableHeaderBackground = dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04)
        successSoft = success.opacity(dark ? 0.18 : 0.10)
        warningSoft = warning.opacity(dark ? 0.18 : 0.10)
        dangerSoft = danger.opacity(dark ? 0.17 : 0.09)
        infoSoft = info.opacity(dark ? 0.18 : 0.10)
        userBubble = dark ? info.opacity(template == .aurora ? 0.20 : 0.22) : info.opacity(template == .graphite || template == .obsidian ? 0.08 : 0.10)
        assistantBubble = dark ? accent.opacity(template == .paper || template == .porcelain ? 0.15 : 0.18) : accent.opacity(template == .paper || template == .porcelain ? 0.075 : 0.09)
        toolBubble = dark ? warning.opacity(0.18) : warning.opacity(0.10)
        sidebarSelection = accent.opacity(dark ? (template == .aurora ? 0.18 : 0.26) : 0.13)
        listRowHover = accent.opacity(dark ? (template == .aurora ? 0.08 : 0.12) : 0.07)
        listRowPressed = accent.opacity(dark ? (template == .aurora ? 0.13 : 0.18) : 0.11)
        controlFill = dark ? Color.white.opacity(template == .graphite || template == .obsidian ? 0.06 : 0.08) : Color.black.opacity(template == .paper || template == .porcelain || template == .sunset ? 0.035 : 0.05)
        disabledFill = controlFill.opacity(dark ? 0.58 : 0.62)
        controlPressed = dark ? Color.white.opacity(template == .graphite || template == .obsidian ? 0.12 : 0.14) : Color.black.opacity(0.10)
        controlBorder = dark ? Color.white.opacity(template == .graphite || template == .obsidian ? 0.18 : 0.14) : Color.black.opacity(template == .paper || template == .porcelain || template == .sunset ? 0.08 : 0.10)
        focusRing = accent.opacity(0.72)
        modalScrim = Color.black.opacity(dark ? 0.48 : 0.28)
        contentBackground = appBackground
        sidebarBackground = secondaryBackground
        sheetBackground = dark ? surface : elevatedSurface
        cardBackground = surface
        cardBorder = separator

        switch template {
        case .aurora where dark:
            contentBackground = Color(hex: 0x080D20)
            sidebarBackground = Color(hex: 0x0B1028)
            sheetBackground = Color(hex: 0x121A35)
            cardBackground = Color(hex: 0x121A35)
            cardBorder = Color.white.opacity(0.105)
            controlFill = Color.white.opacity(0.065)
            controlBorder = Color.white.opacity(0.12)
            toolBubble = warning.opacity(0.14)
        case .paper where dark:
            contentBackground = Color(hex: 0x111412)
            sidebarBackground = Color(hex: 0x171B17)
            sheetBackground = Color(hex: 0x20251F)
            cardBackground = Color(hex: 0x20251F)
            cardBorder = Color.white.opacity(0.11)
            controlFill = Color.white.opacity(0.07)
            controlBorder = Color.white.opacity(0.12)
        case .paper:
            contentBackground = Color(hex: 0xFAF6EC)
            sidebarBackground = Color(hex: 0xEFE6D6)
            sheetBackground = Color(hex: 0xFFF9EE)
            cardBackground = Color(hex: 0xFFF8EC)
            cardBorder = Color.black.opacity(0.085)
        case .slate where !dark:
            sidebarBackground = Color(hex: 0xD8E6EC)
            cardBackground = Color(hex: 0xF6FBFD)
            cardBorder = Color(hex: 0x9BB5C1).opacity(0.34)
        case .porcelain where !dark:
            sidebarBackground = Color(hex: 0xF0ECE3)
            cardBackground = Color(hex: 0xFFFDF8)
            cardBorder = Color(hex: 0xD8CEC2).opacity(0.48)
        case .sunset where dark:
            sidebarBackground = Color(hex: 0x1D1008)
            cardBackground = Color(hex: 0x2A180C)
            cardBorder = Color(hex: 0xFFB15B).opacity(0.16)
            controlFill = Color.white.opacity(0.075)
            controlBorder = Color(hex: 0xFFB15B).opacity(0.18)
        case .sunset:
            sidebarBackground = Color(hex: 0xF4E0C8)
            cardBackground = Color(hex: 0xFFF3E5)
            cardBorder = Color(hex: 0xD66B00).opacity(0.16)
        default:
            break
        }
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
        let titleWeight: Font.Weight = template == .paper || template == .porcelain ? .semibold : .bold
        let bodyDesign: Font.Design = template == .graphite || template == .obsidian ? .default : .rounded
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
        case .graphite, .obsidian:
            xxsmall = 3; xsmall = 6; small = 9; medium = 12; large = 18; xlarge = 24; xxlarge = 32; contentMaxWidth = 820
        case .paper, .porcelain:
            xxsmall = 5; xsmall = 8; small = 12; medium = 16; large = 24; xlarge = 34; xxlarge = 44; contentMaxWidth = 720
        case .slate:
            xxsmall = 4; xsmall = 6; small = 10; medium = 14; large = 20; xlarge = 28; xxlarge = 36; contentMaxWidth = 800
        case .sunset:
            xxsmall = 4; xsmall = 7; small = 11; medium = 15; large = 22; xlarge = 30; xxlarge = 40; contentMaxWidth = 760
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
        case .obsidian:
            control = 8; panel = 9; sheet = 14
        case .paper:
            control = 10; panel = 10; sheet = 16
        case .porcelain:
            control = 10; panel = 12; sheet = 18
        case .sunset:
            control = 10; panel = 11; sheet = 18
        case .slate:
            control = 8; panel = 10; sheet = 16
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

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        hairline = template == .graphite || template == .obsidian ? 0.7 : 1
        selected = 1.5
    }
}

struct PinesThemeShadow: Equatable {
    var panelColor: Color
    var panelRadius: CGFloat
    var panelY: CGFloat

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        switch template {
        case .graphite:
            panelColor = scheme == .dark ? Color.black.opacity(0.30) : Color.black.opacity(0.08)
            panelRadius = 8
            panelY = 3
        case .obsidian:
            panelColor = scheme == .dark ? Color.black.opacity(0.46) : Color.black.opacity(0.08)
            panelRadius = 10
            panelY = 4
        case .aurora:
            panelColor = scheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.10)
            panelRadius = 22
            panelY = 9
        case .paper, .porcelain:
            panelColor = scheme == .dark ? Color.black.opacity(0.30) : Color.black.opacity(0.06)
            panelRadius = 16
            panelY = 7
        case .sunset:
            panelColor = scheme == .dark ? Color.black.opacity(0.36) : Color(hex: 0x7A3A00).opacity(0.08)
            panelRadius = 17
            panelY = 8
        case .slate, .evergreen:
            panelColor = scheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.09)
            panelRadius = 15
            panelY = 8
        }
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
        standard = .smooth(duration: template == .paper || template == .porcelain ? 0.28 : 0.24)
        emphasized = .spring(duration: 0.42, bounce: template == .aurora ? 0.28 : 0.18)
        selection = .smooth(duration: template == .graphite || template == .obsidian ? 0.14 : 0.18)
        cardInsertion = .spring(duration: template == .aurora ? 0.48 : 0.40, bounce: template == .aurora ? 0.22 : 0.14)
        copySuccess = .spring(duration: 0.34, bounce: 0.20)
        progressUpdate = .smooth(duration: template == .graphite || template == .obsidian ? 0.16 : 0.24)
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
        case .graphite, .obsidian:
            minHeight = 66; iconTile = 36; trailingWidth = 74; horizontalPadding = 10; verticalPadding = 8
        case .paper, .porcelain, .sunset:
            minHeight = 78; iconTile = 40; trailingWidth = 82; horizontalPadding = 12; verticalPadding = 10
        case .aurora, .slate:
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
        case .graphite, .obsidian:
            minHeight = 96; headerIconSize = 34; sectionSpacing = 12; gridMinWidth = 154
        case .paper, .porcelain, .sunset:
            minHeight = 116; headerIconSize = 40; sectionSpacing = 18; gridMinWidth = 174
        case .aurora, .slate:
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
        case .graphite, .obsidian:
            tileMinHeight = 86; tileMinWidth = 138; compactGridMinWidth = 132; wideGridMinWidth = 196; actionMinHeight = 38; chipHeight = 28
        case .paper, .porcelain, .sunset:
            tileMinHeight = 108; tileMinWidth = 156; compactGridMinWidth = 150; wideGridMinWidth = 220; actionMinHeight = 42; chipHeight = 30
        case .aurora, .slate:
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
        case .slate:
            lineOpacity = dark ? 0.15 : 0.09; glowOpacity = dark ? 0.13 : 0.07; markOpacity = dark ? 0.07 : 0.05; drift = 8
        case .porcelain:
            lineOpacity = dark ? 0.10 : 0.07; glowOpacity = dark ? 0.08 : 0.05; markOpacity = dark ? 0.05 : 0.035; drift = 5
        case .sunset:
            lineOpacity = dark ? 0.14 : 0.08; glowOpacity = dark ? 0.16 : 0.09; markOpacity = dark ? 0.07 : 0.045; drift = 8
        case .obsidian:
            lineOpacity = dark ? 0.18 : 0.10; glowOpacity = dark ? 0.16 : 0.06; markOpacity = dark ? 0.08 : 0.04; drift = 4
        }
    }
}

struct PinesThemeChart: Equatable {
    var ringLineWidth: CGFloat
    var timelineDot: CGFloat
    var timelineLine: CGFloat

    init(template: PinesThemeTemplate, scheme: ColorScheme) {
        ringLineWidth = template == .graphite || template == .obsidian ? 8 : 9
        timelineDot = template == .paper || template == .porcelain ? 10 : 9
        timelineLine = template == .graphite || template == .obsidian ? 1 : 1.3
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
    @State private var didAppear = false

    private let stages = [
        PinesBootStage(title: "Runtime", systemImage: "cpu", tint: .accent),
        PinesBootStage(title: "Vault", systemImage: "shippingbox", tint: .warning),
        PinesBootStage(title: "Tools", systemImage: "wrench.and.screwdriver", tint: .info),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PinesAmbientBackground(animates: true)
                    .ignoresSafeArea()

                PinesBootSignalField(isActive: didAppear && !reduceMotion)
                    .ignoresSafeArea()

                VStack(spacing: theme.spacing.xlarge) {
                    PinesBootMarkCluster(isActive: didAppear && !reduceMotion)
                        .scaleEffect(didAppear || reduceMotion ? 1 : 0.9)
                        .opacity(didAppear ? 1 : 0)

                    VStack(spacing: theme.spacing.small) {
                        Text("pines")
                            .font(theme.typography.hero)
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text("Local-first AI workbench")
                            .font(theme.typography.callout)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .offset(y: didAppear || reduceMotion ? 0 : 10)
                    .opacity(didAppear ? 1 : 0)

                    HStack(spacing: theme.spacing.small) {
                        ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                            PinesBootStageChip(
                                stage: stage,
                                isActive: didAppear,
                                delay: Double(index) * 0.12
                            )
                        }
                    }

                    VStack(spacing: theme.spacing.small) {
                        PinesBootSignalBar(isActive: didAppear && !reduceMotion)

                        Text("Starting private workspace")
                            .font(theme.typography.caption.weight(.medium))
                            .foregroundStyle(theme.colors.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .opacity(didAppear ? 1 : 0)
                }
                .frame(width: max(0, min(430, proxy.size.width - 32)))
                .padding(.horizontal, theme.spacing.large)
                .padding(.vertical, theme.spacing.xxlarge)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .background(theme.colors.appBackground)
        .onAppear {
            guard !didAppear else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.68, bounce: 0.24)) {
                didAppear = true
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: reduceMotion ? .identity : .scale(scale: 0.96)),
            removal: .opacity.combined(with: reduceMotion ? .identity : .scale(scale: 1.04))
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pines is starting")
    }
}

private struct PinesBootStage: Identifiable {
    enum Tint {
        case accent
        case info
        case warning

        func color(in theme: PinesTheme) -> Color {
            switch self {
            case .accent:
                theme.colors.accent
            case .info:
                theme.colors.info
            case .warning:
                theme.colors.warning
            }
        }
    }

    var id: String { title }
    let title: String
    let systemImage: String
    let tint: Tint
}

private struct PinesBootMarkCluster: View {
    @Environment(\.pinesTheme) private var theme
    let isActive: Bool
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let diameter = 130 + CGFloat(index * 30)
                Circle()
                    .stroke(
                        ringGradient(for: index),
                        style: StrokeStyle(lineWidth: index == 0 ? 2.2 : 1.3, lineCap: .round)
                    )
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(pulse ? 1.08 + CGFloat(index) * 0.035 : 0.92)
                    .opacity(pulse ? 0.14 : 0.48 - Double(index) * 0.10)
                    .animation(
                        isActive ? .easeOut(duration: 1.7).repeatForever(autoreverses: false).delay(Double(index) * 0.18) : nil,
                        value: pulse
                    )
            }

            Circle()
                .trim(from: 0.05, to: 0.70)
                .stroke(
                    AngularGradient(
                        colors: [
                            theme.colors.accent,
                            theme.colors.chartB,
                            theme.colors.warning,
                            theme.colors.accent,
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 154, height: 154)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .shadow(color: theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.32 : 0.20), radius: 12, x: 0, y: 0)
                .animation(isActive ? .linear(duration: 3.1).repeatForever(autoreverses: false) : nil, value: spin)

            Circle()
                .trim(from: 0.62, to: 0.92)
                .stroke(
                    theme.colors.info.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
                .frame(width: 178, height: 178)
                .rotationEffect(.degrees(spin ? -360 : 0))
                .animation(isActive ? .linear(duration: 4.8).repeatForever(autoreverses: false) : nil, value: spin)

            PinesMark(size: 116)
                .shadow(color: theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.32 : 0.16), radius: 22, x: 0, y: 12)
        }
        .frame(width: 200, height: 200)
        .onAppear {
            guard isActive else { return }
            spin = true
            pulse = true
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            spin = true
            pulse = true
        }
        .accessibilityHidden(true)
    }

    private func ringGradient(for index: Int) -> AngularGradient {
        AngularGradient(
            colors: [
                theme.colors.accent.opacity(index == 0 ? 0.92 : 0.52),
                theme.colors.info.opacity(index == 1 ? 0.78 : 0.42),
                theme.colors.warning.opacity(index == 2 ? 0.72 : 0.34),
                theme.colors.accent.opacity(index == 0 ? 0.92 : 0.52),
            ],
            center: .center
        )
    }
}

private struct PinesBootStageChip: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: PinesBootStage
    let isActive: Bool
    let delay: Double

    var body: some View {
        let tint = stage.tint.color(in: theme)
        VStack(spacing: theme.spacing.xsmall) {
            Image(systemName: stage.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating.speed(0.55), value: isActive && !reduceMotion)

            Text(stage.title)
                .font(theme.typography.caption.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(tint.opacity(theme.colorScheme == .dark ? 0.14 : 0.10), in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: theme.stroke.hairline)
        }
        .opacity(isActive ? 1 : 0)
        .offset(y: isActive || reduceMotion ? 0 : 12)
        .animation(reduceMotion ? nil : .spring(duration: 0.54, bounce: 0.24).delay(delay), value: isActive)
    }
}

private struct PinesBootSignalBar: View {
    @Environment(\.pinesTheme) private var theme
    let isActive: Bool
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.colors.controlFill)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.colors.accent.opacity(0.15),
                                theme.colors.accent,
                                theme.colors.chartB,
                                theme.colors.warning.opacity(0.88),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.62)
                    .offset(x: isActive ? (sweep ? proxy.size.width * 0.62 : -proxy.size.width * 0.18) : proxy.size.width * 0.14)
                    .shadow(color: theme.colors.accent.opacity(theme.colorScheme == .dark ? 0.34 : 0.22), radius: 8, x: 0, y: 0)
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
            }
        }
        .frame(height: 8)
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PinesBootSignalField: View {
    @Environment(\.pinesTheme) private var theme
    let isActive: Bool
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(theme.colors.appBackground.opacity(theme.colorScheme == .dark ? 0.26 : 0.18))

                ForEach(0..<7, id: \.self) { index in
                    let y = proxy.size.height * (0.12 + CGFloat(index) * 0.13)
                    RoundedRectangle(cornerRadius: theme.radius.capsule, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    signalColor(for: index).opacity(0.34),
                                    Color.clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.72, height: index.isMultiple(of: 2) ? 2 : 1)
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -16 : 12))
                        .position(
                            x: sweep ? proxy.size.width * 0.62 : proxy.size.width * 0.38,
                            y: y
                        )
                        .opacity(theme.colorScheme == .dark ? 0.68 : 0.44)
                }

                bootTracePath(size: proxy.size)
                    .trim(from: sweep ? 0.10 : 0, to: sweep ? 1 : 0.82)
                    .stroke(
                        LinearGradient(
                            colors: [
                                theme.colors.accent.opacity(0.10),
                                theme.colors.chartB.opacity(0.26),
                                theme.colors.warning.opacity(0.20),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: theme.stroke.hairline, lineCap: .round, lineJoin: .round)
                    )
                    .opacity(theme.colorScheme == .dark ? 0.82 : 0.54)
            }
            .clipped()
        }
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func signalColor(for index: Int) -> Color {
        switch index % 3 {
        case 0:
            theme.colors.accent
        case 1:
            theme.colors.info
        default:
            theme.colors.warning
        }
    }

    private func bootTracePath(size: CGSize) -> Path {
        var path = Path()
        let columns: [CGFloat] = [0.08, 0.24, 0.42, 0.64, 0.82]
        for (index, column) in columns.enumerated() {
            let x = size.width * column
            path.move(to: CGPoint(x: x, y: size.height * 0.08))
            path.addLine(to: CGPoint(x: x + CGFloat(index % 2 == 0 ? 18 : -18), y: size.height * 0.38))
            path.addLine(to: CGPoint(x: x + CGFloat(index % 2 == 0 ? -8 : 8), y: size.height * 0.66))
            path.addLine(to: CGPoint(x: x, y: size.height * 0.92))
        }
        return path
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
            AnyShapeStyle(theme.colors.cardBackground)
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
            theme.colors.cardBorder
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
    @Environment(\.isEnabled) private var isEnabled
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
        guard isEnabled else {
            return theme.colors.disabledText
        }

        switch kind {
        case .primary:
            return theme.colorScheme == .dark ? Color.black.opacity(0.88) : Color.white
        case .destructive:
            return theme.colors.danger
        case .secondary, .ghost, .icon:
            return theme.colors.primaryText
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
        guard isEnabled else {
            return AnyShapeStyle(theme.colors.disabledFill)
        }

        if configuration.isPressed {
            return AnyShapeStyle(kind == .primary ? theme.colors.accent.opacity(0.82) : theme.colors.listRowPressed)
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
        guard isEnabled else {
            return theme.colors.controlBorder.opacity(0.55)
        }

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
        guard isEnabled, kind == .primary, !configuration.isPressed else {
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
        case .slate:
            for index in 0..<5 {
                let y = CGFloat(index) * max(1, size.height / 4)
                path.move(to: CGPoint(x: -20, y: y + 8))
                path.addLine(to: CGPoint(x: size.width + 20, y: y - 10))
            }
            path.move(to: CGPoint(x: size.width * 0.18, y: size.height))
            path.addCurve(
                to: CGPoint(x: size.width * 0.74, y: 0),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.62),
                control2: CGPoint(x: size.width * 0.58, y: size.height * 0.36)
            )
        case .porcelain:
            for index in 0..<4 {
                let y = CGFloat(index) * max(1, size.height / 3)
                path.move(to: CGPoint(x: -20, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width + 20, y: y + 8),
                    control1: CGPoint(x: size.width * 0.24, y: y + 10),
                    control2: CGPoint(x: size.width * 0.72, y: y - 12)
                )
            }
        case .sunset:
            path.move(to: CGPoint(x: -20, y: size.height * 0.22))
            path.addCurve(
                to: CGPoint(x: size.width + 20, y: size.height * 0.34),
                control1: CGPoint(x: size.width * 0.24, y: size.height * 0.04),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.52)
            )
            path.move(to: CGPoint(x: -20, y: size.height * 0.72))
            path.addCurve(
                to: CGPoint(x: size.width + 20, y: size.height * 0.60),
                control1: CGPoint(x: size.width * 0.30, y: size.height * 0.54),
                control2: CGPoint(x: size.width * 0.68, y: size.height * 0.82)
            )
        case .obsidian:
            for index in 0..<7 {
                let x = CGFloat(index) * max(1, size.width / 6)
                path.move(to: CGPoint(x: x, y: -20))
                path.addLine(to: CGPoint(x: x + 14, y: size.height + 20))
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
        .background(rowBackground, in: RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.panel, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: theme.stroke.hairline)
        }
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

    private var rowBackground: Color {
        if isSelected {
            return theme.colors.sidebarSelection
        }
        return theme.colors.cardBackground.opacity(theme.colorScheme == .dark ? 0.34 : 0.72)
    }

    private var rowBorder: Color {
        if isSelected {
            return (tint ?? theme.colors.accent).opacity(0.18)
        }
        return theme.colors.cardBorder.opacity(theme.colorScheme == .dark ? 0.70 : 0.58)
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
