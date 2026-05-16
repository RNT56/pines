import SwiftUI

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
