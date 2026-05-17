import Foundation
import HighlightSwift
import PinesCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct MarkdownMessageView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pinesTheme) private var theme

    let messageID: UUID
    let content: String
    let isStreaming: Bool

    @State private var parsedMessage: ParsedMarkdownMessage?

    private var renderTaskID: MarkdownRenderTaskID {
        MarkdownRenderTaskID(
            messageID: messageID,
            contentHash: content.hashValue,
            contentLength: content.count,
            themeKey: theme.template.rawValue,
            colorSchemeKey: theme.colorScheme == .dark ? "dark" : "light",
            dynamicTypeKey: String(describing: dynamicTypeSize),
            isStreaming: isStreaming
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.small) {
            if let parsedMessage, !parsedMessage.blocks.isEmpty {
                ForEach(Array(parsedMessage.blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block, depth: 0)
                }
            } else if !content.isEmpty {
                Text(content)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            guard Self.isSafeURL(url) else {
                return .discarded
            }
            return .systemAction
        })
        .task(id: renderTaskID) {
            if isStreaming {
                do {
                    try await Task.sleep(nanoseconds: 125_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
            }
            let parsed = await MarkdownRenderCache.shared.parsedMessage(
                messageID: messageID,
                content: content,
                themeKey: theme.template.rawValue,
                colorSchemeKey: theme.colorScheme == .dark ? "dark" : "light",
                dynamicTypeKey: String(describing: dynamicTypeSize)
            )
            guard !Task.isCancelled else {
                return
            }
            parsedMessage = parsed
        }
    }

    private static func isSafeURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

private struct MarkdownBlockView: View {
    @Environment(\.pinesTheme) private var theme

    let block: MarkdownBlock
    let depth: Int

    var body: some View {
        switch block {
        case let .paragraph(runs):
            MarkdownInlineText(runs: runs, baseFont: theme.typography.body, baseColor: theme.colors.primaryText)

        case let .heading(level, runs):
            MarkdownInlineText(runs: runs, baseFont: headingFont(level), baseColor: theme.colors.primaryText)
                .padding(.top, level <= 2 ? theme.spacing.xsmall : 0)

        case let .blockQuote(blocks):
            HStack(alignment: .top, spacing: theme.spacing.small) {
                RoundedRectangle(cornerRadius: theme.radius.capsule)
                    .fill(theme.colors.accent)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, nestedBlock in
                        MarkdownBlockView(block: nestedBlock, depth: depth + 1)
                    }
                }
            }
            .padding(theme.spacing.small)
            .background(theme.colors.quoteBackground, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                    .strokeBorder(theme.colors.separator.opacity(0.75), lineWidth: theme.stroke.hairline)
            }

        case let .unorderedList(items):
            MarkdownListView(ordered: false, startIndex: 1, items: items, depth: depth)

        case let .orderedList(startIndex, items):
            MarkdownListView(ordered: true, startIndex: startIndex, items: items, depth: depth)

        case let .codeBlock(language, code):
            MarkdownCodeBlockView(language: language, code: code)

        case let .table(table):
            MarkdownTableView(table: table)

        case .thematicBreak:
            Rectangle()
                .fill(theme.colors.separator)
                .frame(height: theme.stroke.hairline)
                .padding(.vertical, theme.spacing.xsmall)

        case let .htmlBlock(rawHTML):
            MarkdownCodeBlockView(language: "html", code: rawHTML, forcedLabel: "HTML")
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            theme.typography.title
        case 2:
            theme.typography.section
        case 3:
            theme.typography.headline
        default:
            theme.typography.bodyEmphasis
        }
    }
}

private struct MarkdownInlineText: View {
    @Environment(\.pinesTheme) private var theme

    let runs: [MarkdownInlineRun]
    let baseFont: Font
    let baseColor: Color

    var body: some View {
        Text(attributedString)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedString: AttributedString {
        var result = AttributedString()
        for run in runs {
            result += attributedRun(run)
        }
        return result
    }

    private func attributedRun(_ run: MarkdownInlineRun) -> AttributedString {
        var attributed = AttributedString(run.text)
        var font = run.traits.contains(.code) || run.traits.contains(.html) ? theme.typography.code : baseFont

        if run.traits.contains(.strong), !run.traits.contains(.code) {
            font = font.weight(.semibold)
        }
        if run.traits.contains(.emphasis), !run.traits.contains(.code) {
            font = font.italic()
        }

        attributed.font = font
        attributed.foregroundColor = foregroundColor(for: run)

        if run.traits.contains(.code) || run.traits.contains(.html) {
            attributed.backgroundColor = theme.colors.inlineCodeBackground
        }

        if run.traits.contains(.strikethrough) {
            attributed.strikethroughStyle = Text.LineStyle(pattern: .solid, color: theme.colors.secondaryText)
        }

        if let url = safeURL(from: run.linkDestination) {
            attributed.link = url
            attributed.underlineStyle = Text.LineStyle(pattern: .solid, color: theme.colors.link)
        }

        return attributed
    }

    private func foregroundColor(for run: MarkdownInlineRun) -> Color {
        if run.traits.contains(.image) {
            return theme.colors.secondaryText
        }
        if safeURL(from: run.linkDestination) != nil {
            return theme.colors.link
        }
        if run.traits.contains(.code) || run.traits.contains(.html) {
            return theme.colors.primaryText
        }
        return baseColor
    }
}

private struct MarkdownListView: View {
    @Environment(\.pinesTheme) private var theme

    let ordered: Bool
    let startIndex: Int
    let items: [MarkdownListItem]
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .top, spacing: theme.spacing.small) {
                    marker(for: item, offset: offset)
                        .frame(width: markerWidth, alignment: .trailing)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: theme.spacing.xsmall) {
                        if item.blocks.isEmpty {
                            EmptyView()
                        } else {
                            ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                                MarkdownBlockView(block: block, depth: depth + 1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, CGFloat(depth) * theme.spacing.medium)
    }

    private var markerWidth: CGFloat {
        ordered ? 34 : 22
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, offset: Int) -> some View {
        if let checkbox = item.checkbox {
            Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                .font(theme.typography.callout)
                .foregroundStyle(checkbox == .checked ? theme.colors.success : theme.colors.secondaryText)
                .accessibilityLabel(checkbox == .checked ? "Checked" : "Unchecked")
        } else if ordered {
            Text("\(startIndex + offset).")
                .font(theme.typography.bodyEmphasis)
                .foregroundStyle(theme.colors.secondaryText)
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 5, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.top, 7)
                .accessibilityHidden(true)
        }
    }
}

private struct MarkdownTableView: View {
    @Environment(\.pinesTheme) private var theme

    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                if !table.header.isEmpty {
                    GridRow {
                        ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                            tableCell(cell, column: column, isHeader: true)
                        }
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            tableCell(cell, column: column, isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                    .strokeBorder(theme.colors.separator, lineWidth: theme.stroke.hairline)
            }
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
        }
        .scrollIndicators(.visible)
        .pinesExpressiveHorizontalScrollHaptics()
        .overlay(alignment: .leading) {
            LinearGradient(colors: [theme.colors.appBackground.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 18)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [.clear, theme.colors.appBackground.opacity(0.95)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 18)
                .allowsHitTesting(false)
        }
    }

    private func tableCell(_ runs: [MarkdownInlineRun], column: Int, isHeader: Bool) -> some View {
        MarkdownInlineText(
            runs: runs,
            baseFont: isHeader ? theme.typography.caption.weight(.semibold) : theme.typography.caption,
            baseColor: theme.colors.primaryText
        )
        .padding(.horizontal, theme.spacing.small)
        .padding(.vertical, theme.spacing.xsmall)
        .frame(minWidth: 120, maxWidth: 260, alignment: frameAlignment(for: alignment(for: column)))
        .background(isHeader ? theme.colors.tableHeaderBackground : Color.clear)
        .overlay {
            Rectangle()
                .stroke(theme.colors.separator, lineWidth: theme.stroke.hairline)
        }
    }

    private func alignment(for column: Int) -> MarkdownTableAlignment? {
        guard column < table.alignments.count else {
            return nil
        }
        return table.alignments[column]
    }

    private func frameAlignment(for alignment: MarkdownTableAlignment?) -> Alignment {
        switch alignment {
        case .center:
            .center
        case .trailing:
            .trailing
        case .leading, nil:
            .leading
        }
    }
}

private struct MarkdownCodeBlockView: View {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var haptics: PinesHaptics

    let language: String?
    let code: String
    var forcedLabel: String?

    @State private var isSoftWrapped = false
    @State private var didCopy = false
    @State private var highlightedCode: HighlightedCode?

    private var taskID: SyntaxHighlightTaskID {
        SyntaxHighlightTaskID(
            codeHash: code.hashValue,
            codeLength: code.count,
            language: language?.lowercased() ?? "",
            themeKey: theme.template.rawValue,
            colorSchemeKey: theme.colorScheme == .dark ? "dark" : "light"
        )
    }

    private var displayCode: HighlightedCode {
        highlightedCode ?? .plain(code: code, languageLabel: displayLanguageLabel, reason: nil)
    }

    private var displayLanguageLabel: String {
        forcedLabel ?? normalizedDisplayLanguage(language) ?? "Code"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing.small) {
                Label(displayCode.languageLabel, systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(theme.typography.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, theme.spacing.small)
                    .frame(height: 32)
                    .background(theme.colors.controlFill, in: Capsule())

                if let reason = displayCode.reason {
                    Text(reason)
                        .font(theme.typography.caption.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, theme.spacing.small)
                        .frame(height: 32)
                        .background(theme.colors.inlineCodeBackground, in: Capsule())
                }

                Spacer(minLength: theme.spacing.small)

                Button {
                    isSoftWrapped.toggle()
                } label: {
                    Image(systemName: isSoftWrapped ? "text.alignleft" : "arrow.left.and.right")
                }
                .buttonStyle(MarkdownIconButtonStyle())
                .accessibilityLabel(isSoftWrapped ? "Disable code wrapping" : "Enable code wrapping")

                Button {
                    copyToPasteboard(code)
                    haptics.play(.primaryAction)
                    withAnimation(reduceMotion ? nil : theme.motion.copySuccess) {
                        didCopy = true
                    }
                    Task {
                        do {
                            try await Task.sleep(nanoseconds: 1_200_000_000)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(reduceMotion ? nil : theme.motion.fast) {
                                didCopy = false
                            }
                        }
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .symbolEffect(.bounce, options: .nonRepeating, value: didCopy)
                }
                .buttonStyle(MarkdownIconButtonStyle())
                .accessibilityLabel(didCopy ? "Copied code" : "Copy code")
            }
            .padding(.horizontal, theme.spacing.small)
            .padding(.vertical, theme.spacing.xsmall)
            .background(theme.colors.codeHeaderBackground)

            Divider()
                .overlay(theme.colors.separator)

            Group {
                if isSoftWrapped {
                    Text(displayCode.attributedText)
                        .font(theme.typography.code)
                        .foregroundStyle(theme.colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal) {
                        Text(displayCode.attributedText)
                            .font(theme.typography.code)
                            .foregroundStyle(theme.colors.primaryText)
                            .fixedSize(horizontal: true, vertical: true)
                            .frame(minWidth: 1, alignment: .leading)
                    }
                    .scrollIndicators(.visible)
                    .pinesExpressiveHorizontalScrollHaptics()
                    .overlay(alignment: .leading) {
                        LinearGradient(colors: [theme.colors.codeBackground, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 18)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .trailing) {
                        LinearGradient(colors: [.clear, theme.colors.codeBackground], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 18)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(theme.spacing.small)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pinesSurface(.code, padding: 0)
        .task(id: taskID) {
            highlightedCode = nil
            let highlighted = await SyntaxHighlightingService.shared.highlight(
                code: code,
                language: language,
                themeKey: theme.template.rawValue,
                colorSchemeKey: theme.colorScheme == .dark ? "dark" : "light",
                fallbackLabel: displayLanguageLabel
            )
            guard !Task.isCancelled else {
                return
            }
            highlightedCode = highlighted
        }
    }
}

private struct MarkdownIconButtonStyle: ButtonStyle {
    @Environment(\.pinesTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.typography.caption.weight(.semibold))
            .foregroundStyle(configuration.isPressed ? theme.colors.primaryText : theme.colors.secondaryText)
            .frame(width: 32, height: 32)
            .background(
                configuration.isPressed ? theme.colors.controlPressed : theme.colors.controlFill,
                in: RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous)
                    .strokeBorder(configuration.isPressed ? theme.colors.focusRing.opacity(0.45) : theme.colors.controlBorder, lineWidth: theme.stroke.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: theme.radius.control, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : theme.motion.fast, value: configuration.isPressed)
    }
}

private actor MarkdownRenderCache {
    static let shared = MarkdownRenderCache()

    private final class Box: NSObject {
        let parsedMessage: ParsedMarkdownMessage

        init(_ parsedMessage: ParsedMarkdownMessage) {
            self.parsedMessage = parsedMessage
        }
    }

    private let parser = MarkdownMessageParser()
    private let cache: NSCache<NSString, Box>

    private init() {
        cache = NSCache<NSString, Box>()
        cache.countLimit = 240
    }

    func parsedMessage(
        messageID: UUID,
        content: String,
        themeKey: String,
        colorSchemeKey: String,
        dynamicTypeKey: String
    ) -> ParsedMarkdownMessage {
        let key = "\(messageID.uuidString)|\(content.hashValue)|\(content.count)|\(themeKey)|\(colorSchemeKey)|\(dynamicTypeKey)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.parsedMessage
        }

        let parsed = parser.parse(content)
        cache.setObject(Box(parsed), forKey: key)
        return parsed
    }
}

private actor SyntaxHighlightingService {
    static let shared = SyntaxHighlightingService()

    private let highlighter = Highlight()
    private let maxHighlightedBytes = 200_000
    private let timeoutNanoseconds: UInt64 = 750_000_000
    private var cache = [SyntaxHighlightTaskID: HighlightedCode]()
    private var insertionOrder = [SyntaxHighlightTaskID]()

    func highlight(
        code: String,
        language: String?,
        themeKey: String,
        colorSchemeKey: String,
        fallbackLabel: String
    ) async -> HighlightedCode {
        let key = SyntaxHighlightTaskID(
            codeHash: code.hashValue,
            codeLength: code.count,
            language: language?.lowercased() ?? "",
            themeKey: themeKey,
            colorSchemeKey: colorSchemeKey
        )

        if let cached = cache[key] {
            return cached
        }

        let highlighted = await computeHighlight(
            code: code,
            language: language,
            themeKey: themeKey,
            colorSchemeKey: colorSchemeKey,
            fallbackLabel: fallbackLabel
        )
        cache[key] = highlighted
        insertionOrder.append(key)
        while insertionOrder.count > 160, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return highlighted
    }

    private func computeHighlight(
        code: String,
        language: String?,
        themeKey: String,
        colorSchemeKey: String,
        fallbackLabel: String
    ) async -> HighlightedCode {
        guard code.utf8.count <= maxHighlightedBytes else {
            return .plain(code: code, languageLabel: "Plain text", reason: "Large code block")
        }

        let normalizedLanguage = normalizedHighlightLanguage(language)
        if normalizedLanguage == "plaintext" {
            return .plain(code: code, languageLabel: "Plain text", reason: nil)
        }

        let mode: HighlightMode = normalizedLanguage.map { .languageAliasIgnoreIllegal($0) } ?? .automatic
        let colors = Self.highlightColors(themeKey: themeKey, colorSchemeKey: colorSchemeKey)
        let highlighter = highlighter
        let timeoutNanoseconds = timeoutNanoseconds
        do {
            let result = try await withThrowingTaskGroup(of: HighlightResult.self) { group in
                group.addTask {
                    try await highlighter.request(code, mode: mode, colors: colors)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    throw SyntaxHighlightError.timeout
                }

                guard let result = try await group.next() else {
                    throw SyntaxHighlightError.timeout
                }
                group.cancelAll()
                return result
            }

            guard !result.isUndefined else {
                return .plain(code: code, languageLabel: fallbackLabel, reason: "Plain text")
            }

            let label = normalizedLanguage.map(normalizedDisplayLanguage) ?? result.languageName
            return HighlightedCode(
                attributedText: result.attributedText,
                languageLabel: label ?? fallbackLabel,
                isHighlighted: true,
                reason: nil
            )
        } catch {
            return .plain(code: code, languageLabel: fallbackLabel, reason: "Plain text")
        }
    }

    private static func highlightColors(themeKey: String, colorSchemeKey: String) -> HighlightColors {
        let highlightTheme: HighlightTheme
        switch themeKey {
        case PinesThemeTemplate.aurora.rawValue:
            highlightTheme = .tokyoNight
        case PinesThemeTemplate.slate.rawValue:
            highlightTheme = .tokyoNight
        case PinesThemeTemplate.obsidian.rawValue:
            highlightTheme = .tokyoNight
        case PinesThemeTemplate.graphite.rawValue:
            highlightTheme = .grayscale
        case PinesThemeTemplate.paper.rawValue:
            highlightTheme = .papercolor
        case PinesThemeTemplate.sunset.rawValue:
            highlightTheme = .papercolor
        case PinesThemeTemplate.porcelain.rawValue:
            highlightTheme = .github
        default:
            highlightTheme = .github
        }

        return colorSchemeKey == "dark" ? .dark(highlightTheme) : .light(highlightTheme)
    }

    private func normalizedHighlightLanguage(_ language: String?) -> String? {
        guard var normalized = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty
        else {
            return nil
        }

        if normalized.hasPrefix("language-") {
            normalized.removeFirst("language-".count)
        }

        return [
            "c++": "cpp",
            "js": "javascript",
            "jsx": "javascript",
            "md": "markdown",
            "plain": "plaintext",
            "py": "python",
            "sh": "shell",
            "text": "plaintext",
            "ts": "typescript",
            "tsx": "typescript",
            "yml": "yaml",
            "zsh": "shell",
        ][normalized] ?? normalized
    }
}

private struct HighlightedCode: Sendable {
    var attributedText: AttributedString
    var languageLabel: String
    var isHighlighted: Bool
    var reason: String?

    static func plain(code: String, languageLabel: String, reason: String?) -> HighlightedCode {
        HighlightedCode(
            attributedText: AttributedString(code),
            languageLabel: languageLabel,
            isHighlighted: false,
            reason: reason
        )
    }
}

private struct MarkdownRenderTaskID: Hashable {
    var messageID: UUID
    var contentHash: Int
    var contentLength: Int
    var themeKey: String
    var colorSchemeKey: String
    var dynamicTypeKey: String
    var isStreaming: Bool
}

private struct SyntaxHighlightTaskID: Hashable, Sendable {
    var codeHash: Int
    var codeLength: Int
    var language: String
    var themeKey: String
    var colorSchemeKey: String
}

private enum SyntaxHighlightError: Error {
    case timeout
}

private func safeURL(from destination: String?) -> URL? {
    guard let destination,
          let url = URL(string: destination),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else {
        return nil
    }
    return url
}

private func normalizedDisplayLanguage(_ language: String?) -> String? {
    guard let language = language?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !language.isEmpty
    else {
        return nil
    }

    switch language.lowercased() {
    case "bash", "sh", "shell", "zsh":
        return "Shell"
    case "csharp":
        return "C#"
    case "cpp", "c++":
        return "C++"
    case "css":
        return "CSS"
    case "html", "xml":
        return "HTML"
    case "javascript", "js", "jsx":
        return "JavaScript"
    case "json":
        return "JSON"
    case "markdown", "md":
        return "Markdown"
    case "objectivec":
        return "Objective-C"
    case "plaintext", "plain", "text":
        return "Plain text"
    case "postgresql", "pgsql":
        return "PostgreSQL"
    case "python", "py":
        return "Python"
    case "sql":
        return "SQL"
    case "swift":
        return "Swift"
    case "typescript", "ts", "tsx":
        return "TypeScript"
    case "yaml", "yml":
        return "YAML"
    default:
        return language.capitalized
    }
}

func copyToPasteboard(_ value: String) {
    #if os(iOS)
    UIPasteboard.general.string = value
    #endif
}
