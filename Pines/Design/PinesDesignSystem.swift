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
    var listSectionBackground: Color
    var listRowBackground: Color
    var chromeBackground: Color
    var chromeBorder: Color
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
        listSectionBackground = cardBackground
        listRowBackground = cardBackground.opacity(dark ? 0.46 : 0.72)
        chromeBackground = elevatedSurface.opacity(dark ? 0.88 : 0.94)
        chromeBorder = controlBorder

        switch template {
        case .evergreen:
            listSectionBackground = dark ? Color(hex: 0x0C211B) : Color(hex: 0xEAF2EB)
            listRowBackground = dark ? Color(hex: 0x112A23) : Color(hex: 0xFAFCFA)
            chromeBackground = dark ? Color(hex: 0x122A23).opacity(0.92) : Color(hex: 0xFBFCFA).opacity(0.96)
        case .graphite:
            listSectionBackground = dark ? Color(hex: 0x15181D) : Color(hex: 0xECEFF3)
            listRowBackground = dark ? Color(hex: 0x1C2026) : Color(hex: 0xFCFCFD)
            chromeBackground = dark ? Color(hex: 0x20242B).opacity(0.92) : Color(hex: 0xFFFFFF).opacity(0.95)
        case .aurora:
            listSectionBackground = dark ? Color(hex: 0x101735) : Color(hex: 0xE8F0FF)
            listRowBackground = dark ? Color(hex: 0x151E3B) : Color(hex: 0xFAFCFF)
            chromeBackground = dark ? Color(hex: 0x141D3A).opacity(0.92) : Color(hex: 0xFAFCFF).opacity(0.95)
        case .paper:
            listSectionBackground = dark ? Color(hex: 0x20251F) : Color(hex: 0xFFF4E4)
            listRowBackground = dark ? Color(hex: 0x252B24) : Color(hex: 0xFFF9EE)
            chromeBackground = dark ? Color(hex: 0x252B24).opacity(0.92) : Color(hex: 0xFFF9EE).opacity(0.96)
        case .slate:
            listSectionBackground = dark ? Color(hex: 0x102730) : Color(hex: 0xEAF3F7)
            listRowBackground = dark ? Color(hex: 0x18343F) : Color(hex: 0xF6FBFD)
            chromeBackground = dark ? Color(hex: 0x193743).opacity(0.92) : Color(hex: 0xF7FBFD).opacity(0.95)
        case .porcelain:
            listSectionBackground = dark ? Color(hex: 0x242223) : Color(hex: 0xF8F3EA)
            listRowBackground = dark ? Color(hex: 0x2B282A) : Color(hex: 0xFFFDF8)
            chromeBackground = dark ? Color(hex: 0x2B282A).opacity(0.92) : Color(hex: 0xFFFDF8).opacity(0.96)
        case .sunset:
            listSectionBackground = dark ? Color(hex: 0x241409) : Color(hex: 0xFFE9D1)
            listRowBackground = dark ? Color(hex: 0x302010) : Color(hex: 0xFFF5EA)
            chromeBackground = dark ? Color(hex: 0x302010).opacity(0.92) : Color(hex: 0xFFF7EF).opacity(0.96)
        case .obsidian:
            listSectionBackground = dark ? Color(hex: 0x0D1112) : Color(hex: 0xE9EEEE)
            listRowBackground = dark ? Color(hex: 0x141C1F) : Color(hex: 0xFBFCFC)
            chromeBackground = dark ? Color(hex: 0x172124).opacity(0.92) : Color(hex: 0xFFFFFF).opacity(0.95)
        }

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
            listSectionBackground = Color(hex: 0x101735)
            listRowBackground = Color(hex: 0x151E3B)
            chromeBackground = Color(hex: 0x141D3A).opacity(0.92)
        case .paper where dark:
            contentBackground = Color(hex: 0x111412)
            sidebarBackground = Color(hex: 0x171B17)
            sheetBackground = Color(hex: 0x20251F)
            cardBackground = Color(hex: 0x20251F)
            cardBorder = Color.white.opacity(0.11)
            controlFill = Color.white.opacity(0.07)
            controlBorder = Color.white.opacity(0.12)
            listSectionBackground = Color(hex: 0x20251F)
            listRowBackground = Color(hex: 0x252B24)
            chromeBackground = Color(hex: 0x252B24).opacity(0.92)
        case .paper:
            contentBackground = Color(hex: 0xFAF6EC)
            sidebarBackground = Color(hex: 0xEFE6D6)
            sheetBackground = Color(hex: 0xFFF9EE)
            cardBackground = Color(hex: 0xFFF8EC)
            cardBorder = Color.black.opacity(0.085)
            listSectionBackground = Color(hex: 0xFFF4E4)
            listRowBackground = Color(hex: 0xFFF9EE)
            chromeBackground = Color(hex: 0xFFF9EE).opacity(0.96)
        case .slate where !dark:
            sidebarBackground = Color(hex: 0xD8E6EC)
            cardBackground = Color(hex: 0xF6FBFD)
            cardBorder = Color(hex: 0x9BB5C1).opacity(0.34)
            listSectionBackground = Color(hex: 0xEAF3F7)
            listRowBackground = Color(hex: 0xF6FBFD)
            chromeBackground = Color(hex: 0xF7FBFD).opacity(0.95)
        case .porcelain where !dark:
            sidebarBackground = Color(hex: 0xF0ECE3)
            cardBackground = Color(hex: 0xFFFDF8)
            cardBorder = Color(hex: 0xD8CEC2).opacity(0.48)
            listSectionBackground = Color(hex: 0xF8F3EA)
            listRowBackground = Color(hex: 0xFFFDF8)
            chromeBackground = Color(hex: 0xFFFDF8).opacity(0.96)
        case .sunset where dark:
            sidebarBackground = Color(hex: 0x1D1008)
            cardBackground = Color(hex: 0x2A180C)
            cardBorder = Color(hex: 0xFFB15B).opacity(0.16)
            controlFill = Color.white.opacity(0.075)
            controlBorder = Color(hex: 0xFFB15B).opacity(0.18)
            listSectionBackground = Color(hex: 0x241409)
            listRowBackground = Color(hex: 0x302010)
            chromeBackground = Color(hex: 0x302010).opacity(0.92)
        case .sunset:
            sidebarBackground = Color(hex: 0xF4E0C8)
            cardBackground = Color(hex: 0xFFF3E5)
            cardBorder = Color(hex: 0xD66B00).opacity(0.16)
            listSectionBackground = Color(hex: 0xFFE9D1)
            listRowBackground = Color(hex: 0xFFF5EA)
            chromeBackground = Color(hex: 0xFFF7EF).opacity(0.96)
        default:
            break
        }
        chromeBorder = controlBorder
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

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
