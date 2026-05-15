import Foundation
import Markdown

public struct ParsedMarkdownMessage: Hashable, Sendable {
    public var blocks: [MarkdownBlock]
    public var containsIncompleteCodeFence: Bool

    public init(blocks: [MarkdownBlock], containsIncompleteCodeFence: Bool = false) {
        self.blocks = blocks
        self.containsIncompleteCodeFence = containsIncompleteCodeFence
    }

    public var plainText: String {
        blocks.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

public indirect enum MarkdownBlock: Hashable, Sendable {
    case paragraph([MarkdownInlineRun])
    case heading(level: Int, [MarkdownInlineRun])
    case blockQuote([MarkdownBlock])
    case unorderedList([MarkdownListItem])
    case orderedList(startIndex: Int, [MarkdownListItem])
    case codeBlock(language: String?, code: String)
    case table(MarkdownTable)
    case thematicBreak
    case htmlBlock(String)

    public var plainText: String {
        switch self {
        case let .paragraph(runs):
            MarkdownInlineRun.plainText(runs)
        case let .heading(_, runs):
            MarkdownInlineRun.plainText(runs)
        case let .blockQuote(blocks):
            blocks.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n")
        case let .unorderedList(items):
            items.map { "- \($0.plainText)" }.joined(separator: "\n")
        case let .orderedList(startIndex, items):
            items.enumerated()
                .map { offset, item in "\(startIndex + offset). \(item.plainText)" }
                .joined(separator: "\n")
        case let .codeBlock(_, code):
            code
        case let .table(table):
            table.plainText
        case .thematicBreak:
            ""
        case let .htmlBlock(rawHTML):
            rawHTML
        }
    }
}

public struct MarkdownListItem: Hashable, Sendable {
    public var checkbox: MarkdownCheckbox?
    public var blocks: [MarkdownBlock]

    public init(checkbox: MarkdownCheckbox? = nil, blocks: [MarkdownBlock]) {
        self.checkbox = checkbox
        self.blocks = blocks
    }

    public var plainText: String {
        let prefix: String
        switch checkbox {
        case .checked:
            prefix = "[x] "
        case .unchecked:
            prefix = "[ ] "
        case nil:
            prefix = ""
        }

        return prefix + blocks.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public enum MarkdownCheckbox: Hashable, Sendable {
    case checked
    case unchecked
}

public struct MarkdownTable: Hashable, Sendable {
    public var alignments: [MarkdownTableAlignment?]
    public var header: [[MarkdownInlineRun]]
    public var rows: [[[MarkdownInlineRun]]]

    public init(
        alignments: [MarkdownTableAlignment?] = [],
        header: [[MarkdownInlineRun]],
        rows: [[[MarkdownInlineRun]]]
    ) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }

    public var plainText: String {
        let headerText = header.map(MarkdownInlineRun.plainText).joined(separator: "\t")
        let bodyText = rows
            .map { row in row.map(MarkdownInlineRun.plainText).joined(separator: "\t") }
            .joined(separator: "\n")

        if headerText.isEmpty {
            return bodyText
        }

        if bodyText.isEmpty {
            return headerText
        }

        return "\(headerText)\n\(bodyText)"
    }
}

public enum MarkdownTableAlignment: Hashable, Sendable {
    case leading
    case center
    case trailing
}

public struct MarkdownInlineTraits: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let emphasis = MarkdownInlineTraits(rawValue: 1 << 0)
    public static let strong = MarkdownInlineTraits(rawValue: 1 << 1)
    public static let strikethrough = MarkdownInlineTraits(rawValue: 1 << 2)
    public static let code = MarkdownInlineTraits(rawValue: 1 << 3)
    public static let html = MarkdownInlineTraits(rawValue: 1 << 4)
    public static let image = MarkdownInlineTraits(rawValue: 1 << 5)
}

public struct MarkdownInlineRun: Hashable, Sendable {
    public var text: String
    public var traits: MarkdownInlineTraits
    public var linkDestination: String?
    public var imageSource: String?

    public init(
        text: String,
        traits: MarkdownInlineTraits = [],
        linkDestination: String? = nil,
        imageSource: String? = nil
    ) {
        self.text = text
        self.traits = traits
        self.linkDestination = linkDestination
        self.imageSource = imageSource
    }

    public static func plainText(_ runs: [MarkdownInlineRun]) -> String {
        runs.map(\.text).joined()
    }
}

public struct MarkdownMessageParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> ParsedMarkdownMessage {
        let document = Document(parsing: source)
        return ParsedMarkdownMessage(
            blocks: parseBlocks(document.children),
            containsIncompleteCodeFence: Self.containsIncompleteCodeFence(source)
        )
    }

    public func plainText(from source: String) -> String {
        parse(source).plainText
    }

    private func parseBlocks(_ markups: MarkupChildren) -> [MarkdownBlock] {
        markups.flatMap(parseBlock)
    }

    private func parseBlock(_ markup: Markup) -> [MarkdownBlock] {
        if let paragraph = markup as? Paragraph {
            let runs = parseInlineSequence(paragraph.inlineChildren)
            return runs.isEmpty ? [] : [.paragraph(runs)]
        }

        if let heading = markup as? Heading {
            return [.heading(level: heading.level, parseInlineSequence(heading.inlineChildren))]
        }

        if let blockQuote = markup as? BlockQuote {
            return [.blockQuote(parseBlocks(blockQuote.children))]
        }

        if let unorderedList = markup as? UnorderedList {
            return [.unorderedList(unorderedList.listItems.map(parseListItem))]
        }

        if let orderedList = markup as? OrderedList {
            return [.orderedList(startIndex: Int(orderedList.startIndex), orderedList.listItems.map(parseListItem))]
        }

        if let codeBlock = markup as? CodeBlock {
            return [.codeBlock(language: normalizedLanguage(codeBlock.language), code: codeBlock.code)]
        }

        if let table = markup as? Markdown.Table {
            return [.table(parseTable(table))]
        }

        if markup is ThematicBreak {
            return [.thematicBreak]
        }

        if let htmlBlock = markup as? HTMLBlock {
            return [.htmlBlock(htmlBlock.rawHTML)]
        }

        if markup.childCount > 0 {
            return parseBlocks(markup.children)
        }

        return []
    }

    private func parseListItem(_ item: ListItem) -> MarkdownListItem {
        let checkbox: MarkdownCheckbox?
        switch item.checkbox {
        case .checked:
            checkbox = .checked
        case .unchecked:
            checkbox = .unchecked
        case nil:
            checkbox = nil
        }

        return MarkdownListItem(checkbox: checkbox, blocks: parseBlocks(item.children))
    }

    private func parseTable(_ table: Markdown.Table) -> MarkdownTable {
        let header = table.head.children.compactMap { cell -> [MarkdownInlineRun]? in
            guard let cell = cell as? Markdown.Table.Cell else { return nil }
            return parseInlineSequence(cell.inlineChildren)
        }

        let rows = Array(table.body.rows.map { row in
            row.children.compactMap { cell -> [MarkdownInlineRun]? in
                guard let cell = cell as? Markdown.Table.Cell else { return nil }
                return parseInlineSequence(cell.inlineChildren)
            }
        })

        return MarkdownTable(
            alignments: table.columnAlignments.map(Self.tableAlignment),
            header: header,
            rows: rows
        )
    }

    private func parseInlineSequence<InlineChildren: Sequence>(
        _ children: InlineChildren,
        traits: MarkdownInlineTraits = [],
        linkDestination: String? = nil
    ) -> [MarkdownInlineRun] where InlineChildren.Element == InlineMarkup {
        var runs = [MarkdownInlineRun]()
        for child in children {
            for run in parseInline(child, traits: traits, linkDestination: linkDestination) {
                append(run, to: &runs)
            }
        }
        return runs
    }

    private func parseInline(
        _ markup: InlineMarkup,
        traits: MarkdownInlineTraits,
        linkDestination: String?
    ) -> [MarkdownInlineRun] {
        if let text = markup as? Markdown.Text {
            return [MarkdownInlineRun(text: text.string, traits: traits, linkDestination: linkDestination)]
        }

        if let inlineCode = markup as? InlineCode {
            return [MarkdownInlineRun(text: inlineCode.code, traits: traits.union(.code), linkDestination: linkDestination)]
        }

        if markup is SoftBreak || markup is LineBreak {
            return [MarkdownInlineRun(text: "\n", traits: traits, linkDestination: linkDestination)]
        }

        if let emphasis = markup as? Emphasis {
            return parseInlineSequence(
                emphasis.inlineChildren,
                traits: traits.union(.emphasis),
                linkDestination: linkDestination
            )
        }

        if let strong = markup as? Strong {
            return parseInlineSequence(
                strong.inlineChildren,
                traits: traits.union(.strong),
                linkDestination: linkDestination
            )
        }

        if let strikethrough = markup as? Strikethrough {
            return parseInlineSequence(
                strikethrough.inlineChildren,
                traits: traits.union(.strikethrough),
                linkDestination: linkDestination
            )
        }

        if let link = markup as? Link {
            let destination = normalizedDestination(link.destination)
            let nestedRuns = parseInlineSequence(
                link.inlineChildren,
                traits: traits,
                linkDestination: destination
            )
            if nestedRuns.isEmpty, let destination {
                return [MarkdownInlineRun(text: destination, traits: traits, linkDestination: destination)]
            }
            return nestedRuns
        }

        if let image = markup as? Markdown.Image {
            let altText = parseInlineSequence(image.inlineChildren)
                .map(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let source = normalizedDestination(image.source)
            let label: String
            if altText.isEmpty {
                label = source.map { "[Image: \($0)]" } ?? "[Image]"
            } else {
                label = "[Image: \(altText)]"
            }
            return [
                MarkdownInlineRun(
                    text: label,
                    traits: traits.union(.image),
                    imageSource: source
                ),
            ]
        }

        if let inlineHTML = markup as? InlineHTML {
            return [MarkdownInlineRun(text: inlineHTML.rawHTML, traits: traits.union(.html), linkDestination: linkDestination)]
        }

        if let container = markup as? any InlineContainer {
            return parseInlineSequence(container.inlineChildren, traits: traits, linkDestination: linkDestination)
        }

        return [MarkdownInlineRun(text: markup.plainText, traits: traits, linkDestination: linkDestination)]
    }

    private func append(_ run: MarkdownInlineRun, to runs: inout [MarkdownInlineRun]) {
        guard !run.text.isEmpty else { return }
        if let lastIndex = runs.indices.last,
           runs[lastIndex].traits == run.traits,
           runs[lastIndex].linkDestination == run.linkDestination,
           runs[lastIndex].imageSource == run.imageSource {
            runs[lastIndex].text += run.text
        } else {
            runs.append(run)
        }
    }

    private func normalizedLanguage(_ language: String?) -> String? {
        language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func normalizedDestination(_ destination: String?) -> String? {
        destination?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func tableAlignment(_ alignment: Markdown.Table.ColumnAlignment?) -> MarkdownTableAlignment? {
        switch alignment {
        case .left:
            .leading
        case .center:
            .center
        case .right:
            .trailing
        case nil:
            nil
        }
    }

    private static func containsIncompleteCodeFence(_ source: String) -> Bool {
        struct Fence {
            var marker: Character
            var count: Int
        }

        var openFence: Fence?
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { character in
                character == " " || character == "\t"
            }

            guard let marker = trimmed.first, marker == "`" || marker == "~" else {
                continue
            }

            let count = trimmed.prefix { $0 == marker }.count
            guard count >= 3 else {
                continue
            }

            if let open = openFence {
                if marker == open.marker, count >= open.count {
                    openFence = nil
                }
            } else {
                openFence = Fence(marker: marker, count: count)
            }
        }

        return openFence != nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
